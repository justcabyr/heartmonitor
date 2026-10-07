import Combine
import Foundation
import HealthKit
import ThresholdEngine

enum MonitoringSessionState: Equatable {
    case idle
    case running
    case paused
    case ended
}

enum HealthAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
}

private enum HeartRateQuantity {
    static let sampleType = HKQuantityType(.heartRate)
    static let unit = HKUnit.count().unitDivided(by: .minute())
}

enum HeartRateMonitorError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Heart rate is not available on this watch."
        case .authorizationDenied:
            return "Health access is off. Allow heart rate for HeartThreshold in the Watch app on iPhone, then start again."
        }
    }
}

@MainActor
final class HeartRateMonitor: NSObject, ObservableObject {
    @Published private(set) var currentBPM: Double?
    @Published private(set) var lastSampleDate: Date?
    @Published private(set) var authorizationState: HealthAuthorizationState = .notDetermined
    @Published private(set) var sessionState: MonitoringSessionState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var finishedSummary: MonitoringSummary?
    @Published private(set) var settings: HeartRateSettings
    @Published private(set) var zone: HeartRateZone = .stale
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var batterySecondsRemaining: TimeInterval?
    @Published private(set) var displayedElapsed: TimeInterval = 0
    @Published private(set) var isRecovering = false
    @Published private(set) var openSessionScreen = false

    private let healthStore = HKHealthStore()
    private let settingsStore: WatchSettingsStore
    private let recorder: SessionRecorder
    private let haptics = HapticAlertService()
    private let batteryGuard = BatteryGuard()
    private var engine: ThresholdEngine?
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var frozenElapsed: TimeInterval = 0
    private var didFreezeElapsed = false
    private var requestedEndReason: EndReason?
    private var suppressAutomaticFinalize = false
    private var hasFreshSample = false
    private var wasStale = false
    private var zoneTimer: Task<Void, Never>?
    private var isStopping = false
    private var didEndForBattery = false
    private var didRequestRecovery = false
    private var wristDown = false
    private var lastDisplayUpdate = Date.distantPast
    private var measuredBPM: Double?
    private var measuredZone: HeartRateZone = .stale
    private var latestSampleDate: Date?
    private var measuredBatteryLevel: Double?
    private var measuredBatteryRemaining: TimeInterval?

