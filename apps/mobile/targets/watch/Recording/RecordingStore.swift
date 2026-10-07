import Darwin
import Foundation
import ThresholdEngine

enum RecordingStoreError: LocalizedError {
    case documentsUnavailable
    case noActiveSession
    case notEnoughStorage
    case invalidLine
    case invalidBundle(String)

    var errorDescription: String? {
        switch self {
        case .documentsUnavailable:
            return "The recording folder is not available."
        case .noActiveSession:
            return "There is no recording to save."
        case .notEnoughStorage:
            return "Not enough free space for a long session. Free at least 5 MB, then start again."
        case .invalidLine:
            return "The recording has an unreadable line."
        case .invalidBundle(let reason):
            return reason
        }
    }
}

enum RecordingJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    static func date(from value: String) -> Date? {
        if let date = fractionalFormatter().date(from: value) {
            return date
        }
        return internetFormatter().date(from: value)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func internetFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a date"
                )
            }
            return date
        }
        return decoder
    }
}

enum RecordingValidator {
    static let sourcePlatform = "watchos"

    static func validate(_ recording: SessionRecording) throws {
        guard recording.schemaVersion == AppConstants.schemaVersion else {
            throw RecordingStoreError.invalidBundle("The recording version is not supported.")
        }
        guard recording.sourcePlatform == sourcePlatform else {
            throw RecordingStoreError.invalidBundle("The recording platform is not supported.")
        }
        guard !recording.deviceModel.isEmpty, !recording.watchAppVersion.isEmpty else {
            throw RecordingStoreError.invalidBundle("The recording is missing the watch or app version.")
        }
        guard recording.summary.id == recording.id else {
            throw RecordingStoreError.invalidBundle("The summary does not match the session.")
        }
        guard recording.summary.sampleCount == recording.samples.count else {
            throw RecordingStoreError.invalidBundle("The sample count does not match the recording.")
        }
        guard recording.summary.startedAt == recording.startedAt else {
            throw RecordingStoreError.invalidBundle("The summary start time does not match the session.")
        }
        try validate(settings: recording.settings)
        for sample in recording.samples {
            guard sample.offset.isFinite, sample.offset >= 0, sample.bpm.isFinite else {
                throw RecordingStoreError.invalidBundle("A heart-rate sample in the recording is invalid.")
            }
        }
        for event in recording.events {
            guard event.offset.isFinite, event.offset >= 0 else {
                throw RecordingStoreError.invalidBundle("An event in the recording is invalid.")
            }
        }
        let warningEvents = recording.events.filter { $0.kind == .warning }.count
        let thresholdEvents = recording.events.filter { $0.kind == .threshold }.count
        guard recording.summary.warningEvents == warningEvents,
              recording.summary.thresholdEvents == thresholdEvents else {
            throw RecordingStoreError.invalidBundle("The alert counts do not match the recording.")
        }
        guard recording.summary.sampleCount >= 0,
              recording.summary.warningEvents >= 0,
              recording.summary.thresholdEvents >= 0,
              recording.summary.activeSeconds.isFinite, recording.summary.activeSeconds >= 0,
              recording.summary.secondsAboveWarning.isFinite, recording.summary.secondsAboveWarning >= 0,
              recording.summary.secondsAboveTarget.isFinite, recording.summary.secondsAboveTarget >= 0,
              recording.summary.gapSeconds.isFinite, recording.summary.gapSeconds >= 0,
              recording.summary.avgBPM.isFinite,
              recording.summary.minBPM.isFinite,
              recording.summary.maxBPM.isFinite else {
            throw RecordingStoreError.invalidBundle("The summary numbers are invalid.")
        }
    }

    private static func validate(settings: HeartRateSettings) throws {
        guard settings.targetBPM.isFinite, (60...230).contains(settings.targetBPM) else {
            throw RecordingStoreError.invalidBundle("The alert target is outside the allowed range.")
        }
        guard settings.warningFraction.isFinite, (0.5...0.99).contains(settings.warningFraction) else {
            throw RecordingStoreError.invalidBundle("The warning level is outside the allowed range.")
        }
        guard settings.warningCooldown.isFinite, (5...600).contains(settings.warningCooldown),
              settings.thresholdCooldown.isFinite, (5...600).contains(settings.thresholdCooldown) else {
            throw RecordingStoreError.invalidBundle("A cooldown is outside the allowed range.")
        }
        guard settings.hysteresisBPM.isFinite, (1...20).contains(settings.hysteresisBPM) else {
            throw RecordingStoreError.invalidBundle("The hysteresis is outside the allowed range.")
        }
        guard settings.staleTimeout.isFinite, (1...120).contains(settings.staleTimeout) else {
            throw RecordingStoreError.invalidBundle("The stale timeout is outside the allowed range.")
        }
        guard settings.batteryGuardLevel.isFinite, (0.05...0.3).contains(settings.batteryGuardLevel) else {
            throw RecordingStoreError.invalidBundle("The battery guard level is outside the allowed range.")
        }
    }
}

