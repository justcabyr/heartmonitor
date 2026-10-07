import ThresholdEngine

extension HeartRateSample {
    var wholeBPM: Int {
        Int(bpm.rounded())
    }
}
