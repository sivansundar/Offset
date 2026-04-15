import Foundation

struct ConversionResult: Equatable {
    let sourceDisplay: String
    let localDisplay: String
    let inlineDisplay: String
    let notificationBody: String
    let resolvedSourceTimeZone: TimeZone
    let resolvedDate: Date
}

enum TimeParseError: LocalizedError, Equatable {
    case missingTime
    case missingTimeZone
    case unsupportedTimeZone
    case ambiguousTimeZone
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .missingTime, .invalidFormat:
            return "Couldn't parse that time. Try '9AM PT' or '3:30 PM EST'."
        case .missingTimeZone, .unsupportedTimeZone, .ambiguousTimeZone:
            return "Couldn't parse that time. Include a timezone like 'PT' or 'EST'."
        }
    }
}

struct TimeConverter {
    private let abbreviationMap: [String: String]
    private let appleIntelligenceParser: AppleIntelligenceTimeParsing

    init(
        abbreviationMap: [String: String] = Self.defaultAbbreviationMap,
        appleIntelligenceParser: AppleIntelligenceTimeParsing = AppleIntelligenceTimeParser()
    ) {
        self.abbreviationMap = abbreviationMap
        self.appleIntelligenceParser = appleIntelligenceParser
    }

    func parseAndConvert(
        _ input: String,
        to destinationTimeZone: TimeZone = .current,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result<ConversionResult, TimeParseError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidFormat)
        }

        guard let parsedTimeZone = parseTimeZone(in: trimmed) else {
            return .failure(.missingTimeZone)
        }

        guard let sourceTimeZone = TimeZone(identifier: parsedTimeZone.identifier) else {
            return .failure(.unsupportedTimeZone)
        }

        guard let timeComponents = parseTime(in: trimmed) else {
            return .failure(.missingTime)
        }

        let dayReference = parseDayReference(in: trimmed)
        var sourceCalendar = calendar
        sourceCalendar.timeZone = sourceTimeZone

        let baseDate = resolvedBaseDate(
            dayReference: dayReference,
            now: now,
            timeComponents: timeComponents,
            calendar: sourceCalendar
        )

        var components = sourceCalendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0

        guard let sourceDate = sourceCalendar.date(from: components) else {
            return .failure(.invalidFormat)
        }

        return .success(makeResult(
            sourceDate: sourceDate,
            sourceTimeZone: sourceTimeZone,
            sourceAbbreviation: parsedTimeZone.inputAbbreviation,
            destinationTimeZone: destinationTimeZone,
            dayReference: dayReference
        ))
    }

    func parseAndConvert(
        _ input: String,
        usingAppleIntelligence: Bool,
        to destinationTimeZone: TimeZone = .current,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Result<ConversionResult, TimeParseError> {
        let standardResult = parseAndConvert(
            input,
            to: destinationTimeZone,
            now: now,
            calendar: calendar
        )

        guard usingAppleIntelligence else {
            return standardResult
        }

        if case .success = standardResult {
            return standardResult
        }

        guard let normalizedInput = await appleIntelligenceParser.normalizeTimeExpression(
            input,
            supportedAbbreviations: abbreviationMap
        ) else {
            return standardResult
        }

        return parseAndConvert(
            normalizedInput,
            to: destinationTimeZone,
            now: now,
            calendar: calendar
        )
    }

    func utcOffsetString(for timeZone: TimeZone, at date: Date = Date()) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        if minutes == 0 {
            return String(format: "UTC%+d", hours)
        }
        return String(format: "UTC%+d:%02d", hours, minutes)
    }
}

extension TimeConverter {
    static let defaultAbbreviationMap: [String: String] = [
        "PT": "America/Los_Angeles",
        "PST": "America/Los_Angeles",
        "PDT": "America/Los_Angeles",
        "MT": "America/Denver",
        "MST": "America/Denver",
        "MDT": "America/Denver",
        "CT": "America/Chicago",
        "CST": "America/Chicago",
        "CDT": "America/Chicago",
        "ET": "America/New_York",
        "EST": "America/New_York",
        "EDT": "America/New_York",
        "GMT": "Europe/London",
        "BST": "Europe/London",
        "UTC": "UTC",
        "IST": "Asia/Kolkata",
        "CET": "Europe/Paris",
        "CEST": "Europe/Paris",
        "JST": "Asia/Tokyo",
        "AEST": "Australia/Sydney",
        "GST": "Asia/Dubai",
        "SGT": "Asia/Singapore",
    ]
}

private extension TimeConverter {
    struct ParsedTimeZone {
        let inputAbbreviation: String
        let identifier: String
    }

    enum DayReference: Equatable {
        case today
        case tomorrow
        case weekday(Int)
        case nextWeekday(Int)

        var displayText: String? {
            switch self {
            case .today:
                return "today"
            case .tomorrow:
                return "tomorrow"
            case let .weekday(value), let .nextWeekday(value):
                return Self.weekdayName(for: value)
            }
        }

        private static func weekdayName(for value: Int) -> String {
            let formatter = DateFormatter()
            return formatter.weekdaySymbols[value - 1]
        }
    }

    struct ParsedTime {
        let hour: Int
        let minute: Int
    }

