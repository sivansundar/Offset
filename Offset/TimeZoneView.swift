import Combine
import SwiftUI

struct WorldClockEntry: Identifiable {
    let id: String
    let timeZoneIdentifier: String
    let converter: TimeConverter

    var city: String {
        timeZoneIdentifier
            .split(separator: "/")
            .last?
            .replacingOccurrences(of: "_", with: " ") ?? timeZoneIdentifier
    }

    static func entries(
        from configurations: [WorldClockConfiguration],
        converter: TimeConverter = TimeConverter()
    ) -> [WorldClockEntry] {
        configurations.map {
            WorldClockEntry(
                id: $0.timeZoneIdentifier,
                timeZoneIdentifier: $0.timeZoneIdentifier,
                converter: converter
            )
        }
    }

    func currentLabel(at date: Date) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return timeZoneIdentifier
        }

        return timeZone.abbreviation(for: date) ?? timeZone.identifier
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

struct WorldClockConfiguration: Codable, Equatable, Identifiable {
    let timeZoneIdentifier: String

    var id: String { timeZoneIdentifier }

    static let defaults: [WorldClockConfiguration] = [
        WorldClockConfiguration(timeZoneIdentifier: "America/New_York"),
        WorldClockConfiguration(timeZoneIdentifier: "Europe/London"),
        WorldClockConfiguration(timeZoneIdentifier: "Asia/Tokyo"),
        WorldClockConfiguration(timeZoneIdentifier: "Asia/Dubai"),
    ]
}

struct AvailableTimeZone: Identifiable, Equatable {
    let id: String
    let identifier: String
    let city: String
    let region: String

    init(identifier: String) {
        self.id = identifier
        self.identifier = identifier

        let parts = identifier.split(separator: "/")
        if parts.count >= 2 {
            self.region = String(parts.first ?? "")
            self.city = parts.dropFirst().joined(separator: " / ").replacingOccurrences(of: "_", with: " ")
        } else {
            self.region = "Other"
            self.city = identifier.replacingOccurrences(of: "_", with: " ")
        }
    }
}

final class WorldClockStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "savedWorldClockIdentifiers"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> [WorldClockConfiguration] {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let configurations = try? JSONDecoder().decode([WorldClockConfiguration].self, from: data),
            !configurations.isEmpty
        else {
            return WorldClockConfiguration.defaults
        }

