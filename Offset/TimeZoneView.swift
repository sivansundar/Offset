import Combine
import SwiftUI

struct WorldClockEntry: Identifiable {
    let id = UUID()
    let city: String
    let timeZoneIdentifier: String
    let label: String
    let converter: TimeConverter

    static func defaultEntries(converter: TimeConverter = TimeConverter()) -> [WorldClockEntry] {
        [
            WorldClockEntry(city: "New York", timeZoneIdentifier: "America/New_York", label: "ET", converter: converter),
            WorldClockEntry(city: "London", timeZoneIdentifier: "Europe/London", label: "GMT/BST", converter: converter),
            WorldClockEntry(city: "Tokyo", timeZoneIdentifier: "Asia/Tokyo", label: "JST", converter: converter),
            WorldClockEntry(city: "Dubai", timeZoneIdentifier: "Asia/Dubai", label: "GST", converter: converter),
        ]
    }

    func currentTimeString(at date: Date) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    func offsetString(at date: Date) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return ""
        }
        return converter.utcOffsetString(for: timeZone, at: date)
    }
}

@MainActor
final class TimeZoneViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var inlineResult: String?
    @Published private(set) var worldClocks: [WorldClockEntry]
    @Published private(set) var referenceDate: Date

    private let converter: TimeConverter
    private let nowProvider: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let calendarProvider: () -> Calendar

    init(
        converter: TimeConverter = TimeConverter(),
        nowProvider: @escaping () -> Date = Date.init,
        timeZoneProvider: @escaping () -> TimeZone = { .current },
        calendarProvider: @escaping () -> Calendar = { .current }
    ) {
        self.converter = converter
        self.nowProvider = nowProvider
        self.timeZoneProvider = timeZoneProvider
        self.calendarProvider = calendarProvider
        self.referenceDate = nowProvider()
        self.worldClocks = WorldClockEntry.defaultEntries(converter: converter)
    }

    var localTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZoneProvider()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: referenceDate)
    }

    var localTimeZoneLabel: String {
        let zone = timeZoneProvider()
        let city = zone.identifier.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ") ?? zone.identifier
        let abbreviation = zone.abbreviation(for: referenceDate) ?? zone.identifier
        return "\(city) (\(abbreviation))"
    }

    func submitConversion() {
        switch converter.parseAndConvert(
            inputText,
            to: timeZoneProvider(),
            now: nowProvider(),
            calendar: calendarProvider()
        ) {
        case let .success(result):
            inlineResult = result.inlineDisplay
        case let .failure(error):
            inlineResult = error.errorDescription
        }
    }

    func refreshClocks(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }
}

struct TimeZoneView: View {
    @ObservedObject var viewModel: TimeZoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.localTimeString)
                    .font(.system(size: 32, weight: .semibold))
                Text(viewModel.localTimeZoneLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.worldClocks) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.city)
                            Text(entry.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.currentTimeString(at: viewModel.referenceDate))
                            Text(entry.offsetString(at: viewModel.referenceDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Enter a time to convert...", text: $viewModel.inputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.submitConversion()
                        }

                    Button("Convert") {
                        viewModel.submitConversion()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }

                if let inlineResult = viewModel.inlineResult {
                    Text(inlineResult)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial)
    }
}
