import XCTest
@testable import Offset

final class MeetingSchedulingTests: XCTestCase {
    func testGoogleCalendarDraftURLIncludesMeetingDetails() {
        let opener = GoogleCalendarDraftOpener(workspace: TestWorkspace())

        let url = opener.draftURL(for: makeSubmission(provider: .googleCalendar))
        let components = URLComponents(url: try! XCTUnwrap(url), resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(url?.host, "calendar.google.com")
        XCTAssertEqual(queryItems.first(where: { $0.name == "action" })?.value, "TEMPLATE")
        XCTAssertEqual(queryItems.first(where: { $0.name == "text" })?.value, "Partner sync")
        XCTAssertEqual(queryItems.first(where: { $0.name == "ctz" })?.value, "Asia/Kolkata")
    }

    func testAppleCalendarDraftProducesICS() throws {
        let opener = AppleCalendarDraftOpener(
            workspace: TestWorkspace(),
            temporaryFileWriter: InMemoryTemporaryFileWriter()
        )

        let data = try XCTUnwrap(opener.icsData(for: makeSubmission(provider: .appleCalendar)))
        let ics = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(ics.contains("SUMMARY:Partner sync"))
        XCTAssertTrue(ics.contains("DTSTART;TZID=Asia/Kolkata:20260115T223000"))
        XCTAssertTrue(ics.contains("DTEND;TZID=Asia/Kolkata:20260115T231500"))
        XCTAssertTrue(ics.contains("Created from \"9AM PT\" in Offset"))
    }

    func testPreferredCalendarProviderPersists() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = PreferencesStore(
            userDefaults: defaults,
            appleIntelligenceKey: "test.appleIntelligence",
            calendarDraftProviderKey: "test.calendarProvider"
        )

        XCTAssertEqual(store.loadPreferredCalendarDraftProvider(), .appleCalendar)

        store.savePreferredCalendarDraftProvider(.googleCalendar)

        XCTAssertEqual(store.loadPreferredCalendarDraftProvider(), .googleCalendar)
    }

    func testAppleCalendarDraftURLReturnsTemporaryICSFile() {
        let opener = AppleCalendarDraftOpener(
            workspace: TestWorkspace(),
            temporaryFileWriter: InMemoryTemporaryFileWriter()
        )

        let url = opener.draftURL(for: makeSubmission(provider: .appleCalendar))

        XCTAssertEqual(url?.absoluteString, "file:///tmp/offset-meeting.ics")
    }

    private func makeSubmission(provider: CalendarDraftProvider) -> ScheduleMeetingSubmission {
        let draft = ScheduleMeetingDraft(
            sourceText: "9AM PT",
            sourceDisplay: "9:00 AM PT",
            localDisplay: "10:30 PM IST",
            localDateDisplay: "Thursday, January 15",
            resolvedStartDate: ISO8601DateFormatter().date(from: "2026-01-15T17:00:00Z")!,
            resolvedSourceTimeZone: TimeZone(identifier: "America/Los_Angeles")!,
            resolvedDestinationTimeZone: TimeZone(identifier: "Asia/Kolkata")!,
            defaultTitle: "Meeting",
            defaultDurationMinutes: 30,
            defaultProvider: provider
        )

        return draft.submission(
            title: "Partner sync",
            durationMinutes: 45,
            provider: provider
        )
    }
}

private struct TestWorkspace: WorkspaceOpening {
    func open(_ url: URL) -> Bool { true }
}

private struct InMemoryTemporaryFileWriter: TemporaryFileWriting {
    func writeTemporaryFile(named fileName: String, contents: Data) throws -> URL {
        URL(fileURLWithPath: "/tmp/offset-meeting.ics")
    }
}
