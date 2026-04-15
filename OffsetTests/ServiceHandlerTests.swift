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
            schedulePresenter: RecordingMeetingDraftPresenter(),
            anchorResolver: TestAnchorResolver(
                anchor: ServicePresentationAnchor(
                    selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40),
                    pointerLocation: CGPoint(x: 50, y: 60)
                )
            ),
            clipboard: RecordingClipboard(),
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

    func testPrepareScheduleMeetingBuildsDraft() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let preferencesStore = PreferencesStore(
            userDefaults: defaults,
            appleIntelligenceKey: "test.appleIntelligence",
            calendarDraftProviderKey: "test.calendarProvider"
        )
        preferencesStore.savePreferredCalendarDraftProvider(.googleCalendar)

        let handler = ServiceHandler(
            converter: TimeConverter(),
            presenter: TestServicePresenter(),
            schedulePresenter: RecordingMeetingDraftPresenter(),
            clipboard: RecordingClipboard(),
            preferencesStore: preferencesStore,
            destinationTimeZoneProvider: { TimeZone(identifier: "Asia/Kolkata")! },
            nowProvider: { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! },
            calendarProvider: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }
        )

        let result = await handler.prepareScheduleMeeting(from: "tomorrow 9AM JST")

        guard case let .success(draft) = result else {
            return XCTFail("Expected a draft")
        }

        XCTAssertEqual(draft.sourceDisplay, "9:00 AM JST")
        XCTAssertEqual(draft.localDisplay, "5:30 AM IST")
        XCTAssertTrue(draft.localDateDisplay.contains("Friday"))
        XCTAssertTrue(draft.localDateDisplay.contains("January"))
        XCTAssertEqual(draft.defaultTitle, "Meeting")
        XCTAssertEqual(draft.defaultDurationMinutes, 30)
        XCTAssertEqual(draft.defaultProvider, .googleCalendar)
    }

    func testScheduleMeetingShowsDraftPanelAndRoutesSubmission() async {
        let servicePresenter = RecordingServicePresenter()
        let meetingPresenter = RecordingMeetingDraftPresenter()
        let draftRouter = RecordingCalendarDraftRouter()
        let clipboard = RecordingClipboard()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let preferencesStore = PreferencesStore(
            userDefaults: defaults,
            appleIntelligenceKey: "test.appleIntelligence",
            calendarDraftProviderKey: "test.calendarProvider"
        )

        let anchor = ServicePresentationAnchor(
            selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            pointerLocation: CGPoint(x: 50, y: 60)
        )
        let handler = ServiceHandler(
            converter: TimeConverter(),
            presenter: servicePresenter,
            schedulePresenter: meetingPresenter,
            anchorResolver: TestAnchorResolver(anchor: anchor),
            draftRouter: draftRouter,
            clipboard: clipboard,
            preferencesStore: preferencesStore,
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

        handler.scheduleMeeting(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(
            servicePresenter.presentedDescriptors.first,
            ServiceResultDescriptor(
                title: "Offset - Schedule Meeting",
                body: "Preparing your meeting draft...",
                isLoading: true
            )
        )

        let deadline = Date().addingTimeInterval(2)
        while meetingPresenter.presentedDraft == nil && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(servicePresenter.dismissCallCount, 1)
        XCTAssertEqual(meetingPresenter.presentedAnchor, anchor)
        XCTAssertEqual(meetingPresenter.presentedDraft?.localDisplay, "10:30 PM IST")

        meetingPresenter.submit(
            title: "Partner sync",
            durationMinutes: 45,
            provider: .googleCalendar
        )

        XCTAssertEqual(draftRouter.submissions.count, 1)
        XCTAssertEqual(draftRouter.submissions.first?.title, "Partner sync")
        XCTAssertEqual(draftRouter.submissions.first?.durationMinutes, 45)
        XCTAssertEqual(draftRouter.submissions.first?.provider, .googleCalendar)
        XCTAssertEqual(preferencesStore.loadPreferredCalendarDraftProvider(), .googleCalendar)
        XCTAssertEqual(meetingPresenter.dismissCallCount, 1)

        meetingPresenter.copyLink(
            title: "Partner sync",
            durationMinutes: 45,
            provider: .googleCalendar
        )

        XCTAssertEqual(clipboard.copiedStrings.count, 1)
        XCTAssertTrue(clipboard.copiedStrings[0].contains("calendar.google.com"))
    }
}

private final class TestServicePresenter: ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor) {}
    func dismiss() {}
}