        return configurations
    }

    func save(_ configurations: [WorldClockConfiguration]) {
        guard let data = try? JSONEncoder().encode(configurations) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class TimeZoneViewModel: ObservableObject {
    enum Screen {
        case clocks
        case settings
    }

    @Published var inputText = ""
    @Published var inlineResult: String?
    @Published private(set) var worldClocks: [WorldClockEntry]
    @Published private(set) var referenceDate: Date
    @Published var screen: Screen = .clocks
    @Published var timeZoneSearchText = ""
    @Published var useAppleIntelligence: Bool {
        didSet {
            preferencesStore.saveUseAppleIntelligence(useAppleIntelligence)
        }
    }

    private let converter: TimeConverter
    private let nowProvider: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let calendarProvider: () -> Calendar
    private let worldClockStore: WorldClockStore
    private let preferencesStore: PreferencesStore
    private let appleIntelligenceAvailabilityProvider: () -> AppleIntelligenceAvailability
    private var worldClockConfigurations: [WorldClockConfiguration]

    init(
        converter: TimeConverter = TimeConverter(),
        nowProvider: @escaping () -> Date = Date.init,
        timeZoneProvider: @escaping () -> TimeZone = { .autoupdatingCurrent },
        calendarProvider: @escaping () -> Calendar = { .autoupdatingCurrent },
        worldClockStore: WorldClockStore = WorldClockStore(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        appleIntelligenceAvailabilityProvider: @escaping () -> AppleIntelligenceAvailability = {
            AppleIntelligenceTimeParser().availability()
        }
    ) {
        self.converter = converter
        self.nowProvider = nowProvider
        self.timeZoneProvider = timeZoneProvider
        self.calendarProvider = calendarProvider
        self.worldClockStore = worldClockStore
        self.preferencesStore = preferencesStore
        self.appleIntelligenceAvailabilityProvider = appleIntelligenceAvailabilityProvider
        self.referenceDate = nowProvider()
        self.worldClockConfigurations = worldClockStore.load()
        self.worldClocks = WorldClockEntry.entries(from: worldClockConfigurations, converter: converter)
        self.useAppleIntelligence = preferencesStore.loadUseAppleIntelligence()
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
        let abbreviation = zone.abbreviation(for: referenceDate) ?? zone.identifier
        let localizedName = zone.localizedName(for: .generic, locale: .autoupdatingCurrent)
            ?? zone.localizedName(for: .standard, locale: .autoupdatingCurrent)
            ?? zone.identifier
        return "\(localizedName) (\(abbreviation))"
    }

    var selectedTimeZones: [AvailableTimeZone] {
        worldClockConfigurations.map { AvailableTimeZone(identifier: $0.timeZoneIdentifier) }
    }

    var filteredAvailableTimeZones: [AvailableTimeZone] {
        let selectedIdentifiers = Set(worldClockConfigurations.map(\.timeZoneIdentifier))
        let trimmedSearch = timeZoneSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return TimeZone.knownTimeZoneIdentifiers
            .filter { !selectedIdentifiers.contains($0) }
            .map(AvailableTimeZone.init(identifier:))
            .filter { zone in
                guard !trimmedSearch.isEmpty else { return true }
                let haystack = "\(zone.city) \(zone.region) \(zone.identifier)".localizedLowercase
                return haystack.contains(trimmedSearch.localizedLowercase)
            }
    }

    var appleIntelligenceStatusMessage: String {
        appleIntelligenceAvailabilityProvider().statusMessage
    }

    func submitConversion() async {
        switch await converter.parseAndConvert(
            inputText,
            usingAppleIntelligence: useAppleIntelligence,
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

    func showSettings() {
        screen = .settings
    }

    func showClocks() {
        screen = .clocks
    }

    func addTimeZone(identifier: String) {
        guard !worldClockConfigurations.contains(where: { $0.timeZoneIdentifier == identifier }) else {
            return
        }

        worldClockConfigurations.append(WorldClockConfiguration(timeZoneIdentifier: identifier))
        persistWorldClocks()
    }

    func removeTimeZone(identifier: String) {
        worldClockConfigurations.removeAll { $0.timeZoneIdentifier == identifier }
        persistWorldClocks()
    }

    private func persistWorldClocks() {
        worldClockStore.save(worldClockConfigurations)
        worldClocks = WorldClockEntry.entries(from: worldClockConfigurations, converter: converter)
    }
}

struct TimeZoneView: View {
    @ObservedObject var viewModel: TimeZoneViewModel

    @Namespace private var glassNamespace
    @State private var isConverting = false
    @State private var conversionTask: Task<Void, Never>?
    @State private var orbitingIcon = false
    @State private var resultPulse = false

    var body: some View {
        ZStack {
            backgroundGradient

            Group {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 14) {
                        content
                    }
                } else {
                    content
                }
            }
            .padding(18)
        }
        .frame(width: 388)
        .onDisappear {
            conversionTask?.cancel()
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                navigationHeader

                switch viewModel.screen {
                case .clocks:
                    dashboardContent
                case .settings:
                    settingsContent
                }
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.blue.opacity(0.12),
                Color.mint.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: 70, y: -70)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -80, y: 90)
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            if viewModel.screen == .settings {
                Button {
                    withAnimation(.snappy(duration: 0.35)) {
                        viewModel.showClocks()
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offset")
                        .font(.title3.weight(.semibold))
                    Text("Time zones at a glance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.4)) {
                    if viewModel.screen == .clocks {
                        viewModel.showSettings()
                    } else {
                        viewModel.showClocks()
                    }
                }
            } label: {
                Image(systemName: viewModel.screen == .clocks ? "slider.horizontal.3" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(ControlOrbModifier())
            .help(viewModel.screen == .clocks ? "Manage world clocks" : "Close settings")
        }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard
            converterCard
            worldClockSection
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local time")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(viewModel.localTimeString)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .modifier(NumericTimeModifier())

                    Text(viewModel.localTimeZoneLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                statusBadge(
                    title: "Live",
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: .green
                )
            }

            Divider()
                .overlay(Color.white.opacity(0.18))

            HStack(spacing: 10) {
                statusBadge(
                    title: "\(viewModel.worldClocks.count) cities",
                    systemImage: "globe.americas.fill",
                    tint: .blue
                )

                statusBadge(
                    title: "Menu Bar",
                    systemImage: "menubar.rectangle",
                    tint: .mint
                )
            }
        }
        .padding(18)
        .modifier(PanelCardModifier(emphasized: true, namespace: glassNamespace, id: "hero-card"))
    }

    private var converterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick conversion")
                        .font(.headline)
                    Text("Try 9AM PT or 3:30 PM EST")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isConverting {
                    convertingIndicator
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("Enter a time to convert", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.10))
                    )
                    .onSubmit {
                        runConversion()
                    }

                convertButton
            }

            if let inlineResult = viewModel.inlineResult {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(resultPulse ? 6 : -6))

                    Text(inlineResult)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
                .scaleEffect(resultPulse ? 1.01 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatCount(2, autoreverses: true), value: resultPulse)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(18)
        .modifier(PanelCardModifier(namespace: glassNamespace, id: "converter-card"))
    }

    private var convertingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(orbitingIcon ? 360 : 0))
                Text("Converting")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                orbitingIcon = true
            }
        }
        .onDisappear {
            orbitingIcon = false
        }
    }

    @ViewBuilder
    private var convertButton: some View {
        if #available(macOS 26.0, *) {
            Button("Convert") {
                runConversion()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(isConverting)
        } else {
            Button("Convert") {
                runConversion()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(isConverting)
        }
    }

    private var worldClockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("World Clock")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.worldClocks.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.worldClocks) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.city)
                                .font(.body.weight(.semibold))
                            Text(entry.currentLabel(at: viewModel.referenceDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(entry.currentTimeString(at: viewModel.referenceDate))
                                .font(.body.weight(.semibold))
                                .modifier(NumericTimeModifier())
                            Text(entry.offsetString(at: viewModel.referenceDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.07))
                    )
                }
            }
        }
        .padding(18)
        .modifier(PanelCardModifier(namespace: glassNamespace, id: "world-clocks"))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("World Clocks")
                    .font(.title3.weight(.semibold))
                Text("Pick the cities that appear in your menu bar panel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PanelCardModifier(emphasized: true, namespace: glassNamespace, id: "settings-intro"))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Selected")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.selectedTimeZones.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.selectedTimeZones.isEmpty {
                    Text("No extra time zones selected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.selectedTimeZones) { zone in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(zone.city)
                                        .font(.body.weight(.medium))
                                    Text(zone.identifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Remove") {
                                    withAnimation(.snappy(duration: 0.35)) {
                                        viewModel.removeTimeZone(identifier: zone.identifier)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            )
                        }
                    }
                }
            }
            .padding(18)
            .modifier(PanelCardModifier(namespace: glassNamespace, id: "selected-zones"))

            VStack(alignment: .leading, spacing: 12) {
                Text("Time Parsing")
                    .font(.headline)

                Toggle(isOn: $viewModel.useAppleIntelligence) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use Apple Intelligence")
                            .font(.body.weight(.medium))
                        Text("Use Apple's on-device model when a typed time phrase needs extra help parsing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Text(viewModel.appleIntelligenceStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .modifier(PanelCardModifier(namespace: glassNamespace, id: "time-parsing"))

            VStack(alignment: .leading, spacing: 12) {
                Text("Add city")
                    .font(.headline)

                TextField("Search time zones", text: $viewModel.timeZoneSearchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.10))
                    )

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.filteredAvailableTimeZones.prefix(12))) { zone in
                        Button {
                            withAnimation(.snappy(duration: 0.35)) {
                                viewModel.addTimeZone(identifier: zone.identifier)
                                viewModel.timeZoneSearchText = ""
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(zone.city)
                                        .foregroundStyle(.primary)
                                        .font(.body.weight(.medium))
                                    Text(zone.identifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(zone.region)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .modifier(PanelCardModifier(namespace: glassNamespace, id: "search-zones"))
        }
    }

    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .foregroundStyle(tint)
    }

    private func runConversion() {
        conversionTask?.cancel()
        orbitingIcon = false

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isConverting = true
        }

        conversionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))

            guard !Task.isCancelled else {
                isConverting = false
                return
            }

            await viewModel.submitConversion()

            resultPulse.toggle()

            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                isConverting = false
            }
        }
    }
}

private struct PanelCardModifier: ViewModifier {
    var emphasized = false
    let namespace: Namespace.ID
    let id: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    emphasized ? .regular.tint(.white.opacity(0.08)).interactive() : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .glassEffectID(id, in: namespace)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10))
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
    }
}

private struct ControlOrbModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(.white.opacity(0.10))
            )
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.10))
            )
    }
}

private struct NumericTimeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}
