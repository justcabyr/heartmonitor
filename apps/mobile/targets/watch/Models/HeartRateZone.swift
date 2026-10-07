import ThresholdEngine

extension HeartRateZone {
    var title: String {
        switch self {
        case .normal:
            return "NORMAL"
        case .warning:
            return "WARNING"
        case .threshold:
            return "THRESHOLD"
        case .stale:
            return "WAITING FOR HR"
        }
    }
}
