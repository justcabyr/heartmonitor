import ThresholdEngine

extension HeartRateSettings {
    static let startScreen = HeartRateSettings(
        targetBPM: AppConstants.defaultTargetBPM,
        warningFraction: AppConstants.defaultWarningFraction,
        warningCooldown: 60,
        thresholdCooldown: 30,
        hysteresisBPM: 5,
        staleTimeout: 10,
        batteryGuardLevel: 0.10,
        saveToHealth: false
    )

    var isWithinLimits: Bool {
        targetBPM.isFinite && (60...230).contains(targetBPM)
            && warningFraction.isFinite && (0.5...0.99).contains(warningFraction)
            && warningCooldown.isFinite && (5...600).contains(warningCooldown)
            && thresholdCooldown.isFinite && (5...600).contains(thresholdCooldown)
            && hysteresisBPM.isFinite && (1...20).contains(hysteresisBPM)
            && staleTimeout.isFinite && (1...120).contains(staleTimeout)
            && batteryGuardLevel.isFinite && (0.05...0.3).contains(batteryGuardLevel)
    }
}
