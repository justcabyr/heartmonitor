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

    private let healthStore = HKHealthStore()
    private let recorder: SessionRecorder
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var frozenElapsed: TimeInterval = 0
    private var didFreezeElapsed = false
    private var requestedEndReason: EndReason?
    private var suppressAutomaticFinalize = false

    override init() {
        recorder = SessionRecorder()
        super.init()
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
            try recorder.start(settings: HeartRateSettings.startScreen, at: start)
        } catch {
            session.end()
            releaseWorkout()
            sessionState = .ended
            throw surface(error)
        }

        sessionState = .running
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
        suppressAutomaticFinalize = false
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
        currentBPM = bpm
        lastSampleDate = timestamp
        do {
            try recorder.recordSample(bpm: bpm, at: timestamp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySessionState(_ state: HKWorkoutSessionState, at date: Date) {
        switch state {
        case .running:
            if sessionState == .paused {
                recordEvent(.resumed, at: date)
            }
            sessionState = .running
        case .paused:
            if sessionState == .running {
                recordEvent(.paused, at: date)
            }
            sessionState = .paused
        case .ended, .stopped:
            if let workoutBuilder {
                freezeElapsed(using: workoutBuilder, at: date)
            }
            if suppressAutomaticFinalize {
                break
            }
            if finishedSummary == nil {
                finalize(reason: requestedEndReason ?? .interrupted, at: date)
            }
            sessionState = .ended
            releaseWorkout()
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
        }
    }

    private func recordEvent(_ kind: SessionEventKind, at date: Date) {
        do {
            try recorder.record(kind: kind, at: date, flushImmediately: true)
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
