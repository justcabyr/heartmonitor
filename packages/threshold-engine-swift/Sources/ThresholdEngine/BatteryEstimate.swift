import Foundation

/// Drain estimate for the watch battery guard.
/// Uses the drop from the oldest to the newest reading inside the last 15 minutes.
/// A span under 60 seconds, a flat line, or a charge is not an estimate.
public enum BatteryEstimate {
    public static let window: TimeInterval = 15 * 60
    public static let minimumSpan: TimeInterval = 60
    public static let maximumSeconds: TimeInterval = 36 * 60 * 60

    public struct Reading: Equatable {
        public let date: Date
        public let level: Double

        public init(date: Date, level: Double) {
            self.date = date
            self.level = level
        }
    }

    /// Seconds until `floor` (the guard level) at the current drain rate.
    /// Already being at or below `floor` returns 0. An unusable rate returns nil.
    public static func secondsRemaining(
        readings: [Reading],
        now: Date,
        until floor: Double
    ) -> TimeInterval? {
        let recent = readings
            .filter { reading in
                reading.level >= 0 && reading.level <= 1
                    && now.timeIntervalSince(reading.date) >= 0
                    && now.timeIntervalSince(reading.date) <= window
            }
            .sorted { $0.date < $1.date }
        guard let first = recent.first, let last = recent.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= minimumSpan else { return nil }
        let drop = first.level - last.level
        guard drop > 0 else { return nil }
        if last.level <= floor {
            return 0
        }
        let remaining = (last.level - floor) / (drop / span)
        guard remaining.isFinite, remaining >= 0, remaining <= maximumSeconds else { return nil }
        return remaining
    }
}
