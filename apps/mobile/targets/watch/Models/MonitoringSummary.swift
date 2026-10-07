import Foundation

enum EndReason: String, Codable {
    case user
    case batteryGuard
    case interrupted
    case error
}

struct MonitoringSummary: Codable, Identifiable {
    let id: UUID
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
}
