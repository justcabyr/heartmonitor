import Foundation
import ThresholdEngine

@MainActor
final class SessionRecorder {
    static let sampleFlushCount = 12
    static let flushInterval: TimeInterval = 60

    var onRecordingError: ((Error) -> Void)?

    private let store: RecordingStore
    private var session: OpenSession?
    private var pendingSamples: [HeartRateSample] = []
    private var pendingEvents: [SessionEvent] = []
    private var closedSummary: MonitoringSummary?
    private var accepting = false
    private var flushTask: Task<Void, Never>?

    private struct OpenSession {
        let id: UUID
        let folder: URL
        let startedAt: Date
    }

    enum Recovery {
        case finished(MonitoringSummary)
        case open(lastSampleDate: Date?)
    }

    init(store: RecordingStore? = nil) {
        self.store = store ?? RecordingStore()
    }

    var hasOpenSession: Bool {
        session != nil
    }

    func ensureRoomToStart() throws {
        try store.ensureRoomForSession()
    }

    @discardableResult
    func start(settings: HeartRateSettings, at startedAt: Date) throws -> UUID {
        if session != nil {
            throw RecordingStoreError.invalidBundle("A recording is already open.")
        }
        closedSummary = nil
        pendingSamples = []
        pendingEvents = []
        let header = SessionHeader(
            id: UUID(),
            startedAt: startedAt,
            schemaVersion: AppConstants.schemaVersion,
            deviceModel: try WatchHardware.modelIdentifier(),
            watchAppVersion: try WatchHardware.appVersion(),
            settings: settings
        )
        let folder = try store.createSession(header)
        let stored: SessionHeader
        do {
            stored = try store.readHeader(in: folder)
        } catch {
            do {
                try store.removeFolder(folder)
            } catch {
                throw RecordingStoreError.invalidBundle(
                    "The recording could not be started, and the partial folder could not be removed."
                )
            }
            throw error
        }
        session = OpenSession(id: stored.id, folder: folder, startedAt: stored.startedAt)
        accepting = true
        scheduleFlush()
        return stored.id
    }

    func prepareRecovery(id: UUID) throws -> Recovery {
        if session != nil {
            throw RecordingStoreError.invalidBundle("A recording is already open.")
        }
        let folder = try store.existingFolder(for: id)
        let header = try store.readHeader(in: folder)
        guard header.id == id else {
            throw RecordingStoreError.invalidBundle("The session id does not match its folder.")
        }
        if let summary = try store.summaryIfPresent(in: folder) {
            try store.ensureBundle(matching: summary, in: folder)
            closedSummary = summary
            return .finished(summary)
        }
        let samples = try store.readSamples(in: folder)
        closedSummary = nil
        pendingSamples = []
        pendingEvents = []
        session = OpenSession(id: header.id, folder: folder, startedAt: header.startedAt)
        accepting = true
        scheduleFlush()
        let lastSampleDate = samples.map(\.offset).max().map { header.startedAt.addingTimeInterval($0) }
        return .open(lastSampleDate: lastSampleDate)
    }

    func recordSample(bpm: Double, at timestamp: Date) throws {
        guard accepting, let session else { return }
        guard bpm.isFinite else {
            throw RecordingStoreError.invalidBundle("Heart rate reading was not a number.")
        }
        let offset = max(0, timestamp.timeIntervalSince(session.startedAt))
        pendingSamples.append(HeartRateSample(offset: offset, bpm: bpm))
        if pendingSamples.count >= Self.sampleFlushCount {
            try flush()
        }
    }

    func record(kind: SessionEventKind, at timestamp: Date, flushImmediately: Bool) throws {
        guard accepting, let session else { return }
        let offset = max(0, timestamp.timeIntervalSince(session.startedAt))
        pendingEvents.append(SessionEvent(offset: offset, kind: kind))
        if flushImmediately || pendingSamples.count >= Self.sampleFlushCount {
            try flush()
        }
    }

    func flush() throws {
        defer {
            if accepting {
                scheduleFlush()
            }
        }
        try writePending()
    }

    func finish(reason: EndReason, at endedAt: Date) throws -> MonitoringSummary {
        if let closedSummary {
            return closedSummary
        }
        guard session != nil else {
            throw RecordingStoreError.noActiveSession
        }
        accepting = false
        flushTask?.cancel()
        flushTask = nil
        do {
            try writePending()
            let recording = try makeRecording(endedAt: endedAt, reason: reason)
            guard let folder = session?.folder else {
                throw RecordingStoreError.noActiveSession
            }
            try store.writeFinished(recording, in: folder)
            closedSummary = recording.summary
            session = nil
            pendingSamples = []
            pendingEvents = []
            return recording.summary
        } catch {
            accepting = true
            scheduleFlush()
            throw error
        }
    }

    private func writePending() throws {
        guard let session else { return }
        if !pendingSamples.isEmpty {
            try store.appendSamples(pendingSamples, to: session.folder)
            pendingSamples.removeAll()
        }
        if !pendingEvents.isEmpty {
            try store.appendEvents(pendingEvents, to: session.folder)
            pendingEvents.removeAll()
        }
    }

    private func makeRecording(endedAt: Date, reason: EndReason) throws -> SessionRecording {
        guard let session else {
            throw RecordingStoreError.noActiveSession
        }
        let header = try store.readHeader(in: session.folder)
        let samples = try store.readSamples(in: session.folder)
        let events = try store.readEvents(in: session.folder)
        guard header.schemaVersion == AppConstants.schemaVersion else {
            throw RecordingStoreError.invalidBundle("The recording version is not supported.")
        }
        let endOffset = max(0, endedAt.timeIntervalSince(header.startedAt))
        let calculated = SummaryCalculator.calculate(
            samples: samples,
            events: events,
            endOffset: endOffset,
            warningBPM: header.settings.warningBPM,
            targetBPM: header.settings.targetBPM,
            gapThreshold: SummaryCalculator.gapThresholdSeconds
        )
        guard calculated.sampleCount == samples.count else {
            throw RecordingStoreError.invalidBundle("The sample count does not match the recording.")
        }
        let summary = MonitoringSummary(
            id: header.id,
            startedAt: header.startedAt,
            endedAt: endedAt,
            activeSeconds: calculated.activeSeconds,
            sampleCount: samples.count,
            avgBPM: calculated.avgBPM,
            minBPM: calculated.minBPM,
            maxBPM: calculated.maxBPM,
            warningEvents: events.filter { $0.kind == .warning }.count,
            thresholdEvents: events.filter { $0.kind == .threshold }.count,
            secondsAboveWarning: calculated.secondsAboveWarning,
            secondsAboveTarget: calculated.secondsAboveTarget,
            gapSeconds: calculated.gapSeconds,
            endReason: reason
        )
        return SessionRecording(
            schemaVersion: header.schemaVersion,
            id: header.id,
            sourcePlatform: RecordingValidator.sourcePlatform,
            deviceModel: header.deviceModel,
            watchAppVersion: header.watchAppVersion,
            startedAt: header.startedAt,
            settings: header.settings,
            samples: samples,
            events: events,
            summary: summary
        )
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let nanoseconds = UInt64(Self.flushInterval * 1_000_000_000)
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            do {
                try self.flush()
            } catch {
                self.onRecordingError?(error)
            }
        }
    }
}
