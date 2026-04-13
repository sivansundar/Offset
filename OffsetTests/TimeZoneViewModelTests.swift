import XCTest
@testable import Offset

@MainActor
final class TimeZoneViewModelTests: XCTestCase {
    func testDefaultWorldClockOrder() {
        let viewModel = TimeZoneViewModel(
            converter: TimeConverter(),
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            timeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )

        XCTAssertEqual(viewModel.worldClocks.map(\.city), ["New York", "London", "Tokyo", "Dubai"])
    }

    func testSubmitConversionShowsInlineResult() {
        let viewModel = makeViewModel()
        viewModel.inputText = "9AM PT"

        viewModel.submitConversion()

        XCTAssertEqual(viewModel.inlineResult, "9:00 AM PT -> 10:30 PM IST (your local time)")
    }

    func testSubmitConversionShowsFriendlyError() {
        let viewModel = makeViewModel()
        viewModel.inputText = "hello there"

        viewModel.submitConversion()

        XCTAssertEqual(viewModel.inlineResult, "Couldn't parse that time. Include a timezone like 'PT' or 'EST'.")
    }

    private func makeViewModel() -> TimeZoneViewModel {
        TimeZoneViewModel(
            converter: TimeConverter(),
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            timeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )
    }
}