    func parseTimeZone(in input: String) -> ParsedTimeZone? {
        let sortedKeys = abbreviationMap.keys.sorted { $0.count > $1.count }
        for abbreviation in sortedKeys {
            let pattern = #"(?i)\b\#(abbreviation)\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            if regex.firstMatch(in: input, range: range) != nil {
                return ParsedTimeZone(
                    inputAbbreviation: abbreviation.uppercased(),
                    identifier: abbreviationMap[abbreviation] ?? abbreviation
                )
            }
        }
        return nil
    }

    func parseTime(in input: String) -> ParsedTime? {
        let twelveHourPattern = #"(?i)\b([0]?\d|1[0-2])(?::([0-5]\d))?\s*(am|pm)\b"#
        if let regex = try? NSRegularExpression(pattern: twelveHourPattern) {
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            if let match = regex.firstMatch(in: input, range: range),
               let hourRange = Range(match.range(at: 1), in: input),
               let meridiemRange = Range(match.range(at: 3), in: input),
               let hour = Int(input[hourRange]) {
                let minute = Range(match.range(at: 2), in: input).flatMap { Int(input[$0]) } ?? 0
                var adjustedHour = hour % 12
                if input[meridiemRange].lowercased() == "pm" {
                    adjustedHour += 12
                }
                return ParsedTime(hour: adjustedHour, minute: minute)
            }
        }

        let twentyFourHourPattern = #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#
        if let regex = try? NSRegularExpression(pattern: twentyFourHourPattern) {
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            if let match = regex.firstMatch(in: input, range: range),
               let hourRange = Range(match.range(at: 1), in: input),
               let minuteRange = Range(match.range(at: 2), in: input),
               let hour = Int(input[hourRange]),
               let minute = Int(input[minuteRange]) {
                return ParsedTime(hour: hour, minute: minute)
            }
        }

        return nil
    }

    func parseDayReference(in input: String) -> DayReference? {
        let lowercase = input.lowercased()
        if lowercase.contains("tomorrow") {
            return .tomorrow
        }
        if lowercase.contains("today") {
            return .today
        }

        let weekdays: [(String, Int)] = [
            ("sunday", 1),
            ("monday", 2),
            ("tuesday", 3),
            ("wednesday", 4),
            ("thursday", 5),
            ("friday", 6),
            ("saturday", 7),
        ]

        for (name, value) in weekdays {
            if lowercase.contains("next \(name)") {
                return .nextWeekday(value)
            }
        }

        for (name, value) in weekdays {
            if lowercase.contains(name) {
                return .weekday(value)
            }
        }

        return nil
    }

    func resolvedBaseDate(
        dayReference: DayReference?,
        now: Date,
        timeComponents: ParsedTime,
        calendar: Calendar
    ) -> Date {
        let reference = dayReference ?? .today
        switch reference {
        case .today:
            return now
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case let .weekday(targetWeekday):
            return nextDate(
                for: targetWeekday,
                from: now,
                timeComponents: timeComponents,
                includeCurrentWeek: true,
                calendar: calendar
            )
        case let .nextWeekday(targetWeekday):
            return nextDate(
                for: targetWeekday,
                from: now,
                timeComponents: timeComponents,
                includeCurrentWeek: false,
                calendar: calendar
            )
        }
    }

    func nextDate(
        for targetWeekday: Int,
        from now: Date,
        timeComponents: ParsedTime,
        includeCurrentWeek: Bool,
        calendar: Calendar
    ) -> Date {
        let currentWeekday = calendar.component(.weekday, from: now)
        var delta = targetWeekday - currentWeekday
        if delta < 0 {
            delta += 7
        }

        if delta == 0 {
            let currentHour = calendar.component(.hour, from: now)
            let currentMinute = calendar.component(.minute, from: now)
            let currentValue = currentHour * 60 + currentMinute
            let targetValue = timeComponents.hour * 60 + timeComponents.minute
            if !includeCurrentWeek || targetValue <= currentValue {
                delta = 7
            }
        } else if !includeCurrentWeek {
            delta += 7
        }

        return calendar.date(byAdding: .day, value: delta, to: now) ?? now
    }

    func makeResult(
        sourceDate: Date,
        sourceTimeZone: TimeZone,
        sourceAbbreviation: String,
        destinationTimeZone: TimeZone,
        dayReference: DayReference?
    ) -> ConversionResult {
        let sourceText = timeText(for: sourceDate, in: sourceTimeZone, abbreviation: sourceAbbreviation)
        let localAbbreviation = destinationTimeZone.abbreviation(for: sourceDate) ?? destinationTimeZone.identifier
        let localText = timeText(for: sourceDate, in: destinationTimeZone, abbreviation: localAbbreviation)

        let inlineDisplay: String
        let notificationBody: String
        if let dayText = dayReference?.displayText {
            inlineDisplay = "\(sourceText) on \(dayText) -> \(localText) (your local time)"
            notificationBody = "\(sourceText) on \(dayText) = \(localText)"
        } else {
            inlineDisplay = "\(sourceText) -> \(localText) (your local time)"
            notificationBody = "\(sourceText) = \(localText)"
        }

        return ConversionResult(
            sourceDisplay: sourceText,
            localDisplay: localText,
            inlineDisplay: inlineDisplay,
            notificationBody: notificationBody,
            resolvedSourceTimeZone: sourceTimeZone,
            resolvedDate: sourceDate
        )
    }

    func timeText(for date: Date, in timeZone: TimeZone, abbreviation: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: date)) \(abbreviation)"
    }
}
