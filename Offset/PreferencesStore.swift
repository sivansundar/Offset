import Foundation

final class PreferencesStore {
    private let userDefaults: UserDefaults
    private let appleIntelligenceKey: String

    init(
        userDefaults: UserDefaults = .standard,
        appleIntelligenceKey: String = "useAppleIntelligenceForTimeParsing"
    ) {
        self.userDefaults = userDefaults
        self.appleIntelligenceKey = appleIntelligenceKey
    }

    func loadUseAppleIntelligence() -> Bool {
        userDefaults.object(forKey: appleIntelligenceKey) as? Bool ?? false
    }

    func saveUseAppleIntelligence(_ value: Bool) {
        userDefaults.set(value, forKey: appleIntelligenceKey)
    }
}
