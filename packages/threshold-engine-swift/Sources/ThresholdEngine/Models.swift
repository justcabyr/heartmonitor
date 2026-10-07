import Foundation

public struct HeartRateSettings: Codable, Equatable {
    public var targetBPM: Double
    public var warningFraction: Double
    public var warningCooldown: TimeInterval
    public var thresholdCooldown: TimeInterval
    public var hysteresisBPM: Double
    public var staleTimeout: TimeInterval
    public var batteryGuardLevel: Double
    public var saveToHealth: Bool

    public var warningBPM: Double { targetBPM * warningFraction }

    public init(
        targetBPM: Double,
        warningFraction: Double,
        warningCooldown: TimeInterval,
        thresholdCooldown: TimeInterval,
        hysteresisBPM: Double,
        staleTimeout: TimeInterval,
        batteryGuardLevel: Double,
        saveToHealth: Bool
    ) {
        self.targetBPM = targetBPM
        self.warningFraction = warningFraction
        self.warningCooldown = warningCooldown
        self.thresholdCooldown = thresholdCooldown
        self.hysteresisBPM = hysteresisBPM
        self.staleTimeout = staleTimeout
        self.batteryGuardLevel = batteryGuardLevel
        self.saveToHealth = saveToHealth
    }
}

public enum HeartRateZone: String, Codable, Equatable {
    case normal
    case warning
    case threshold
    case stale
}

public enum ThresholdAlert: String, Codable, Equatable {
    case warning
    case threshold
    case stale
}

public struct ThresholdEvaluation: Equatable {
    public let zone: HeartRateZone
    public let alert: ThresholdAlert?

    public init(zone: HeartRateZone, alert: ThresholdAlert?) {
        self.zone = zone
        self.alert = alert
    }
}

public struct HeartRateSample: Codable, Equatable {
    public let offset: TimeInterval
    public let bpm: Double

    public init(offset: TimeInterval, bpm: Double) {
        self.offset = offset
        self.bpm = bpm
    }
}

public enum SessionEventKind: String, Codable, Equatable {
    case warning
    case threshold
    case staleStart
    case staleEnd
    case paused
    case resumed
    case recovered
    case batteryGuard
    case settingsChanged
}

public struct SessionEvent: Codable, Equatable {
    public let offset: TimeInterval
    public let kind: SessionEventKind

    public init(offset: TimeInterval, kind: SessionEventKind) {
        self.offset = offset
        self.kind = kind
    }
}
