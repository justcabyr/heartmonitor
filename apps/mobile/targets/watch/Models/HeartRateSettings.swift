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
}
