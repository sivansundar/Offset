import AppKit
import ApplicationServices
import Foundation
import SwiftUI

struct ServiceResultDescriptor: Equatable {
    let title: String
    let body: String
    var isLoading = false
}

struct ServicePresentationAnchor: Equatable {
    let selectionRect: CGRect?
    let pointerLocation: CGPoint
}

protocol ServiceResultPresenting {
    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor)
}

@MainActor
final class TooltipPresenter: ServiceResultPresenting {
    private var panel: NSPanel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func present(_ descriptor: ServiceResultDescriptor, anchor: ServicePresentationAnchor) {
        let panel = panel ?? makePanel()
        let contentView = NSHostingView(rootView: ServiceTooltipView(descriptor: descriptor))
        let fittingSize = contentView.fittingSize
        let frame = Self.frameForTooltip(
            tooltipSize: fittingSize,
            anchor: anchor,
            visibleFrame: Self.visibleFrame(for: anchor)
        )

        panel.contentView = contentView
        panel.setContentSize(fittingSize)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        installDismissMonitorsIfNeeded()
    }

    private func installDismissMonitorsIfNeeded() {
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.dismissTooltip()
                return event
            }
        }

        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismissTooltip()
            }
        }
    }

    private func dismissTooltip() {
        panel?.orderOut(nil)
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    nonisolated static func frameForTooltip(
        tooltipSize: NSSize,
        anchor: ServicePresentationAnchor,
        visibleFrame: NSRect
    ) -> NSRect {
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 12
        let cursorGap: CGFloat = 14
        let width = max(220, min(tooltipSize.width, 360))
        let height = max(68, tooltipSize.height)
        let targetRect = anchor.selectionRect.map { NSRect(x: $0.origin.x, y: $0.origin.y, width: $0.width, height: $0.height) } ?? NSRect(
            x: anchor.pointerLocation.x,
            y: anchor.pointerLocation.y,
            width: 1,
            height: 1
        )
        let minX = visibleFrame.minX + horizontalPadding
        let maxX = max(minX, visibleFrame.maxX - horizontalPadding - width)
        let centeredX = targetRect.midX - (width / 2)
        let originX = min(max(centeredX, minX), maxX)

        let minY = visibleFrame.minY + verticalPadding
        let maxY = max(minY, visibleFrame.maxY - verticalPadding - height)
        let aboveSelectionY = targetRect.maxY + cursorGap
        let belowSelectionY = targetRect.minY - height - cursorGap
        let preferredY = aboveSelectionY <= maxY ? aboveSelectionY : belowSelectionY
        let originY = min(max(preferredY, minY), maxY)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    nonisolated static func visibleFrame(for anchor: ServicePresentationAnchor) -> NSRect {
        let screens = NSScreen.screens
        if let selectionRect = anchor.selectionRect {
            let selectionCenter = NSPoint(x: selectionRect.midX, y: selectionRect.midY)
            if let screen = screens.first(where: { $0.frame.contains(selectionCenter) }) {
                return screen.visibleFrame
            }
        }

        if let screen = screens.first(where: { $0.frame.contains(anchor.pointerLocation) }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
    }
}

private struct ServiceTooltipView: View {
    let descriptor: ServiceResultDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(descriptor.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if descriptor.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text(descriptor.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(descriptor.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

@MainActor
final class ServiceHandler: NSObject {
    private let converter: TimeConverter
    private let presenter: ServiceResultPresenting
    private let anchorResolver: ServicePresentationAnchoring
    private let preferencesStore: PreferencesStore
    private let destinationTimeZoneProvider: () -> TimeZone
    private let nowProvider: () -> Date
    private let calendarProvider: () -> Calendar

    init(
        converter: TimeConverter = TimeConverter(),
        presenter: ServiceResultPresenting? = nil,
        anchorResolver: ServicePresentationAnchoring = AccessibilitySelectionAnchorResolver(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        destinationTimeZoneProvider: @escaping () -> TimeZone = { .autoupdatingCurrent },
        nowProvider: @escaping () -> Date = Date.init,
        calendarProvider: @escaping () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.converter = converter
        self.presenter = presenter ?? TooltipPresenter()
        self.anchorResolver = anchorResolver
        self.preferencesStore = preferencesStore
        self.destinationTimeZoneProvider = destinationTimeZoneProvider
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func handleSelectedText(_ text: String) async -> ServiceResultDescriptor {
        switch await converter.parseAndConvert(
            text,
            usingAppleIntelligence: preferencesStore.loadUseAppleIntelligence(),
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
        let anchor = anchorResolver.resolveAnchor()
        presenter.present(
            ServiceResultDescriptor(
                title: "Offset - Time Converted",
                body: "Checking the selected text...",
                isLoading: true
            ),
            anchor: anchor
        )

        Task { @MainActor in
            let descriptor = await handleSelectedText(text)
            presenter.present(descriptor, anchor: anchor)
        }
    }
}

protocol ServicePresentationAnchoring {
    func resolveAnchor() -> ServicePresentationAnchor
}

struct AccessibilitySelectionAnchorResolver: ServicePresentationAnchoring {
    func resolveAnchor() -> ServicePresentationAnchor {
        let pointerLocation = NSEvent.mouseLocation
        return ServicePresentationAnchor(
            selectionRect: selectedTextRect(),
            pointerLocation: pointerLocation
        )
    }

    private func selectedTextRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementObject
        ) == .success,
        let focusedElementObject,
        CFGetTypeID(focusedElementObject) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementObject, to: AXUIElement.self)
        var selectedTextRangeObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRangeObject
        ) == .success,
        let selectedTextRangeObject,
        CFGetTypeID(selectedTextRangeObject) == AXValueGetTypeID()
        else {
            return nil
        }

        let selectedTextRangeValue = unsafeBitCast(selectedTextRangeObject, to: AXValue.self)
        guard AXValueGetType(selectedTextRangeValue) == .cfRange else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(selectedTextRangeValue, .cfRange, &selectedRange),
              selectedRange.length > 0
        else {
            return nil
        }

        var boundsObject: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedTextRangeValue,
            &boundsObject
        ) == .success,
        let boundsObject,
        CFGetTypeID(boundsObject) == AXValueGetTypeID()
        else {
            return nil
        }

        let boundsValue = unsafeBitCast(boundsObject, to: AXValue.self)
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &bounds), !bounds.isEmpty else {
            return nil
        }

        return convertToAppKitCoordinates(bounds)
    }

    private func convertToAppKitCoordinates(_ rect: CGRect) -> CGRect {
        let desktopFrame = NSScreen.screens.map(\.frame).reduce(into: CGRect.null) { partialResult, frame in
            partialResult = partialResult.union(frame)
        }
        guard !desktopFrame.isNull else {
            return rect
        }

        return CGRect(
            x: rect.origin.x,
            y: desktopFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
