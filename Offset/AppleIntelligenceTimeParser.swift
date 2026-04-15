import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceAvailability: Equatable {
    case unsupportedOS
    case available
    case unavailable(reason: String)

    var statusMessage: String {
        switch self {
        case .unsupportedOS:
            return "Requires macOS 26 or later."
        case .available:
            return "Available on this Mac."
        case let .unavailable(reason):
            return reason
        }
    }
}

protocol AppleIntelligenceTimeParsing {
    func availability() -> AppleIntelligenceAvailability
    func normalizeTimeExpression(
        _ input: String,
        supportedAbbreviations: [String: String]
    ) async -> String?
}

struct AppleIntelligenceTimeParser: AppleIntelligenceTimeParsing {
    func availability() -> AppleIntelligenceAvailability {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This Mac is not eligible for Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Apple Intelligence is turned off in System Settings.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The on-device Apple model is not ready yet.")
            @unknown default:
                return .unavailable(reason: "Apple Intelligence is unavailable on this Mac.")
            }
        }
#endif
        return .unsupportedOS
    }

    func normalizeTimeExpression(
        _ input: String,
        supportedAbbreviations: [String: String]
    ) async -> String? {
#if canImport(FoundationModels)
        guard #available(macOS 26.0, *), case .available = availability() else {
            return nil
        }

        let supportedList = supportedAbbreviations.keys.sorted().joined(separator: ", ")
        let session = LanguageModelSession(
            model: .default,
            instructions: """
            Extract a time expression for timezone conversion.
            Return parseable data only when the user explicitly specifies a time and a supported timezone or city.
            Never invent or assume a time, timezone, or city.
            Provide exact evidence snippets copied from the input for the time reference and timezone or city reference.
            Map city or region references to one supported timezone abbreviation when obvious.
            Supported timezone abbreviations: \(supportedList).
            """
        )

        do {
            let response = try await session.respond(
                to: """
                Normalize this input into structured time data for a time conversion app.
                Input: \(input)
                """,
                generating: TimeNormalization.self,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 160)
            )

            let content = response.content
            guard content.isParseable else {
                return nil
            }

            guard hasUsableEvidence(in: input, content: content, supportedAbbreviations: supportedAbbreviations) else {
                return nil
            }

            guard
                let timeZoneAbbreviation = content.timeZoneAbbreviation?.uppercased(),
                supportedAbbreviations[timeZoneAbbreviation] != nil,
                let hour24 = content.hour24,
                let minute = content.minute,
                (0...23).contains(hour24),
                (0...59).contains(minute)
            else {
                return nil
            }

            let dayReference = content.dayReference?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let supportedDayReferences: Set<String> = [
                "today",
                "tomorrow",
                "sunday",
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday",
                "next sunday",
                "next monday",
                "next tuesday",
                "next wednesday",
                "next thursday",
                "next friday",
                "next saturday",
            ]

            let timeString = String(format: "%02d:%02d", hour24, minute)
            if let dayReference, supportedDayReferences.contains(dayReference) {
                return "\(dayReference) \(timeString) \(timeZoneAbbreviation)"
            }

            return "\(timeString) \(timeZoneAbbreviation)"
        } catch {
            return nil
        }
#else
        return nil
#endif
    }

    @available(macOS 26.0, *)
    private func hasUsableEvidence(
        in input: String,
        content: TimeNormalization,
        supportedAbbreviations: [String: String]
    ) -> Bool {
        let lowercaseInput = input.lowercased()

        guard
            let timeEvidence = content.timeEvidence?.trimmingCharacters(in: .whitespacesAndNewlines),
            let zoneEvidence = content.zoneEvidence?.trimmingCharacters(in: .whitespacesAndNewlines),
            !timeEvidence.isEmpty,
            !zoneEvidence.isEmpty,
            lowercaseInput.contains(timeEvidence.lowercased()),
            lowercaseInput.contains(zoneEvidence.lowercased()),
            isTimeEvidence(timeEvidence)
        else {
            return false
        }

        if supportedAbbreviations[zoneEvidence.uppercased()] != nil {
            return true
        }

        return isLikelyPlaceEvidence(zoneEvidence)
    }

    private func isTimeEvidence(_ text: String) -> Bool {
        let lowercase = text.lowercased()
        let patterns = [
            #"\b([0]?\d|1[0-2])(?::([0-5]\d))?\s*(am|pm)\b"#,
            #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lowercase.startIndex..<lowercase.endIndex, in: lowercase)
                if regex.firstMatch(in: lowercase, range: range) != nil {
                    return true
                }
            }
        }

        let namedTimeSignals = [
            "noon",
            "midnight",
            "morning",
            "afternoon",
            "evening",
            "tonight",
            "today",
            "tomorrow",
        ]

        return namedTimeSignals.contains { lowercase.contains($0) }
    }

    private func isLikelyPlaceEvidence(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count >= 3 else {
            return false
        }

        let bannedWords = [
            "openrouter",
            "text",
            "completion",
            "completions",
            "more",
            "lot",
            "does",
        ]

        return !bannedWords.contains(cleaned)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "Structured time details extracted from natural language for timezone conversion.")
private struct TimeNormalization {
    @Guide(description: "True only if the input contains a clear, specific time and a supported timezone.")
    var isParseable: Bool

    @Guide(description: "An exact copied substring from the input that shows the time reference, such as '9am' or 'noon tomorrow'.")
    var timeEvidence: String?

    @Guide(description: "An exact copied substring from the input that shows the timezone or city reference, such as 'PT' or 'Tokyo'.")
    var zoneEvidence: String?

    @Guide(description: "One supported timezone abbreviation such as PT, EST, CET, JST, IST, or UTC.")
    var timeZoneAbbreviation: String?

    @Guide(description: "Hour in 24-hour format, from 0 through 23.")
    var hour24: Int?

    @Guide(description: "Minute in the hour, from 0 through 59.")
    var minute: Int?

    @Guide(description: "Optional day reference: today, tomorrow, a weekday name, or next followed by a weekday.")
    var dayReference: String?
}
#endif
