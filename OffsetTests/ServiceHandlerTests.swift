import XCTest
@testable import Offset

@MainActor
final class ServiceHandlerTests: XCTestCase {
    func testHandleSelectedTextBuildsSuccessNotification() {
        let handler = ServiceHandler(
            converter: TimeConverter(),
            presenter: TestServicePresenter(),
            destinationTimeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )

        let descriptor = handler.handleSelectedText("9AM PT")

        XCTAssertEqual(descriptor.title, "Offset - Time Converted")
        XCTAssertEqual(descriptor.body, "9:00 AM PT = 10:30 PM IST")
    }

    func testHandleSelectedTextBuildsFailureNotification() {
        let handler = ServiceHandler(
            converter: TimeConverter(),
            presenter: TestServicePresenter(),
            destinationTimeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )

        let descriptor = handler.handleSelectedText("nothing to see here")

        XCTAssertEqual(descriptor.body, "Couldn't find a time in the selected text.")
    }
}

private struct TestServicePresenter: ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor) {}
}
