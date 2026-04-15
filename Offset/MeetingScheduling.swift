import AppKit
import Foundation

struct ScheduleMeetingDraft {
    let sourceText: String
    let sourceDisplay: String
    let localDisplay: String
    let localDateDisplay: String
    let resolvedStartDate: Date
    let resolvedSourceTimeZone: TimeZone
    let resolvedDestinationTimeZone: TimeZone
    let defaultTitle: String
    let defaultDurationMinutes: Int
    let defaultProvider: CalendarDraftProvider

    func submission(
        title: String,
        durationMinutes: Int,
        provider: CalendarDraftProvider
    ) -> ScheduleMeetingSubmission {
        ScheduleMeetingSubmission(
            draft: self,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title.trimmingCharacters(in: .whitespacesAndNewlines),
            durationMinutes: durationMinutes,
            provider: provider
        )
    }
}

struct ScheduleMeetingSubmission {
    let draft: ScheduleMeetingDraft
    let title: String
    let durationMinutes: Int
    let provider: CalendarDraftProvider

    var startDate: Date {
        draft.resolvedStartDate
    }

    var endDate: Date {
        Calendar(identifier: .gregorian).date(
            byAdding: .minute,
            value: durationMinutes,
            to: startDate
        ) ?? startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

struct ScheduleMeetingDraftFactory {
    func makeDraft(
        from result: ConversionResult,
        sourceText: String,
        destinationTimeZone: TimeZone,
        preferredProvider: CalendarDraftProvider
    ) -> ScheduleMeetingDraft {
        ScheduleMeetingDraft(
            sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceDisplay: result.sourceDisplay,
            localDisplay: result.localDisplay,
            localDateDisplay: Self.localDateString(for: result.resolvedDate, timeZone: destinationTimeZone),
            resolvedStartDate: result.resolvedDate,
            resolvedSourceTimeZone: result.resolvedSourceTimeZone,
            resolvedDestinationTimeZone: destinationTimeZone,
            defaultTitle: "Meeting",
            defaultDurationMinutes: 30,
            defaultProvider: preferredProvider
        )
    }

    private static func localDateString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

protocol CalendarDraftRouting {
    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool
    func draftURL(for submission: ScheduleMeetingSubmission) -> URL?
}

final class CalendarDraftRouter: CalendarDraftRouting {
    private let appleCalendarOpener: CalendarDraftOpening
    private let googleCalendarOpener: CalendarDraftOpening

    init(
        appleCalendarOpener: CalendarDraftOpening = AppleCalendarDraftOpener(),
        googleCalendarOpener: CalendarDraftOpening = GoogleCalendarDraftOpener()
    ) {
        self.appleCalendarOpener = appleCalendarOpener
        self.googleCalendarOpener = googleCalendarOpener
    }

    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool {
        switch submission.provider {
        case .appleCalendar:
            return appleCalendarOpener.openDraft(submission)
        case .googleCalendar:
            return googleCalendarOpener.openDraft(submission)
        }
    }

    func draftURL(for submission: ScheduleMeetingSubmission) -> URL? {
        switch submission.provider {
        case .appleCalendar:
            return appleCalendarOpener.draftURL(for: submission)
        case .googleCalendar:
            return googleCalendarOpener.draftURL(for: submission)
        }
    }
}

protocol CalendarDraftOpening {
    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool
    func draftURL(for submission: ScheduleMeetingSubmission) -> URL?
}

protocol WorkspaceOpening {
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

protocol TemporaryFileWriting {
    func writeTemporaryFile(named fileName: String, contents: Data) throws -> URL
}

struct DefaultTemporaryFileWriter: TemporaryFileWriting {
    private let directoryProvider: () -> URL

    init(directoryProvider: @escaping () -> URL = { FileManager.default.temporaryDirectory }) {
        self.directoryProvider = directoryProvider
    }

    func writeTemporaryFile(named fileName: String, contents: Data) throws -> URL {
        let url = directoryProvider().appendingPathComponent(fileName)
        try contents.write(to: url, options: .atomic)
        return url
    }
}

final class AppleCalendarDraftOpener: CalendarDraftOpening {
    private let workspace: WorkspaceOpening
    private let temporaryFileWriter: TemporaryFileWriting

    init(
        workspace: WorkspaceOpening = NSWorkspace.shared,
        temporaryFileWriter: TemporaryFileWriting = DefaultTemporaryFileWriter()
    ) {
        self.workspace = workspace
        self.temporaryFileWriter = temporaryFileWriter
    }

    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool {
        guard let url = draftURL(for: submission) else {
            return false
        }
        return workspace.open(url)
    }

    func draftURL(for submission: ScheduleMeetingSubmission) -> URL? {
        guard let data = icsData(for: submission) else {
            return nil
        }

        return try? temporaryFileWriter.writeTemporaryFile(
            named: "offset-meeting-\(UUID().uuidString).ics",
            contents: data
        )
    }

    func icsData(for submission: ScheduleMeetingSubmission) -> Data? {
        let timeZone = submission.draft.resolvedDestinationTimeZone
        let lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Offset//Schedule Meeting//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString.lowercased())",
            "DTSTAMP:\(Self.utcTimestampString(for: Date()))",
            "SUMMARY:\(Self.escapeICS(submission.title))",
            "DTSTART;TZID=\(timeZone.identifier):\(Self.localTimestampString(for: submission.startDate, timeZone: timeZone))",
            "DTEND;TZID=\(timeZone.identifier):\(Self.localTimestampString(for: submission.endDate, timeZone: timeZone))",
            "DESCRIPTION:\(Self.escapeICS("Created from \"\(submission.draft.sourceText)\" in Offset"))",
            "END:VEVENT",
            "END:VCALENDAR",
            ""
        ]

        return lines.joined(separator: "\r\n").data(using: .utf8)
    }

    private static func escapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func localTimestampString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func utcTimestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

final class GoogleCalendarDraftOpener: CalendarDraftOpening {
    private let workspace: WorkspaceOpening

    init(workspace: WorkspaceOpening = NSWorkspace.shared) {
        self.workspace = workspace
    }

    func openDraft(_ submission: ScheduleMeetingSubmission) -> Bool {
        guard let url = draftURL(for: submission) else {
            return false
        }

        return workspace.open(url)
    }

    func draftURL(for submission: ScheduleMeetingSubmission) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: submission.title),
            URLQueryItem(
                name: "dates",
                value: "\(Self.googleTimestampString(for: submission.startDate))/\(Self.googleTimestampString(for: submission.endDate))"
            ),
            URLQueryItem(name: "ctz", value: submission.draft.resolvedDestinationTimeZone.identifier),
            URLQueryItem(name: "details", value: "Created from \"\(submission.draft.sourceText)\" in Offset")
        ]
        return components?.url
    }

    private static func googleTimestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
