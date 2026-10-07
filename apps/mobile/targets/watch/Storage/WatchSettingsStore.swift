import Foundation
import ThresholdEngine

enum WatchSettingsError: LocalizedError {
    case invalid
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "Those alert settings are outside the allowed range."
        case .couldNotSave:
            return "The alert settings could not be saved."
        }
    }
}

@MainActor
final class WatchSettingsStore {
    private let defaults: UserDefaults
    private let key = "heartRateSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (settings: HeartRateSettings, rejectedStoredValue: Bool) {
        guard let data = defaults.data(forKey: key) else {
            return (.startScreen, false)
        }
        do {
            let decoded = try JSONDecoder().decode(HeartRateSettings.self, from: data)
            guard decoded.isWithinLimits else {
                return (.startScreen, true)
            }
            return (decoded, false)
        } catch {
            return (.startScreen, true)
        }
    }

    func save(_ settings: HeartRateSettings) throws {
        guard settings.isWithinLimits else {
            throw WatchSettingsError.invalid
        }
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            throw WatchSettingsError.couldNotSave
        }
    }
}
