import ThresholdEngine

extension SessionEventKind {
    var marksPause: Bool {
        self == .paused || self == .resumed
    }
}
