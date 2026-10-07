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

    private let healthStore = HKHealthStore()
    private let settingsStore: WatchSettingsStore
    private let recorder: SessionRecorder
    private let haptics = HapticAlertService()
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

    func startMonitoring() async throws {
        errorMessage = nil
        guard sessionState == .idle || sessionState == .ended else { return }

        if recorder.hasOpenSession {
            finalize(reason: .error, at: Date())
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

        finishedSummary = nil
        requestedEndReason = nil
        currentBPM = nil
        lastSampleDate = nil
        frozenElapsed = 0
        didFreezeElapsed = false
        hasFreshSample = false
        wasStale = false
        zone = .stale
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
        do {
            try recorder.start(settings: settings, at: start)
        } catch {
            session.end()
            releaseWorkout()
            stopZoneTimer()
            sessionState = .ended
            throw surface(error)
        }

        sessionState = .running
        startZoneTimer()
        session.startActivity(with: start)
        do {
            try await builder.beginCollection(at: start)
        } catch {
            let endDate = Date()
            freezeElapsed(using: builder, at: endDate)
            requestedEndReason = .error
            finalize(reason: .error, at: endDate)
            session.end()
            releaseWorkout()
            stopZoneTimer()
            sessionState = .ended
            if finishedSummary != nil {
                throw surface(error)
            }
            throw error
        }
    }

    func pause() {
        workoutSession?.pause()
    }

    func resume() {
        workoutSession?.resume()
    }

    func stopMonitoring(saveToHealth: Bool) async {
        guard let session = workoutSession, let builder = workoutBuilder else {
            if recorder.hasOpenSession {
                finalize(reason: .user, at: Date())
            }
            return
        }

        stopZoneTimer()
        suppressAutomaticFinalize = true
        requestedEndReason = .user
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
            finalize(reason: requestedEndReason ?? .user, at: endDate)
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
        guard sessionState != .ended else { return }
        guard bpm.isFinite else {
            errorMessage = "Heart rate reading was not a number."
            return
        }
        if let lastSampleDate, timestamp <= lastSampleDate {
            return
        }
        if sessionState == .paused {
            notePausedSample(bpm: bpm, at: timestamp)
        } else if sessionState == .running {
            evaluateAndAlert(bpm: bpm, at: timestamp)
        }
        currentBPM = bpm
        lastSampleDate = timestamp
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
        zone = evaluation.zone
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
        zone = ThresholdEngine.zone(for: bpm, settings: settings)
    }

    private func refreshZone(at now: Date) {
        guard sessionState == .running, hasFreshSample, var engine else { return }
        let evaluation = engine.advance(to: now)
        self.engine = engine
        zone = evaluation.zone
        if let alert = evaluation.alert {
            deliver(alert, at: now)
        }
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
            if suppressAutomaticFinalize {
                stopZoneTimer()
                break
            }
            if finishedSummary == nil {
                finalize(reason: requestedEndReason ?? .interrupted, at: date)
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
            if finishedSummary == nil {
                finalize(reason: .error, at: date)
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

    private func finalize(reason: EndReason, at date: Date) {
        guard finishedSummary == nil else { return }
        do {
            finishedSummary = try recorder.finish(reason: reason, at: date)
        } catch {
            errorMessage = error.localizedDescription
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
            if finishedSummary == nil {
                finalize(reason: .error, at: Date())
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
