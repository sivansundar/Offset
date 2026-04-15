import XCTest
@testable import Offset

@MainActor
final class ServiceHandlerTests: XCTestCase {
    func testHandleSelectedTextBuildsSuccessNotification() async {
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

        let descriptor = await handler.handleSelectedText("9AM PT")

        XCTAssertEqual(descriptor.title, "Offset - Time Converted")
        XCTAssertEqual(descriptor.body, "9:00 AM PT = 10:30 PM IST")
    }

    func testHandleSelectedTextBuildsFailureNotification() async {
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

        let descriptor = await handler.handleSelectedText("nothing to see here")

        XCTAssertEqual(descriptor.body, "Couldn't find a time in the selected text.")
    }

    func testConvertSelectedTimeShowsLoadingTooltipBeforeResult() async {
        let presenter = RecordingServicePresenter()
        let handler = ServiceHandler(
            converter: TimeConverter(),
            presenter: presenter,
            anchorResolver: TestAnchorResolver(
                anchor: ServicePresentationAnchor(
                    selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40),
                    pointerLocation: CGPoint(x: 50, y: 60)
                )
            ),
            destinationTimeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setString("9AM PT", forType: .string)
        var serviceError: NSString?

        handler.convertSelectedTime(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(
            presenter.presentedDescriptors.first,
            ServiceResultDescriptor(
                title: "Offset - Time Converted",
                body: "Checking the selected text...",
                isLoading: true
            )
        )

        let deadline = Date().addingTimeInterval(2)
        while presenter.presentedDescriptors.count < 2 && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(presenter.presentedDescriptors.count, 2)
        XCTAssertEqual(presenter.presentedDescriptors.last?.body, "9:00 AM PT = 10:30 PM IST")
        XCTAssertEqual(
            presenter.presentedAnchors,
            [
                ServicePresentationAnchor(
                    selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40),
                    pointerLocation: CGPoint(x: 50, y: 60)
                ),
                ServicePresentationAnchor(
                    selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40),
                    pointerLocation: CGPoint(x: 50, y: 60)
                )
            ]
        )
    }
}

private final class TestServicePresenter: ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor) {}
}

private final class RecordingServicePresenter: ServiceResultPresenting {
    private(set) var presentedDescriptors: [ServiceResultDescriptor] = []
    private(set) var presentedAnchors: [ServicePresentationAnchor] = []

    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor) {
        presentedDescriptors.append(descriptor)
        presentedAnchors.append(anchor)
    }
}

private struct TestAnchorResolver: ServicePresentationAnchoring {
    let anchor: ServicePresentationAnchor

    func resolveAnchor() -> ServicePresentationAnchor {
        anchor
    }
}

@MainActor
final class TooltipPresenterTests: XCTestCase {
    func testTooltipFrameAnchorsAboveSelectionWhenThereIsRoom() {
        let frame = TooltipPresenter.frameForTooltip(
            tooltipSize: NSSize(width: 280, height: 80),
            anchor: ServicePresentationAnchor(
                selectionRect: CGRect(x: 100, y: 300, width: 120, height: 24),
                pointerLocation: CGPoint(x: 0, y: 0)
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame.origin.x, 20, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 338, accuracy: 0.001)
        XCTAssertEqual(frame.width, 280, accuracy: 0.001)
        XCTAssertEqual(frame.height, 80, accuracy: 0.001)
    }

    func testTooltipFrameFallsBelowSelectionWhenAboveWouldOverflow() {
        let frame = TooltipPresenter.frameForTooltip(
            tooltipSize: NSSize(width: 280, height: 80),
            anchor: ServicePresentationAnchor(
                selectionRect: CGRect(x: 100, y: 560, width: 120, height: 24),
                pointerLocation: CGPoint(x: 0, y: 0)
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame.origin.x, 20, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 466, accuracy: 0.001)
    }

    func testTooltipFrameFallsBackToPointerWhenSelectionRectIsUnavailable() {
        let frame = TooltipPresenter.frameForTooltip(
            tooltipSize: NSSize(width: 280, height: 80),
            anchor: ServicePresentationAnchor(
                selectionRect: nil,
                pointerLocation: CGPoint(x: 50, y: 40)
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame.origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 55, accuracy: 0.001)
    }
}