private final class RecordingServicePresenter: ServiceResultPresenting {
    private(set) var presentedDescriptors: [ServiceResultDescriptor] = []
    private(set) var presentedAnchors: [ServicePresentationAnchor] = []
    private(set) var dismissCallCount = 0

    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor) {
        presentedDescriptors.append(descriptor)
        presentedAnchors.append(anchor)
    }

    func dismiss() {
        dismissCallCount += 1
    }
}

private final class RecordingMeetingDraftPresenter: MeetingDraftPresenting {
    private(set) var presentedDraft: ScheduleMeetingDraft?
    private(set) var presentedAnchor: ServicePresentationAnchor?
    private var submitHandler: ((ScheduleMeetingSubmission) -> Void)?
    private var copyHandler: ((ScheduleMeetingSubmission) -> Void)?
    private var cancelHandler: (() -> Void)?
    private(set) var dismissCallCount = 0

    func present(
        _ draft: ScheduleMeetingDraft,
        anchor: ServicePresentationAnchor,
        onSubmit: @escaping (ScheduleMeetingSubmission) -> Void,
        onCopy: @escaping (ScheduleMeetingSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentedDraft = draft
        presentedAnchor = anchor
        submitHandler = onSubmit
        copyHandler = onCopy
        cancelHandler = onCancel
    }

    func dismiss() {
        dismissCallCount += 1
    }

    func submit(title: String, durationMinutes: Int, provider: CalendarDraftProvider) {
        guard let draft = presentedDraft else { return }
        submitHandler?(draft.submission(title: title, durationMinutes: durationMinutes, provider: provider))
    }

    func copyLink(title: String, durationMinutes: Int, provider: CalendarDraftProvider) {
        guard let draft = presentedDraft else { return }
        copyHandler?(draft.submission(title: title, durationMinutes: durationMinutes, provider: provider))
    }

    func cancel() {
        cancelHandler?()
    }
}

private final class RecordingCalendarDraftRouter: CalendarDraftRouting {
    private(set) var submissions: [ScheduleMeetingSubmission] = []

    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool {
        submissions.append(submission)
        return true
    }

    func draftURL(for submission: ScheduleMeetingSubmission) -> URL? {
        URL(string: "https://calendar.google.com/calendar/render?action=TEMPLATE")
    }
}

private final class RecordingClipboard: ClipboardWriting {
    private(set) var copiedStrings: [String] = []

    func copy(_ string: String) {
        copiedStrings.append(string)
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

    func testSchedulePanelFrameStaysWithinVisibleFrame() {
        let frame = ScheduleMeetingPresenter.frameForPanel(
            panelSize: NSSize(width: 448, height: 320),
            anchor: ServicePresentationAnchor(
                selectionRect: CGRect(x: 760, y: 560, width: 80, height: 24),
                pointerLocation: CGPoint(x: 0, y: 0)
            ),
            visibleFrame: NSRect(x: 0, y: 0, width: 900, height: 650)
        )

        XCTAssertGreaterThanOrEqual(frame.origin.x, 16)
        XCTAssertGreaterThanOrEqual(frame.origin.y, 16)
        XCTAssertLessThanOrEqual(frame.maxX, 884)
        XCTAssertLessThanOrEqual(frame.maxY, 634)
    }
}
