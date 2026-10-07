import Foundation
import ThresholdEngine

struct SessionHeader: Codable, Equatable {
    @RecordingUUID var id: UUID
    let startedAt: Date
    let schemaVersion: Int
    let deviceModel: String
    let watchAppVersion: String
    let settings: HeartRateSettings

    init(
        id: UUID,
        startedAt: Date,
        schemaVersion: Int,
        deviceModel: String,
        watchAppVersion: String,
        settings: HeartRateSettings
    ) {
        self.id = id
        self.startedAt = startedAt
        self.schemaVersion = schemaVersion
        self.deviceModel = deviceModel
        self.watchAppVersion = watchAppVersion
        self.settings = settings
    }
}

struct SessionRecording: Codable, Equatable {
    let schemaVersion: Int
    @RecordingUUID var id: UUID
    let sourcePlatform: String
    let deviceModel: String
    let watchAppVersion: String
    let startedAt: Date
    let settings: HeartRateSettings
    let samples: [HeartRateSample]
    let events: [SessionEvent]
    let summary: MonitoringSummary

    init(
        schemaVersion: Int,
        id: UUID,
        sourcePlatform: String,
        deviceModel: String,
        watchAppVersion: String,
        startedAt: Date,
        settings: HeartRateSettings,
        samples: [HeartRateSample],
        events: [SessionEvent],
        summary: MonitoringSummary
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sourcePlatform = sourcePlatform
        self.deviceModel = deviceModel
        self.watchAppVersion = watchAppVersion
        self.startedAt = startedAt
        self.settings = settings
        self.samples = samples
        self.events = events
        self.summary = summary
    }
}
