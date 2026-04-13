import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingController: NSHostingController<TimeZoneView>
    private let clock: ClockProviding
    private let viewModel: TimeZoneViewModel
    private let calendar: Calendar
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        statusBar: NSStatusBar = .system,
        clock: ClockProviding = SystemClock(),
        viewModel: TimeZoneViewModel? = nil,
        calendar: Calendar = .current
    ) {
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.clock = clock
        self.viewModel = viewModel ?? TimeZoneViewModel()
        self.calendar = calendar
        self.hostingController = NSHostingController(rootView: TimeZoneView(viewModel: self.viewModel))

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        bindViewModel()

        refreshStatusTitle()
        scheduleTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func refreshStatusTitle() {
        statusItem.button?.title = Self.statusTitle(for: clock.now(), calendar: calendar)
        viewModel.refreshClocks(referenceDate: clock.now())
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.secondsUntilNextMinute(from: clock.now(), calendar: calendar), repeats: false) { [weak self] _ in
            self?.refreshStatusTitle()
            self?.scheduleTimer()
        }
    }

    func bindViewModel() {
        viewModel.$inlineResult
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePopoverSize()
            }
            .store(in: &cancellables)
    }

    func updatePopoverSize() {
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        popover.contentSize = NSSize(
            width: max(320, fittingSize.width),
            height: max(360, fittingSize.height)
        )
    }

    nonisolated static func statusTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    nonisolated static func secondsUntilNextMinute(from date: Date, calendar: Calendar) -> TimeInterval {
        let seconds = calendar.component(.second, from: date)
        return TimeInterval(max(1, 60 - seconds))
    }
}

protocol ClockProviding {
    func now() -> Date
}

struct SystemClock: ClockProviding {
    func now() -> Date {
        Date()
    }
}
