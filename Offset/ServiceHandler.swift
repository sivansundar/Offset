import AppKit
import Foundation

struct ServiceResultDescriptor: Equatable {
    let title: String
    let body: String
}

protocol ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor)
}

@MainActor
struct AlertPresenter: ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = descriptor.title
        alert.informativeText = descriptor.body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class ServiceHandler: NSObject {
    private let converter: TimeConverter
    private let presenter: ServiceResultPresenting
    private let destinationTimeZoneProvider: () -> TimeZone
    private let nowProvider: () -> Date
    private let calendarProvider: () -> Calendar

    init(
        converter: TimeConverter = TimeConverter(),
        presenter: ServiceResultPresenting? = nil,
        destinationTimeZoneProvider: @escaping () -> TimeZone = { .current },
        nowProvider: @escaping () -> Date = Date.init,
        calendarProvider: @escaping () -> Calendar = { .current }
    ) {
        self.converter = converter
        self.presenter = presenter ?? AlertPresenter()
        self.destinationTimeZoneProvider = destinationTimeZoneProvider
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func handleSelectedText(_ text: String) -> ServiceResultDescriptor {
        switch converter.parseAndConvert(
            text,
            to: destinationTimeZoneProvider(),
            now: nowProvider(),
            calendar: calendarProvider()
        ) {
        case let .success(result):
            return ServiceResultDescriptor(
                title: "Offset - Time Converted",
                body: result.notificationBody
            )
        case .failure:
            return ServiceResultDescriptor(
                title: "Offset - Time Converted",
                body: "Couldn't find a time in the selected text."
            )
        }
    }

    @objc func convertSelectedTime(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let text = pasteboard.string(forType: .string) ?? ""
        let descriptor = handleSelectedText(text)
        presenter.present(descriptor)
    }
}
