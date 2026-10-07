import Foundation

/// Pure alert decision. Pass `now` in; the type never reads the clock itself.
/// A missing `bpm` is not a sample: call `advance(to:)` so a stale episode can begin.
public struct ThresholdEngine {
    public private(set) var settings: HeartRateSettings

    private var lastSampleAt: Date?
    private var latchedZone: HeartRateZone = .normal
    private var isStale = false
    private var cooldownReset = false

    private var warningArmed = true
    private var thresholdArmed = true
    private var warningEpisode = false
    private var thresholdEpisode = false
    private var warningAlertAt: Date?
    private var thresholdAlertAt: Date?

    public init(settings: HeartRateSettings) {
        self.settings = settings
    }

    /// Applies new boundaries immediately and expires both cooldowns.
    public mutating func replaceSettings(_ settings: HeartRateSettings) {
        self.settings = settings
        cooldownReset = true
    }

    /// Time passed with no new sample. Alerts from the previous BPM stay off.
    public mutating func advance(to now: Date) -> ThresholdEvaluation {
        guard let lastSampleAt, now >= lastSampleAt else {
            return ThresholdEvaluation(zone: latchedZone, alert: nil)
        }
        if isStale {
            return ThresholdEvaluation(zone: .stale, alert: nil)
        }
        if now.timeIntervalSince(lastSampleAt) >= settings.staleTimeout {
            isStale = true
            return ThresholdEvaluation(zone: .stale, alert: .stale)
        }
        return ThresholdEvaluation(zone: latchedZone, alert: nil)
    }

    public mutating func evaluate(bpm: Double, at now: Date) -> ThresholdEvaluation {
        lastSampleAt = now
        isStale = false
        rearm(for: bpm)
        let zone = Self.zone(for: bpm, settings: settings)
        let forced = cooldownReset
        cooldownReset = false
        let alert = riskAlert(for: zone, at: now, forcedCooldown: forced)
        latchedZone = zone
        return ThresholdEvaluation(zone: zone, alert: alert)
    }

    public static func zone(for bpm: Double, settings: HeartRateSettings) -> HeartRateZone {
        if bpm >= settings.targetBPM { return .threshold }
        if bpm >= settings.warningBPM { return .warning }
        return .normal
    }

    /// Re-arm a boundary only after BPM has fallen by the full hysteresis amount.
    private mutating func rearm(for bpm: Double) {
        if bpm <= settings.warningBPM - settings.hysteresisBPM {
            warningArmed = true
            warningEpisode = false
        }
        if bpm <= settings.targetBPM - settings.hysteresisBPM {
            thresholdArmed = true
            thresholdEpisode = false
        }
    }

    private mutating func riskAlert(
        for zone: HeartRateZone,
        at now: Date,
        forcedCooldown: Bool
    ) -> ThresholdAlert? {
        switch zone {
        case .warning:
            let next = Self.decide(
                zone: .warning,
                alert: .warning,
                armed: warningArmed,
                episode: warningEpisode,
                alertAt: warningAlertAt,
                latched: latchedZone,
                cooldown: settings.warningCooldown,
                now: now,
                forcedCooldown: forcedCooldown
            )
            warningArmed = next.armed
            warningEpisode = next.episode
            warningAlertAt = next.alertAt
            return next.alert
        case .threshold:
            let next = Self.decide(
                zone: .threshold,
                alert: .threshold,
                armed: thresholdArmed,
                episode: thresholdEpisode,
                alertAt: thresholdAlertAt,
                latched: latchedZone,
                cooldown: settings.thresholdCooldown,
                now: now,
                forcedCooldown: forcedCooldown
            )
            thresholdArmed = next.armed
            thresholdEpisode = next.episode
            thresholdAlertAt = next.alertAt
            return next.alert
        case .normal, .stale:
            return nil
        }
    }

    private struct RiskState {
        var armed: Bool
        var episode: Bool
        var alertAt: Date?
        var alert: ThresholdAlert?
    }

    private static func decide(
        zone: HeartRateZone,
        alert: ThresholdAlert,
        armed: Bool,
        episode: Bool,
        alertAt: Date?,
        latched: HeartRateZone,
        cooldown: TimeInterval,
        now: Date,
        forcedCooldown: Bool
    ) -> RiskState {
        var state = RiskState(armed: armed, episode: episode, alertAt: alertAt, alert: nil)
        let higher = rank(zone) > rank(latched)
        if higher && state.armed {
            state.armed = false
            state.episode = true
            state.alertAt = now
            state.alert = alert
            return state
        }
        if higher && !state.armed {
            if state.episode {
                state.alertAt = now
            }
            return state
        }
        if zone == latched && state.episode {
            let elapsed = state.alertAt.map { now.timeIntervalSince($0) } ?? TimeInterval.greatestFiniteMagnitude
            if forcedCooldown || elapsed >= cooldown {
                state.alertAt = now
                state.alert = alert
            }
            return state
        }
        if rank(zone) < rank(latched), state.episode {
            state.alertAt = now
        }
        return state
    }

    private static func rank(_ zone: HeartRateZone) -> Int {
        switch zone {
        case .normal, .stale:
            return 0
        case .warning:
            return 1
        case .threshold:
            return 2
        }
    }
}
