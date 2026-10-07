import Foundation

enum EndReason: String, Codable, Equatable {
    case user
    case batteryGuard
    case interrupted
    case error

    var title: String {
        switch self {
        case .user:
            return "Ended"
        case .batteryGuard:
            return "Ended, battery low"
        case .interrupted:
            return "Interrupted"
        case .error:
            return "Ended because of an error"
        }
    }
}

struct MonitoringSummary: Codable, Equatable, Identifiable {
    @RecordingUUID var id: UUID
    let startedAt: Date
    let endedAt: Date
    let activeSeconds: TimeInterval
    let sampleCount: Int
    let avgBPM: Double
    let minBPM: Double
    let maxBPM: Double
    let warningEvents: Int
    let thresholdEvents: Int
    let secondsAboveWarning: TimeInterval
    let secondsAboveTarget: TimeInterval
    let gapSeconds: TimeInterval
    let endReason: EndReason

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        activeSeconds: TimeInterval,
        sampleCount: Int,
        avgBPM: Double,
        minBPM: Double,
        maxBPM: Double,
        warningEvents: Int,
        thresholdEvents: Int,
        secondsAboveWarning: TimeInterval,
        secondsAboveTarget: TimeInterval,
        gapSeconds: TimeInterval,
        endReason: EndReason
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.sampleCount = sampleCount
        self.avgBPM = avgBPM
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.warningEvents = warningEvents
        self.thresholdEvents = thresholdEvents
        self.secondsAboveWarning = secondsAboveWarning
        self.secondsAboveTarget = secondsAboveTarget
        self.gapSeconds = gapSeconds
        self.endReason = endReason
    }
}