    init(settingsStore stored: WatchSettingsStore? = nil) {
        let settingsStore = stored ?? WatchSettingsStore()
        self.settingsStore = settingsStore
        let loaded = settingsStore.load()
        settings = loaded.settings
        recorder = SessionRecorder()
        super.init()
        if loaded.rejectedStoredValue {
            errorMessage = "Saved alert settings were invalid, so the defaults are in use."
        }
        recorder.onRecordingError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
        }
        batteryGuard.levelLimit = { [weak self] in
            self?.settings.batteryGuardLevel ?? HeartRateSettings.startScreen.batteryGuardLevel
        }
        batteryGuard.onReading = { [weak self] level, remaining in
            self?.noteBattery(level: level, remaining: remaining)
        }
        batteryGuard.onDepleted = { [weak self] in
            self?.endForBatteryGuard()
        }
    }

    var stateTitle: String {
        switch sessionState {
        case .idle:
            return "Not started"
        case .running:
            return currentBPM == nil ? "Waiting for heart rate" : "Running"
        case .paused:
            return "Paused"
        case .ended:
            return "Ended"
        }
    }

    func elapsedTime(at now: Date) -> TimeInterval {
        if didFreezeElapsed {
            return frozenElapsed
        }
        if let workoutBuilder, sessionState == .running || sessionState == .paused {
            return max(0, workoutBuilder.elapsedTime(at: now))
        }
        return frozenElapsed
    }

    func consumeOpenSessionScreen() {
        openSessionScreen = false
    }

    func setWristDown(_ wristDown: Bool) {
        guard self.wristDown != wristDown else { return }
        self.wristDown = wristDown
        publishDisplay(at: Date(), force: true)
    }

    /// Called from `handleActiveWorkoutRecovery`. HealthKit is asked before this returns.
    func recoverAfterCrash() {
        guard !didRequestRecovery else { return }
        beginRecoveryRequest()
    }

    /// Keeps Start disabled until the launch recovery check runs. The check itself waits
    /// so `handleActiveWorkoutRecovery` can claim the HealthKit call first.
    func prepareForLaunchRecovery() {
        guard !didRequestRecovery else { return }
        guard ActiveSessionStore.current() != nil else { return }
        isRecovering = true
    }

    /// Manual relaunch: resume a stored session, or finalize it when HealthKit has nothing to restore.
    func recoverInterruptedSessionIfNeeded() {
        guard !didRequestRecovery else { return }
        guard ActiveSessionStore.current() != nil else {
            isRecovering = false
            return
        }
        beginRecoveryRequest()
    }

    func startMonitoring() async throws {
        errorMessage = nil
        openSessionScreen = false
        guard !isRecovering else { return }
        guard sessionState == .idle || sessionState == .ended else { return }

        if recorder.hasOpenSession {
            finalize(reason: .error, at: Date(), present: false)
            if recorder.hasOpenSession {
                if errorMessage == nil {
                    throw surface(
                        RecordingStoreError.invalidBundle("The previous recording could not be saved.")
                    )
                }
                throw RecordingStoreError.invalidBundle(
                    errorMessage ?? "The previous recording could not be saved."
                )
            }
        }

        do {
            try recorder.ensureRoomToStart()
        } catch {
            throw surface(error)
        }

        finishedSummary = nil
        requestedEndReason = nil
        currentBPM = nil
        measuredBPM = nil
        lastSampleDate = nil
        latestSampleDate = nil
        frozenElapsed = 0
        didFreezeElapsed = false
        displayedElapsed = 0
        hasFreshSample = false
        wasStale = false
        measuredZone = .stale
        zone = .stale
        measuredBatteryLevel = nil
        measuredBatteryRemaining = nil
        batteryLevel = nil
        batterySecondsRemaining = nil
        lastDisplayUpdate = .distantPast
        didEndForBattery = false
        engine = ThresholdEngine(settings: settings)

        guard HKHealthStore.isHealthDataAvailable() else {
            throw surface(HeartRateMonitorError.healthDataUnavailable)
        }

        try await ensureAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            throw surface(error)
        }

        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = heartRateOnlyDataSource(configuration: configuration)
        session.delegate = self
        builder.delegate = self
        workoutSession = session
        workoutBuilder = builder

        let start = Date()
        let sessionId: UUID
        do {
            sessionId = try recorder.start(settings: settings, at: start)
        } catch {
            session.end()
            releaseWorkout()
            stopZoneTimer()
            sessionState = .ended
            throw surface(error)
        }
        ActiveSessionStore.save(sessionId)

        sessionState = .running
        startZoneTimer()
        session.startActivity(with: start)
        do {
            try await builder.beginCollection(at: start)
        } catch {
            let endDate = Date()
            freezeElapsed(using: builder, at: endDate)
            requestedEndReason = .error
            finalize(reason: .error, at: endDate, present: false)
            session.end()
            releaseWorkout()
            stopZoneTimer()
            sessionState = .ended
            throw surface(error)
        }
        batteryGuard.start()
    }

    func pause() {
        workoutSession?.pause()
    }

    func resume() {
        workoutSession?.resume()
    }

    func stopMonitoring(saveToHealth: Bool, reason: EndReason = .user) async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        batteryGuard.stop()
        guard let session = workoutSession, let builder = workoutBuilder else {
            if recorder.hasOpenSession {
                finalize(reason: reason, at: Date(), present: true)
            }
            stopZoneTimer()
            return
        }

        stopZoneTimer()
        suppressAutomaticFinalize = true
        requestedEndReason = reason
        let endDate = Date()
        freezeElapsed(using: builder, at: endDate)

        do {
            if saveToHealth {
                try await builder.endCollection(at: endDate)
                _ = try await builder.finishWorkout()
            } else {
                builder.discardWorkout()
            }
        } catch {
            errorMessage = error.localizedDescription
            requestedEndReason = .error
        }

        await Task.yield()
        session.end()
        await Task.yield()
        if finishedSummary == nil {
            finalize(reason: requestedEndReason ?? reason, at: endDate, present: true)
        }
        sessionState = .ended
        releaseWorkout()
        stopZoneTimer()
        suppressAutomaticFinalize = false
    }

    func setTargetBPM(_ bpm: Double) {
        var next = settings
        next.targetBPM = bpm.rounded()
        commit(next)
    }

    func setWarningFraction(_ fraction: Double) {
        var next = settings
        next.warningFraction = fraction
        commit(next)
    }

    func setSaveToHealth(_ saveToHealth: Bool) {
        var next = settings
        next.saveToHealth = saveToHealth
        commit(next)
    }

    func flushRecording() {
        do {
            try recorder.flush()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginRecoveryRequest() {
        didRequestRecovery = true
        isRecovering = true
        healthStore.recoverActiveWorkoutSession { [weak self] session, error in
            Task { @MainActor in
                guard let self else { return }
                await self.completeRecovery(session: session, error: error)
            }
        }
    }

    private func completeRecovery(session: HKWorkoutSession?, error: Error?) async {
        defer { isRecovering = false }
        let storedId = ActiveSessionStore.current()

        if let storedId {
            do {
                switch try recorder.prepareRecovery(id: storedId) {
                case .finished(let summary):
                    commitFinished(summary, present: true)
                    if let session {
                        await endHealthSession(session)
                    }
                case .open(let lastSampleDate):
                    if let session, Self.canContinue(session) {
                        continueRecovered(session, lastSampleDate: lastSampleDate)
                    } else {
                        requestedEndReason = .interrupted
                        sessionState = .ended
                        if let session {
                            await endHealthSession(session)
                        }
                        finalize(reason: .interrupted, at: Date(), present: true)
                    }
                }
            } catch {
                if let session {
                    await endHealthSession(session)
                }
                ActiveSessionStore.clear()
                errorMessage = error.localizedDescription
                sessionState = .idle
            }
            return
        }

        if let session {
            await endHealthSession(session)
            errorMessage = "A workout was still running, but its recording could not be found."
            sessionState = .idle
            return
        }

        if let error {
            errorMessage = error.localizedDescription
        }
    }

    private func continueRecovered(_ session: HKWorkoutSession, lastSampleDate: Date?) {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = heartRateOnlyDataSource(configuration: session.workoutConfiguration)
        session.delegate = self
        builder.delegate = self
        workoutSession = session
        workoutBuilder = builder
        finishedSummary = nil
        requestedEndReason = nil
        didFreezeElapsed = false
        frozenElapsed = 0
        hasFreshSample = false
        wasStale = false
        measuredBPM = nil
        currentBPM = nil
        measuredZone = .stale
        zone = .stale
        // A redelivered sample can miss the stored timestamp by a fraction of a millisecond.
        let dedupeUntil = lastSampleDate?.addingTimeInterval(0.001)
        latestSampleDate = dedupeUntil
        self.lastSampleDate = dedupeUntil
        engine = ThresholdEngine(settings: settings)
        switch session.state {
        case .paused:
            sessionState = .paused
            stopZoneTimer()
        default:
            sessionState = .running
            startZoneTimer()
        }
        recordEvent(.recovered, at: Date(), flushImmediately: true)
        publishDisplay(at: Date(), force: true)
        didEndForBattery = false
        batteryGuard.start()
        openSessionScreen = true
    }

    private func endHealthSession(_ session: HKWorkoutSession) async {
        suppressAutomaticFinalize = true
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = self
        workoutSession = session
        workoutBuilder = builder
        if session.state != .ended && session.state != .stopped {
            builder.discardWorkout()
            session.end()
            await Task.yield()
            await Task.yield()
        }
        releaseWorkout()
        batteryGuard.stop()
        stopZoneTimer()
        suppressAutomaticFinalize = false
    }

    private static func canContinue(_ session: HKWorkoutSession) -> Bool {
        switch session.state {
        case .running, .paused, .prepared:
            return true
        default:
            return false
        }
    }

    private func ensureAuthorization() async throws {
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        authorizationState = Self.authorizationState(for: status)
        guard status != .sharingAuthorized else { return }
        guard status == .notDetermined else {
            throw surface(HeartRateMonitorError.authorizationDenied)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [HeartRateQuantity.sampleType])
        } catch {
            authorizationState = .denied
            throw surface(error)
        }

        let updated = healthStore.authorizationStatus(for: workoutType)
        authorizationState = Self.authorizationState(for: updated)
        guard updated == .sharingAuthorized else {
            throw surface(HeartRateMonitorError.authorizationDenied)
        }
    }

    private func heartRateOnlyDataSource(configuration: HKWorkoutConfiguration) -> HKLiveWorkoutDataSource {
        let dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        for type in dataSource.typesToCollect where type != HeartRateQuantity.sampleType {
            dataSource.disableCollection(for: type)
        }
        dataSource.enableCollection(for: HeartRateQuantity.sampleType, predicate: nil)
        return dataSource
    }

    private func acceptSample(bpm: Double, at timestamp: Date) {
        guard sessionState == .running || sessionState == .paused else { return }
        guard bpm.isFinite else {
            errorMessage = "Heart rate reading was not a number."
            return
        }
        if let latestSampleDate, timestamp <= latestSampleDate {
            return
        }
        if sessionState == .paused {
            notePausedSample(bpm: bpm, at: timestamp)
        } else {
            evaluateAndAlert(bpm: bpm, at: timestamp)
        }
        measuredBPM = bpm
        latestSampleDate = timestamp
        publishDisplay(at: timestamp, force: !wristDown)
        do {
            try recorder.recordSample(bpm: bpm, at: timestamp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func evaluateAndAlert(bpm: Double, at timestamp: Date) {
        guard var engine else { return }
        if wasStale {
            recordEvent(.staleEnd, at: timestamp, flushImmediately: false)
            wasStale = false
        }
        let evaluation = engine.evaluate(bpm: bpm, at: timestamp)
        self.engine = engine
        hasFreshSample = true
        measuredZone = evaluation.zone
        if let alert = evaluation.alert {
            deliver(alert, at: timestamp)
        }
    }

    private func notePausedSample(bpm: Double, at timestamp: Date) {
        if wasStale {
            recordEvent(.staleEnd, at: timestamp, flushImmediately: false)
            wasStale = false
        }
        engine?.markFresh(at: timestamp)
        hasFreshSample = true
        measuredZone = ThresholdEngine.zone(for: bpm, settings: settings)
    }

    private func refreshZone(at now: Date) {
        guard sessionState == .running, hasFreshSample, var engine else { return }
        let evaluation = engine.advance(to: now)
        self.engine = engine
        measuredZone = evaluation.zone
        if let alert = evaluation.alert {
            deliver(alert, at: now)
        }
        publishDisplay(at: now, force: !wristDown)
    }

    private func deliver(_ alert: ThresholdAlert, at date: Date) {
        switch alert {
        case .warning:
            haptics.warning()
            recordEvent(.warning, at: date, flushImmediately: false)
        case .threshold:
            haptics.thresholdReached()
            recordEvent(.threshold, at: date, flushImmediately: false)
        case .stale:
            guard !wasStale else { return }
            haptics.attention()
            recordEvent(.staleStart, at: date, flushImmediately: false)
            wasStale = true
        }
    }

    private func noteBattery(level: Double?, remaining: TimeInterval?) {
        measuredBatteryLevel = level
        measuredBatteryRemaining = remaining
        publishDisplay(at: Date(), force: !wristDown)
    }

    private func publishDisplay(at date: Date, force: Bool) {
        if !force && wristDown && date.timeIntervalSince(lastDisplayUpdate) < AppConstants.wristDownDisplayInterval {
            return
        }
        currentBPM = measuredBPM
        zone = measuredZone
        lastSampleDate = latestSampleDate
        batteryLevel = measuredBatteryLevel
        batterySecondsRemaining = measuredBatteryRemaining
        displayedElapsed = elapsedTime(at: date)
        lastDisplayUpdate = date
    }

    private func endForBatteryGuard() {
        guard !didEndForBattery else { return }
        guard sessionState == .running || sessionState == .paused else { return }
        didEndForBattery = true
        recordEvent(.batteryGuard, at: Date(), flushImmediately: true)
        haptics.batteryGuard()
        Task { await stopMonitoring(saveToHealth: settings.saveToHealth, reason: .batteryGuard) }
    }

    private func commit(_ next: HeartRateSettings) {
        guard next != settings else { return }
        guard next.isWithinLimits else {
            errorMessage = WatchSettingsError.invalid.localizedDescription
            return
        }
        do {
            try settingsStore.save(next)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let sessionIsOpen = sessionState == .running || sessionState == .paused
        settings = next
        engine?.replaceSettings(next)
        if sessionIsOpen {
            recordEvent(.settingsChanged, at: Date(), flushImmediately: true)
        }
    }

    private func startZoneTimer() {
        zoneTimer?.cancel()
        zoneTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.refreshZone(at: Date())
            }
        }
    }

    private func stopZoneTimer() {
        zoneTimer?.cancel()
        zoneTimer = nil
    }

    private func applySessionState(_ state: HKWorkoutSessionState, at date: Date) {
        switch state {
        case .running:
            if sessionState == .paused {
                recordEvent(.resumed, at: date, flushImmediately: true)
                if hasFreshSample && !wasStale {
                    engine?.markFresh(at: date)
                }
                startZoneTimer()
            }
            sessionState = .running
        case .paused:
            if sessionState == .running {
                recordEvent(.paused, at: date, flushImmediately: true)
            }
            stopZoneTimer()
            sessionState = .paused
        case .ended, .stopped:
            if let workoutBuilder {
                freezeElapsed(using: workoutBuilder, at: date)
            }
            batteryGuard.stop()
            if suppressAutomaticFinalize {
                stopZoneTimer()
                break
            }
            if finishedSummary == nil {
                finalize(reason: requestedEndReason ?? .interrupted, at: date, present: true)
            }
            sessionState = .ended
            releaseWorkout()
            stopZoneTimer()
        case .notStarted, .prepared:
            break
        @unknown default:
            errorMessage = "The workout session entered an unknown state."
            if let workoutBuilder {
                freezeElapsed(using: workoutBuilder, at: date)
            }
            batteryGuard.stop()
            if finishedSummary == nil {
                finalize(reason: .error, at: date, present: true)
            }
            sessionState = .ended
            releaseWorkout()
            stopZoneTimer()
        }
    }

    private func recordEvent(_ kind: SessionEventKind, at date: Date, flushImmediately: Bool) {
        do {
            try recorder.record(kind: kind, at: date, flushImmediately: flushImmediately)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finalize(reason: EndReason, at date: Date, present: Bool) {
        guard finishedSummary == nil else { return }
        do {
            let summary = try recorder.finish(reason: reason, at: date)
            commitFinished(summary, present: present)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitFinished(_ summary: MonitoringSummary, present: Bool) {
        guard finishedSummary == nil else {
            RecordingTransfer.queue(summary.id)
            ActiveSessionStore.clear()
            return
        }
        finishedSummary = summary
        RecordingTransfer.queue(summary.id)
        ActiveSessionStore.clear()
        batteryGuard.stop()
        stopZoneTimer()
        sessionState = .ended
        if present {
            openSessionScreen = true
        }
    }

    private func freezeElapsed(using builder: HKLiveWorkoutBuilder, at date: Date) {
        guard !didFreezeElapsed else { return }
        frozenElapsed = max(0, builder.elapsedTime(at: date))
        didFreezeElapsed = true
    }

    private func releaseWorkout() {
        workoutSession = nil
        workoutBuilder = nil
    }

    @discardableResult
    private func surface(_ error: Error) -> Error {
        errorMessage = error.localizedDescription
        return error
    }

    private static func authorizationState(for status: HKAuthorizationStatus) -> HealthAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

extension HeartRateMonitor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            applySessionState(toState, at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            if let workoutBuilder {
                freezeElapsed(using: workoutBuilder, at: Date())
            }
            errorMessage = message
            batteryGuard.stop()
            if finishedSummary == nil {
                finalize(reason: .error, at: Date(), present: true)
            }
            sessionState = .ended
            releaseWorkout()
            stopZoneTimer()
        }
    }
}

extension HeartRateMonitor: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(HeartRateQuantity.sampleType),
              let statistics = workoutBuilder.statistics(for: HeartRateQuantity.sampleType),
              let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval() else {
            return
        }
        let bpm = quantity.doubleValue(for: HeartRateQuantity.unit)
        let timestamp = interval.end
        Task { @MainActor in
            acceptSample(bpm: bpm, at: timestamp)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
