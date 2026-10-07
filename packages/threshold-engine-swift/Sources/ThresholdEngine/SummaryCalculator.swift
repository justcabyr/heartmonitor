import Foundation

public struct CalculatedSummary: Equatable {
    public let avgBPM: Double
    public let minBPM: Double
    public let maxBPM: Double
    public let sampleCount: Int
    public let activeSeconds: TimeInterval
    public let pausedSeconds: TimeInterval
    public let secondsAboveWarning: TimeInterval
    public let secondsAboveTarget: TimeInterval
    public let gapSeconds: TimeInterval

    public init(
        avgBPM: Double,
        minBPM: Double,
        maxBPM: Double,
        sampleCount: Int,
        activeSeconds: TimeInterval,
        pausedSeconds: TimeInterval,
        secondsAboveWarning: TimeInterval,
        secondsAboveTarget: TimeInterval,
        gapSeconds: TimeInterval
    ) {
        self.avgBPM = avgBPM
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.sampleCount = sampleCount
        self.activeSeconds = activeSeconds
        self.pausedSeconds = pausedSeconds
        self.secondsAboveWarning = secondsAboveWarning
        self.secondsAboveTarget = secondsAboveTarget
        self.gapSeconds = gapSeconds
    }
}

/// Sample stats for a finished session.
/// Each sample's BPM is held until the next sample, and that hold is capped at
/// `gapThresholdSeconds` of active time. Paused time is excluded from the hold,
/// from gaps, and from `activeSeconds`.
public enum SummaryCalculator {
    public static let gapThresholdSeconds: TimeInterval = 60

    public static func calculate(
        samples: [HeartRateSample],
        events: [SessionEvent],
        endOffset: TimeInterval,
        warningBPM: Double,
        targetBPM: Double,
        gapThreshold: TimeInterval = SummaryCalculator.gapThresholdSeconds
    ) -> CalculatedSummary {
        let pauses = pauseSpans(events: events, endOffset: endOffset)
        let pausedSeconds = pauses.reduce(0) { $0 + ($1.end - $1.start) }
        let activeSeconds = max(0, endOffset - pausedSeconds)
        let ordered = samples.sorted { $0.offset < $1.offset }

        guard !ordered.isEmpty else {
            return CalculatedSummary(
                avgBPM: 0,
                minBPM: 0,
                maxBPM: 0,
                sampleCount: 0,
                activeSeconds: activeSeconds,
                pausedSeconds: pausedSeconds,
                secondsAboveWarning: 0,
                secondsAboveTarget: 0,
                gapSeconds: 0
            )
        }

        let total = ordered.reduce(0) { $0 + $1.bpm }
        var aboveWarning = 0.0
        var aboveTarget = 0.0
        var gapSeconds = 0.0

        func integrate(from start: TimeInterval, to end: TimeInterval, bpm: Double) {
            let active = activeDuration(from: start, to: end, pauses: pauses)
            let counted = min(active, gapThreshold)
            gapSeconds += max(0, active - gapThreshold)
            if bpm >= warningBPM { aboveWarning += counted }
            if bpm >= targetBPM { aboveTarget += counted }
        }

        if ordered.count > 1 {
            for index in 0..<(ordered.count - 1) {
                integrate(from: ordered[index].offset, to: ordered[index + 1].offset, bpm: ordered[index].bpm)
            }
        }
        if let last = ordered.last, last.offset < endOffset {
            integrate(from: last.offset, to: endOffset, bpm: last.bpm)
        }

        return CalculatedSummary(
            avgBPM: total / Double(ordered.count),
            minBPM: ordered.map(\.bpm).min() ?? 0,
            maxBPM: ordered.map(\.bpm).max() ?? 0,
            sampleCount: ordered.count,
            activeSeconds: activeSeconds,
            pausedSeconds: pausedSeconds,
            secondsAboveWarning: aboveWarning,
            secondsAboveTarget: aboveTarget,
            gapSeconds: gapSeconds
        )
    }

    private struct PauseSpan {
        let start: TimeInterval
        let end: TimeInterval
    }

    private static func pauseSpans(events: [SessionEvent], endOffset: TimeInterval) -> [PauseSpan] {
        var spans: [PauseSpan] = []
        var pauseStart: TimeInterval?
        for event in events.sorted(by: { $0.offset < $1.offset }) {
            switch event.kind {
            case .paused where pauseStart == nil && event.offset < endOffset:
                pauseStart = event.offset
            case .resumed:
                guard let start = pauseStart else { continue }
                let end = min(event.offset, endOffset)
                if end > start {
                    spans.append(PauseSpan(start: start, end: end))
                }
                pauseStart = nil
            default:
                continue
            }
        }
        if let start = pauseStart, endOffset > start {
            spans.append(PauseSpan(start: start, end: endOffset))
        }
        return spans
    }

    private static func activeDuration(
        from start: TimeInterval,
        to end: TimeInterval,
        pauses: [PauseSpan]
    ) -> TimeInterval {
        var active = max(0, end - start)
        for pause in pauses {
            let overlap = min(end, pause.end) - max(start, pause.start)
            if overlap > 0 {
                active -= overlap
            }
        }
        return max(0, active)
    }
}
