import XCTest
@testable import Offset

final class TimeConverterTests: XCTestCase {
    private let converter = TimeConverter()
    private let ist = TimeZone(identifier: "Asia/Kolkata")!

    func testParsesNineAmPacificTime() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "9AM PT",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.inlineDisplay, "9:00 AM PT -> 10:30 PM IST (your local time)")
    }

    func testParsesThreeThirtyPmIST() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "3:30 PM IST",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.localDisplay, "3:30 PM IST")
    }

    func testParsesTwentyFourHourCET() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "14:00 CET",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.localDisplay, "6:30 PM IST")
    }

    func testInvalidInputFails() {
        XCTAssertEqual(
            converter.parseAndConvert(
                "sometime later",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).error,
            .missingTimeZone
        )
    }

    func testMissingTimeZoneFails() {
        XCTAssertEqual(
            converter.parseAndConvert(
                "9AM",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).error,
            .missingTimeZone
        )
    }

    func testTomorrowReferenceAdjustsDate() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "tomorrow 9AM JST",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.inlineDisplay, "9:00 AM JST on tomorrow -> 5:30 AM IST (your local time)")
    }

    func testWeekdayReferenceAdjustsDate() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "Monday 3PM EST",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.notificationBody, "3:00 PM EST on Monday = 1:30 AM IST")
    }

    func testNextWeekdayReferenceAdjustsDate() throws {
        let result = try XCTUnwrap(
            converter.parseAndConvert(
                "15:00 CET next Friday",
                to: ist,
                now: fixedDate("2026-01-15T12:00:00Z"),
                calendar: gregorianUTC()
            ).value
        )

        XCTAssertEqual(result.notificationBody, "3:00 PM CET on Friday = 7:30 PM IST")
    }

    func testUTCOffsetFormatting() {
        let dubai = TimeZone(identifier: "Asia/Dubai")!
        XCTAssertEqual(
            converter.utcOffsetString(for: dubai, at: fixedDate("2026-01-15T12:00:00Z")),
            "UTC+4"
        )
    }

    private func fixedDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private extension Result {
    var value: Success? {
        guard case let .success(value) = self else {
            return nil
        }
        return value
    }

    var error: Failure? {
        guard case let .failure(error) = self else {
            return nil
        }
        return error
    }
}
