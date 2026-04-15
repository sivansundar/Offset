import XCTest
@testable import Offset

@MainActor
final class TimeZoneViewModelTests: XCTestCase {
    func testDefaultWorldClockOrder() {
        let viewModel = makeViewModel(store: makeIsolatedStore(name: #function))

        XCTAssertEqual(viewModel.worldClocks.map(\.city), ["New York", "London", "Tokyo", "Dubai"])
    }

    func testSavedWorldClockOrderOverridesDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = WorldClockStore(
            userDefaults: defaults,
            storageKey: "test.savedWorldClockIdentifiers"
        )
        store.save([
            WorldClockConfiguration(timeZoneIdentifier: "America/Los_Angeles"),
            WorldClockConfiguration(timeZoneIdentifier: "Europe/Paris"),
        ])

        let viewModel = makeViewModel(store: store)

        XCTAssertEqual(viewModel.worldClocks.map(\.timeZoneIdentifier), ["America/Los_Angeles", "Europe/Paris"])
    }

    func testSubmitConversionShowsInlineResult() {
        let viewModel = makeViewModel(store: makeIsolatedStore(name: #function))
        viewModel.inputText = "9AM PT"

        let expectation = expectation(description: "conversion")
        Task {
            await viewModel.submitConversion()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(viewModel.inlineResult, "9:00 AM PT -> 10:30 PM IST (your local time)")
    }

    func testSubmitConversionShowsFriendlyError() {
        let viewModel = makeViewModel(store: makeIsolatedStore(name: #function))
        viewModel.inputText = "hello there"

        let expectation = expectation(description: "conversion")
        Task {
            await viewModel.submitConversion()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(viewModel.inlineResult, "Couldn't parse that time. Include a timezone like 'PT' or 'EST'.")
    }

    func testAppleIntelligencePreferencePersists() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let preferencesStore = PreferencesStore(
            userDefaults: defaults,
            appleIntelligenceKey: "test.useAppleIntelligence"
        )
        let viewModel = makeViewModel(
            store: makeIsolatedStore(name: "\(#function).store"),
            preferencesStore: preferencesStore
        )

        viewModel.useAppleIntelligence = true

        let reloadedViewModel = makeViewModel(
            store: makeIsolatedStore(name: "\(#function).store.reloaded"),
            preferencesStore: preferencesStore
        )

        XCTAssertTrue(reloadedViewModel.useAppleIntelligence)
    }

    func testLocalTimeZoneLabelUsesLocalizedSystemName() {
        let viewModel = makeViewModel(store: makeIsolatedStore(name: #function))

        XCTAssertEqual(viewModel.localTimeZoneLabel, "India Standard Time (IST)")
    }

    func testAddAndRemoveTimeZonePersistsSelection() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = WorldClockStore(
            userDefaults: defaults,
            storageKey: "test.savedWorldClockIdentifiers"
        )
        let viewModel = makeViewModel(store: store)

        viewModel.addTimeZone(identifier: "America/Los_Angeles")
        XCTAssertTrue(viewModel.worldClocks.contains(where: { $0.timeZoneIdentifier == "America/Los_Angeles" }))

        let reloadedViewModel = makeViewModel(store: store)
        XCTAssertTrue(reloadedViewModel.worldClocks.contains(where: { $0.timeZoneIdentifier == "America/Los_Angeles" }))

        reloadedViewModel.removeTimeZone(identifier: "America/Los_Angeles")
        XCTAssertFalse(reloadedViewModel.worldClocks.contains(where: { $0.timeZoneIdentifier == "America/Los_Angeles" }))
    }

    private func makeViewModel(
        store: WorldClockStore = WorldClockStore(),
        preferencesStore: PreferencesStore = PreferencesStore()
    ) -> TimeZoneViewModel {
        TimeZoneViewModel(
            converter: TimeConverter(appleIntelligenceParser: NoOpAppleIntelligenceParser()),
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            timeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            },
            worldClockStore: store,
            preferencesStore: preferencesStore,
            appleIntelligenceAvailabilityProvider: { .available }
        )
    }

    private func makeIsolatedStore(name: String) -> WorldClockStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return WorldClockStore(
            userDefaults: defaults,
            storageKey: "test.savedWorldClockIdentifiers"
        )
    }
}

private struct NoOpAppleIntelligenceParser: AppleIntelligenceTimeParsing {
    func availability() -> AppleIntelligenceAvailability {
        .available
    }

    func normalizeTimeExpression(
        _ input: String,
        supportedAbbreviations: [String: String]
    ) async -> String? {
        nil
    }
}