enum WatchHardware {
    static func modelIdentifier() throws -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            throw RecordingStoreError.invalidBundle("The watch model could not be read.")
        }
        let machineBytes = systemInfo.machine
        let machine = withUnsafeBytes(of: machineBytes) { bytes -> String in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return ""
            }
            return String(cString: base)
        }
        let trimmed = machine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecordingStoreError.invalidBundle("The watch model could not be read.")
        }
        return trimmed
    }

    static func appVersion() throws -> String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            throw RecordingStoreError.invalidBundle("The app version could not be read.")
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecordingStoreError.invalidBundle("The app version could not be read.")
        }
        return trimmed
    }
}

struct RecordingListing: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let sampleCount: Int
    let activeSeconds: TimeInterval
    let isFinalized: Bool
}

@MainActor
struct RecordingStore {
    private let rootURL: URL?

    init(root: URL? = nil) {
        if let root {
            rootURL = root
        } else {
            rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("sessions", isDirectory: true)
        }
    }

    func createSession(_ header: SessionHeader) throws -> URL {
        let folder = try folderURL(for: header.id)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.path) {
            throw RecordingStoreError.invalidBundle("A recording with this id already exists.")
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let headerData = try RecordingJSON.encode(header)
            try headerData.write(to: folder.appendingPathComponent("header.json"), options: .atomic)
            let samplesURL = folder.appendingPathComponent("samples.csv")
            let eventsURL = folder.appendingPathComponent("events.csv")
            guard fileManager.createFile(atPath: samplesURL.path, contents: Data()),
                  fileManager.createFile(atPath: eventsURL.path, contents: Data()) else {
                throw RecordingStoreError.invalidBundle("The recording files could not be created.")
            }
            return folder
        } catch {
            if fileManager.fileExists(atPath: folder.path) {
                do {
                    try fileManager.removeItem(at: folder)
                } catch {
                    throw RecordingStoreError.invalidBundle(
                        "The recording could not be started, and the partial folder could not be removed."
                    )
                }
            }
            throw error
        }
    }

    func appendSamples(_ samples: [HeartRateSample], to folder: URL) throws {
        guard !samples.isEmpty else { return }
        let text = samples.map { "\(Self.token($0.offset)),\(Self.token($0.bpm))" }.joined(separator: "\n") + "\n"
        try append(text, to: folder.appendingPathComponent("samples.csv"))
    }

    func appendEvents(_ events: [SessionEvent], to folder: URL) throws {
        guard !events.isEmpty else { return }
        let text = events.map { "\(Self.token($0.offset)),\($0.kind.rawValue)" }.joined(separator: "\n") + "\n"
        try append(text, to: folder.appendingPathComponent("events.csv"))
    }

    func readHeader(in folder: URL) throws -> SessionHeader {
        let data = try Data(contentsOf: folder.appendingPathComponent("header.json"))
        return try RecordingJSON.decode(SessionHeader.self, from: data)
    }

    func readSamples(in folder: URL) throws -> [HeartRateSample] {
        try readLines(in: folder.appendingPathComponent("samples.csv")).map { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let offset = Double(parts[0]), offset.isFinite, offset >= 0,
                  let bpm = Double(parts[1]), bpm.isFinite else {
                throw RecordingStoreError.invalidLine
            }
            return HeartRateSample(offset: offset, bpm: bpm)
        }
    }

    func readEvents(in folder: URL) throws -> [SessionEvent] {
        try readLines(in: folder.appendingPathComponent("events.csv")).map { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let offset = Double(parts[0]), offset.isFinite, offset >= 0,
                  let kind = SessionEventKind(rawValue: String(parts[1])) else {
                throw RecordingStoreError.invalidLine
            }
            return SessionEvent(offset: offset, kind: kind)
        }
    }

    func writeFinished(_ recording: SessionRecording, in folder: URL) throws {
        try RecordingValidator.validate(recording)
        let summaryData = try RecordingJSON.encode(recording.summary)
        let bundleData = try RecordingJSON.encode(recording)
        let decodedSummary = try RecordingJSON.decode(MonitoringSummary.self, from: summaryData)
        let decodedBundle = try RecordingJSON.decode(SessionRecording.self, from: bundleData)
        try RecordingValidator.validate(decodedBundle)
        guard decodedSummary.id == recording.summary.id,
              decodedSummary.sampleCount == recording.summary.sampleCount,
              decodedBundle.samples.count == recording.samples.count else {
            throw RecordingStoreError.invalidBundle("The saved recording could not be read back.")
        }
        try summaryData.write(to: folder.appendingPathComponent("summary.json"), options: .atomic)
        try bundleData.write(to: bundleURL(for: recording.id, in: folder), options: .atomic)
    }

    func removeFolder(_ folder: URL) throws {
        try FileManager.default.removeItem(at: folder)
    }

    static let minimumFreeBytes = 5 * 1024 * 1024

    func ensureRoomForSession() throws {
        let root = try root()
        let fileManager = FileManager.default
        let probe = fileManager.fileExists(atPath: root.path) ? root : root.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: probe.path) else {
            throw RecordingStoreError.invalidBundle("Free space could not be read.")
        }
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let bytes = values.volumeAvailableCapacity else {
            throw RecordingStoreError.invalidBundle("Free space could not be read.")
        }
        guard Int64(bytes) >= Int64(Self.minimumFreeBytes) else {
            throw RecordingStoreError.notEnoughStorage
        }
    }

    func existingFolder(for id: UUID) throws -> URL {
        let folder = try folderURL(for: id)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RecordingStoreError.invalidBundle("The recording folder is missing.")
        }
        return folder
    }

    func summaryIfPresent(in folder: URL) throws -> MonitoringSummary? {
        let url = folder.appendingPathComponent("summary.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try RecordingJSON.decode(MonitoringSummary.self, from: data)
    }

    func ensureBundle(matching summary: MonitoringSummary, in folder: URL) throws {
        let bundle = bundleURL(for: summary.id, in: folder)
        if FileManager.default.fileExists(atPath: bundle.path) {
            return
        }
        let header = try readHeader(in: folder)
        let samples = try readSamples(in: folder)
        let events = try readEvents(in: folder)
        guard summary.id == header.id,
              summary.sampleCount == samples.count,
              summary.startedAt == header.startedAt else {
            throw RecordingStoreError.invalidBundle("The saved summary does not match the recording.")
        }
        let recording = SessionRecording(
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
        try writeFinished(recording, in: folder)
    }

    /// Deletes acknowledged finished recordings that are not among the newest `keeping`.
    /// Unacknowledged recordings stay on the watch. Phase 7 calls this after the phone acks.
    func pruneAcknowledged(
        _ acknowledged: Set<UUID>,
        keeping newestCount: Int = AppConstants.finishedRecordingsToKeep
    ) throws {
        guard newestCount >= 0 else { return }
        let finished = try listings().filter(\.isFinalized)
        let protected = Set(finished.prefix(newestCount).map(\.id))
        for listing in finished where acknowledged.contains(listing.id) && !protected.contains(listing.id) {
            try removeFolder(try existingFolder(for: listing.id))
        }
    }

    func listings() throws -> [RecordingListing] {
        let root = try root()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let folders = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var listings: [RecordingListing] = []
        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            guard let id = UUID(uuidString: folder.lastPathComponent) else {
                throw RecordingStoreError.invalidBundle("A session folder name is not an id.")
            }
            let header = try readHeader(in: folder)
            guard header.id == id else {
                throw RecordingStoreError.invalidBundle("The session id does not match its folder.")
            }
            let samples = try readSamples(in: folder)
            let finalized = fileManager.fileExists(atPath: bundleURL(for: id, in: folder).path)
            let activeSeconds: TimeInterval
            if finalized {
                let data = try Data(contentsOf: bundleURL(for: id, in: folder))
                let recording = try RecordingJSON.decode(SessionRecording.self, from: data)
                try RecordingValidator.validate(recording)
                activeSeconds = recording.summary.activeSeconds
            } else {
                let events = try readEvents(in: folder)
                let endOffset = max(
                    samples.map(\.offset).max() ?? 0,
                    events.map(\.offset).max() ?? 0
                )
                activeSeconds = SummaryCalculator.calculate(
                    samples: samples,
                    events: events,
                    endOffset: endOffset,
                    warningBPM: header.settings.warningBPM,
                    targetBPM: header.settings.targetBPM,
                    gapThreshold: SummaryCalculator.gapThresholdSeconds
                ).activeSeconds
            }
            listings.append(
                RecordingListing(
                    id: id,
                    startedAt: header.startedAt,
                    sampleCount: samples.count,
                    activeSeconds: activeSeconds,
                    isFinalized: finalized
                )
            )
        }
        return listings.sorted { $0.startedAt > $1.startedAt }
    }

    private func folderURL(for id: UUID) throws -> URL {
        try root().appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func bundleURL(for id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("session-\(id.uuidString.lowercased()).json")
    }

    private func root() throws -> URL {
        guard let rootURL else {
            throw RecordingStoreError.documentsUnavailable
        }
        return rootURL
    }

    private func readLines(in url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func append(_ text: String, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecordingStoreError.invalidBundle("A recording file is missing.")
        }
        let data = Data(text.utf8)
        let handle = try FileHandle(forWritingTo: url)
        var writeError: Error?
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            writeError = error
        }
        do {
            try handle.close()
        } catch {
            if writeError == nil {
                throw error
            }
        }
        if let writeError {
            throw writeError
        }
    }

    private static func token(_ value: Double) -> String {
        String(value)
    }
}
