import XCTest
@testable import Offset

final class MenuBarControllerTests: XCTestCase {
    func testStatusTitleUsesTwentyFourHourClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        let date = ISO8601DateFormatter().date(from: "2026-01-15T14:31:45+05:30")!
        XCTAssertEqual(MenuBarController.statusTitle(for: date, calendar: calendar), "14:31")
    }

    func testSecondsUntilNextMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let date = ISO8601DateFormatter().date(from: "2026-01-15T12:00:45Z")!
        XCTAssertEqual(MenuBarController.secondsUntilNextMinute(from: date, calendar: calendar), 15)
    }
}
