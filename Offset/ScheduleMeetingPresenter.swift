import AppKit
import SwiftUI

protocol MeetingDraftPresenting {
    func present(
        _ draft: ScheduleMeetingDraft,
        anchor: ServicePresentationAnchor,
        onSubmit: @escaping (ScheduleMeetingSubmission) -> Void,
        onCopy: @escaping (ScheduleMeetingSubmission) -> Void,
        onCancel: @escaping () -> Void
    )
    func dismiss()
}

@MainActor
final class ScheduleMeetingPresenter: MeetingDraftPresenting {
    private var panel: ScheduleMeetingPanel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func present(
        _ draft: ScheduleMeetingDraft,
        anchor: ServicePresentationAnchor,
        onSubmit: @escaping (ScheduleMeetingSubmission) -> Void,
        onCopy: @escaping (ScheduleMeetingSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let panel = panel ?? makePanel()
        let contentView = NSHostingView(
            rootView: ScheduleMeetingPanelView(
                draft: draft,
                onSubmit: onSubmit,
                onCopy: onCopy,
                onCancel: onCancel
            )
        )
        let fittingSize = contentView.fittingSize
        let frame = Self.frameForPanel(
            panelSize: fittingSize,
            anchor: anchor,
            visibleFrame: TooltipPresenter.visibleFrame(for: anchor)
        )

        panel.contentView = contentView
        panel.setContentSize(fittingSize)
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitorsIfNeeded()
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeDismissMonitors()
    }

    private func installDismissMonitorsIfNeeded() {
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, event.window !== self.panel else {
                    return event
                }
                self.dismiss()
                return event
            }
        }

        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    private func removeDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func makePanel() -> ScheduleMeetingPanel {
        let panel = ScheduleMeetingPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel
        return panel
    }

    nonisolated static func frameForPanel(
        panelSize: NSSize,
        anchor: ServicePresentationAnchor,
        visibleFrame: NSRect
    ) -> NSRect {
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 16
        let cursorGap: CGFloat = 16
        let width = max(420, min(panelSize.width, 520))
        let height = max(292, min(panelSize.height, 420))
        let targetRect = anchor.selectionRect.map {
            NSRect(x: $0.origin.x, y: $0.origin.y, width: $0.width, height: $0.height)
        } ?? NSRect(
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
}

private final class ScheduleMeetingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ScheduleMeetingPanelView: View {
    let draft: ScheduleMeetingDraft
    let onSubmit: (ScheduleMeetingSubmission) -> Void
    let onCopy: (ScheduleMeetingSubmission) -> Void
    let onCancel: () -> Void

    @Namespace private var glassNamespace
    @State private var title: String
    @State private var durationMinutes: Int
    @State private var provider: CalendarDraftProvider
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
    }

    init(
        draft: ScheduleMeetingDraft,
        onSubmit: @escaping (ScheduleMeetingSubmission) -> Void,
        onCopy: @escaping (ScheduleMeetingSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSubmit = onSubmit
        self.onCopy = onCopy
        self.onCancel = onCancel
        _title = State(initialValue: draft.defaultTitle)
        _durationMinutes = State(initialValue: draft.defaultDurationMinutes)
        _provider = State(initialValue: draft.defaultProvider)
    }

    var body: some View {
        ZStack {
            panelBackdrop

            Group {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 14) {
                        content
                    }
                } else {
                    content
                }
            }
            .padding(20)
        }
        .frame(width: 468, alignment: .leading)
        .background(windowBackground)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerCard
            scheduleSummaryCard
            detailsCard
            actionBar
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Schedule Meeting")
                            .font(.title3.weight(.semibold))
                        Text("Turn this resolved time into a shareable calendar draft with the title, duration, and destination you choose.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer(minLength: 0)

                sourceBadge
            }
        }
        .padding(18)
        .modifier(SchedulePanelCardModifier(emphasized: true, namespace: glassNamespace, id: "header"))
    }

    private var scheduleSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolved Time")
                .font(.headline)

            VStack(spacing: 10) {
                summaryRow(
                    title: "Source time",
                    value: draft.sourceDisplay,
                    symbol: "globe"
                )
                summaryRow(
                    title: "Your time",
                    value: draft.localDisplay,
                    symbol: "sparkles.rectangle.stack"
                )
                summaryRow(
                    title: "Resolved date",
                    value: draft.localDateDisplay,
                    symbol: "calendar"
                )
            }
        }
        .padding(18)
        .modifier(SchedulePanelCardModifier(namespace: glassNamespace, id: "summary"))
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Event Details")
                .font(.headline)

            detailField(
                title: "Meeting Title",
                subtitle: "Name the event before you create the draft.",
                systemImage: "text.cursor"
            ) {
                TextField("Meeting title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focusedField, equals: .title)
            }

            detailField(
                title: "Duration",
                subtitle: "Choose how long this meeting should last.",
                systemImage: "timer"
            ) {
                Picker("Duration", selection: $durationMinutes) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }

            detailField(
                title: "Calendar",
                subtitle: "Pick where Offset should open the event draft.",
                systemImage: "calendar.badge.clock"
            ) {
                Picker("Calendar", selection: $provider) {
                    ForEach(CalendarDraftProvider.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }
        }
        .padding(18)
        .modifier(SchedulePanelCardModifier(namespace: glassNamespace, id: "details"))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)

            Spacer()

            copyButton

            if #available(macOS 26.0, *) {
                Button {
                    submit()
                } label: {
                    Label("Create Draft", systemImage: "sparkles")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    submit()
                } label: {
                    Label("Create Draft", systemImage: "sparkles")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var copyButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                copyDraftLink()
            } label: {
                Label("Copy Draft Link", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
        } else {
            Button {
                copyDraftLink()
            } label: {
                Label("Copy Draft Link", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func detailField<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .padding(8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            content()
                .padding(.leading, 46)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceBadge: some View {
        Label("Selected Text", systemImage: "text.cursor")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10), in: Capsule(style: .continuous))
            .foregroundStyle(.secondary)
    }

    private func summaryRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelBackdrop: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.cyan.opacity(0.10),
                Color.blue.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 170, height: 170)
                .blur(radius: 36)
                .offset(x: 34, y: -56)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.mint.opacity(0.12))
                .frame(width: 150, height: 150)
                .blur(radius: 42)
                .offset(x: -26, y: 42)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var windowBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.14))
            )
            .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
    }

    private func submit() {
        onSubmit(
            draft.submission(
                title: title,
                durationMinutes: durationMinutes,
                provider: provider
            )
        )
    }

    private func copyDraftLink() {
        onCopy(
            draft.submission(
                title: title,
                durationMinutes: durationMinutes,
                provider: provider
            )
        )
    }
}

private struct SchedulePanelCardModifier: ViewModifier {
    var emphasized = false
    let namespace: Namespace.ID
    let id: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    emphasized
                        ? .regular.tint(.white.opacity(0.08)).interactive()
                        : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .glassEffectID(id, in: namespace)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                )
        }
    }
}
