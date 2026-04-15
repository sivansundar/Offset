import Foundation

enum CalendarDraftProvider: String, CaseIterable, Codable, Identifiable {
    case appleCalendar
    case googleCalendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleCalendar:
            return "Apple Calendar"
        case .googleCalendar:
            return "Google Calendar"
        }
    }
}

final class PreferencesStore {
    private let userDefaults: UserDefaults
    private let appleIntelligenceKey: String
    private let calendarDraftProviderKey: String

    init(
        userDefaults: UserDefaults = .standard,
        appleIntelligenceKey: String = "useAppleIntelligenceForTimeParsing",
        calendarDraftProviderKey: String = "preferredCalendarDraftProvider"
    ) {
        self.userDefaults = userDefaults
        self.appleIntelligenceKey = appleIntelligenceKey
        self.calendarDraftProviderKey = calendarDraftProviderKey
    }

    func loadUseAppleIntelligence() -> Bool {
        userDefaults.object(forKey: appleIntelligenceKey) as? Bool ?? false
    }

    func saveUseAppleIntelligence(_ value: Bool) {
        userDefaults.set(value, forKey: appleIntelligenceKey)
    }

    func loadPreferredCalendarDraftProvider() -> CalendarDraftProvider {
        guard
            let rawValue = userDefaults.string(forKey: calendarDraftProviderKey),
            let provider = CalendarDraftProvider(rawValue: rawValue)
        else {
            return .appleCalendar
        }

        return provider
    }

    func savePreferredCalendarDraftProvider(_ provider: CalendarDraftProvider) {
        userDefaults.set(provider.rawValue, forKey: calendarDraftProviderKey)
    }
}
