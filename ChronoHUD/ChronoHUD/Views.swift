import AppKit
import SwiftData
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        OverlayContentView(
            engine: appModel.engine,
            settings: appModel.settings
        )
            .environmentObject(appModel)
    }
}

private struct OverlayContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: SettingsStore

    private var preferences: UserPreferences { settings.preferences }
    private var accent: Color { Color.chronoAccent(preferences.accent) }
    private var isPremium: Bool { preferences.theme == .premium }

    var body: some View {
        Group {
            if preferences.compactMode {
                MinimalOverlayView(
                    display: engine.display,
                    mode: engine.mode,
                    state: engine.state,
                    showMilliseconds: preferences.showMilliseconds,
                    accent: accent,
                    isPremium: isPremium,
                    toggleTimer: appModel.toggleTimer,
                    resetTimer: appModel.resetTimer,
                    showFullLayout: showFullLayout
                )
            } else {
                fullBody
            }
        }
        .environment(\.colorScheme, isPremium ? .dark : .light)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: preferences.compactMode ? 14 : 18, style: .continuous))
        .shadow(color: isPremium ? accent.opacity(0.20) : .black.opacity(0.12), radius: 18)
        .overlay {
            if appModel.completionPulse {
                RoundedRectangle(cornerRadius: 18).stroke(accent, lineWidth: 3).transition(.opacity)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.25), value: appModel.completionPulse)
        .accessibilityElement(children: .contain)
    }

    private var fullBody: some View {
        VStack(spacing: 14) {
            HStack {
                Label("CHRONO // HUD", systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                statusPill
                Button(action: showEssentialLayout) {
                    Image(systemName: "rectangle.compress.vertical")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "overlay.layout.essential"))
                .help(String(localized: "overlay.layout.essential"))
                Button { appModel.togglePinned() } label: {
                    Image(systemName: appModel.isPinned ? "pin.fill" : "pin")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appModel.isPinned ? String(localized: "overlay.unpin") : String(localized: "overlay.pin"))
                .help(appModel.isPinned ? String(localized: "overlay.unpin") : String(localized: "overlay.pin"))
                Button(role: .destructive, action: appModel.quit) {
                    Image(systemName: "xmark")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "action.quit"))
                .help(String(localized: "action.quit"))
            }

            Picker("", selection: Binding(get: { engine.mode }, set: { appModel.requestModeChange($0) })) {
                ForEach(TimerMode.allCases) { mode in Text(LocalizedStringKey(mode.titleKey)).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if engine.mode == .pomodoro {
                HStack {
                    Text(LocalizedStringKey(engine.pomodoroPhase.titleKey))
                    Spacer()
                    Text(String(format: String(localized: "pomodoro.cycle"), engine.pomodoroCycle))
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }

            TextField(String(localized: "session.name.placeholder"), text: $engine.sessionName)
                .textFieldStyle(.plain)
                .font(.caption)
                .multilineTextAlignment(.center)

            TimerReadoutView(
                display: engine.display,
                mode: engine.mode,
                phaseDuration: engine.phaseDuration,
                showMilliseconds: preferences.showMilliseconds,
                accent: accent,
                isPremium: isPremium,
                compact: false
            )

            HStack(spacing: 10) {
                Button(engine.state.localizedActionTitle) {
                    appModel.toggleTimer()
                }
                .buttonStyle(ChronoPrimaryButtonStyle(color: accent))

                if engine.canAddLap {
                    Button(String(localized: "action.lap")) { engine.addLap() }
                        .buttonStyle(ChronoSecondaryButtonStyle())
                } else if engine.state != .idle {
                    Button(String(localized: "action.stop")) { appModel.stopTimer() }
                        .buttonStyle(ChronoSecondaryButtonStyle())
                }

                Button(String(localized: "action.reset")) { appModel.resetTimer() }
                    .buttonStyle(ChronoSecondaryButtonStyle())
            }

            if engine.mode == .stopwatch, !engine.laps.isEmpty {
                HStack(spacing: 12) {
                    ForEach(engine.laps.suffix(3)) { lap in
                        Text("#\(lap.order) \(formatInterval(lap.elapsed, milliseconds: true))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            transparencySection
            eventLogSection
        }
        .padding(18)
    }

    private var transparencySection: some View {
        VStack(spacing: 8) {
            Divider().overlay(accent.opacity(0.25))
            HStack {
                Text("overlay.transparency")
                Spacer()
                Text("\(Int((preferences.opacity * 100).rounded()))%")
                    .foregroundStyle(accent)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))

            Slider(value: opacityBinding, in: 0.2...1, step: 0.01)
                .tint(accent)

            HStack(spacing: 6) {
                ForEach([1.0, 0.8, 0.6, 0.4, 0.2], id: \.self) { value in
                    Button("\(Int(value * 100))%") {
                        appModel.updatePreferences { $0.opacity = value }
                    }
                    .buttonStyle(OpacityPresetButtonStyle(
                        color: accent,
                        selected: abs(preferences.opacity - value) < 0.005
                    ))
                }
            }
        }
    }

    private var eventLogSection: some View {
        VStack(spacing: 8) {
            Divider().overlay(accent.opacity(0.25))
            Button { appModel.toggleEventLog() } label: {
                HStack {
                    Image(systemName: appModel.eventLogExpanded ? "chevron.down" : "chevron.right")
                    Text("event.log.title")
                    Spacer()
                    Text("\(engine.events.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if appModel.eventLogExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if engine.events.isEmpty {
                                Text("event.log.empty")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 28)
                            } else {
                                ForEach(engine.events) { event in
                                    HStack(spacing: 10) {
                                        Text(formatEventTimestamp(event.timestamp))
                                            .foregroundStyle(accent.opacity(0.55))
                                        Text(event.kind.localizedTitle)
                                            .foregroundStyle(eventColor(event.kind))
                                            .frame(width: 82, alignment: .leading)
                                        Text(formatInterval(event.interval, milliseconds: true))
                                            .foregroundStyle(accent.opacity(0.65))
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .id(event.id)
                                    Divider().overlay(accent.opacity(0.08))
                                }
                            }
                        }
                    }
                    .frame(height: 116)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.12)))
                    .onChange(of: engine.events.count) { _, _ in
                        if let last = engine.events.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("export.title") {
                        do { try ExportService.exportEventLog(engine.events) }
                        catch { appModel.showError(error.localizedDescription) }
                    }
                    .disabled(engine.events.isEmpty)
                    Button("event.log.clear", role: .destructive) { engine.clearEvents() }
                        .disabled(engine.events.isEmpty)
                }
                .buttonStyle(ChronoLogButtonStyle())
            }
        }
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { preferences.opacity },
            set: { value in appModel.updatePreferences { $0.opacity = value } }
        )
    }

    private func eventColor(_ kind: TimerEventKind) -> Color {
        switch kind {
        case .started: .green
        case .resumed: .cyan
        case .paused, .stopped: .orange
        case .reset: .red
        case .completed: accent
        }
    }

    private func showEssentialLayout() {
        appModel.updatePreferences { $0.compactMode = true }
    }

    private func showFullLayout() {
        appModel.updatePreferences { $0.compactMode = false }
    }

    private var statusPill: some View {
        Text(engine.state.localizedTitle)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .foregroundStyle(accent)
    }

    @ViewBuilder private var background: some View {
        if isPremium {
            ZStack {
                Color(red: 0.015, green: 0.045, blue: 0.07).opacity(0.96)
                LinearGradient(colors: [accent.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: preferences.compactMode ? 14 : 18, style: .continuous)
            .stroke(appModel.isClickThrough ? Color.orange : (isPremium ? accent.opacity(0.38) : Color.primary.opacity(0.10)), lineWidth: appModel.isClickThrough ? 2 : 1)
    }
}

private struct MinimalOverlayView: View {
    @ObservedObject var display: TimerDisplay
    let mode: TimerMode
    let state: RunState
    let showMilliseconds: Bool
    let accent: Color
    let isPremium: Bool
    let toggleTimer: () -> Void
    let resetTimer: () -> Void
    let showFullLayout: () -> Void

    private var statusColor: Color {
        state == .running ? accent : Color.secondary.opacity(0.65)
    }

    private var statusDescription: String {
        String(
            format: String(localized: "overlay.minimal.status"),
            String(localized: String.LocalizationValue(mode.titleKey)).uppercased(),
            state.localizedTitle
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: state == .running ? accent.opacity(0.45) : .clear, radius: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatInterval(display.interval, milliseconds: showMilliseconds && mode == .stopwatch))
                    .font(.system(size: 23, weight: .bold, design: .monospaced))
                    .foregroundStyle(isPremium ? accent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .accessibilityLabel(accessibilityTime(display.interval))

                Text(statusDescription)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            HStack(spacing: 6) {
                Button(action: toggleTimer) {
                    Image(systemName: state == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(MinimalControlButtonStyle(color: accent, isPrimary: true))
                .accessibilityLabel(state.localizedActionTitle)
                .help(state.localizedActionTitle)

                Button(action: resetTimer) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(MinimalControlButtonStyle(color: accent, isPrimary: false))
                .accessibilityLabel(String(localized: "action.reset"))
                .help(String(localized: "action.reset"))

                Button(action: showFullLayout) {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .buttonStyle(MinimalControlButtonStyle(color: accent, isPrimary: false))
                .accessibilityLabel(String(localized: "overlay.layout.full"))
                .help(String(localized: "overlay.layout.full"))
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct TimerReadoutView: View {
    @ObservedObject var display: TimerDisplay
    let mode: TimerMode
    let phaseDuration: TimeInterval
    let showMilliseconds: Bool
    let accent: Color
    let isPremium: Bool
    let compact: Bool

    private var progress: Double {
        guard mode != .stopwatch, phaseDuration > 0 else { return 0 }
        return min(max(1 - display.interval / phaseDuration, 0), 1)
    }

    @ViewBuilder
    var body: some View {
        if compact {
            Text(formatInterval(display.interval, milliseconds: showMilliseconds && mode == .stopwatch))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(isPremium ? accent : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(accessibilityTime(display.interval))
            if mode != .stopwatch {
                ProgressView(value: progress).tint(accent).frame(width: 42)
            }
        } else {
            VStack(spacing: 8) {
                Text(formatInterval(display.interval, milliseconds: showMilliseconds && mode == .stopwatch))
                    .font(.system(size: 43, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                    .foregroundStyle(isPremium ? accent : .primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(accessibilityTime(display.interval))
                if mode != .stopwatch {
                    ProgressView(value: progress).tint(accent)
                }
            }
        }
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(appModel.hudVisible ? String(localized: "menu.hide") : String(localized: "menu.show")) { appModel.toggleHUD() }
        Divider()
        Button(appModel.engine.state.localizedActionTitle) { appModel.toggleTimer() }
        Button(String(localized: "action.reset")) { appModel.resetTimer() }
        Menu(String(localized: "menu.mode")) {
            ForEach(TimerMode.allCases) { mode in
                Button { appModel.requestModeChange(mode) } label: {
                    if appModel.engine.mode == mode { Label(LocalizedStringKey(mode.titleKey), systemImage: "checkmark") }
                    else { Text(LocalizedStringKey(mode.titleKey)) }
                }
            }
        }
        Divider()
        Button(appModel.isClickThrough ? String(localized: "menu.clickThrough.disable") : String(localized: "menu.clickThrough.enable")) { appModel.toggleClickThrough() }
        Button { appModel.togglePinned() } label: {
            Text(appModel.isPinned ? String(localized: "menu.unpin") : String(localized: "menu.pin"))
        }
        Divider()
        Button(String(localized: "history.title")) { openWindow(id: "history"); NSApp.activate(ignoringOtherApps: true) }
        SettingsLink { Text("settings.title") }
        Button(String(localized: "help.onboarding")) { appModel.showOnboarding() }
        if let error = appModel.shortcutError {
            Divider()
            Text(error).foregroundStyle(.red)
        }
        Divider()
        Button(String(localized: "action.quit")) { appModel.quit() }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessions: [SessionRecord]
    @State private var showingClearConfirmation = false

    private var todaySessions: [SessionRecord] { sessions.filter { Calendar.current.isDateInToday($0.startedAt) } }
    private var todayDuration: TimeInterval { todaySessions.reduce(0) { $0 + $1.activeDuration } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryCard(String(localized: "history.today"), formatInterval(todayDuration, milliseconds: false))
                summaryCard(String(localized: "history.sessions"), "\(todaySessions.count)")
                Spacer()
                Menu(String(localized: "export.title")) {
                    Button("CSV") { export { try ExportService.exportCSV(sessions) } }
                    Button("JSON") { export { try ExportService.exportJSON(sessions) } }
                }
                Button(String(localized: "history.clear"), role: .destructive) { showingClearConfirmation = true }
            }
            .padding()

            if sessions.isEmpty {
                ContentUnavailableView("history.empty", systemImage: "clock.badge.questionmark")
            } else {
                List {
                    ForEach(sessions) { session in
                        HStack {
                            Image(systemName: session.mode == .pomodoro ? "brain.head.profile" : session.mode == .countdown ? "timer" : "stopwatch")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.name ?? String(localized: String.LocalizationValue(session.mode.titleKey))).font(.headline)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatInterval(session.activeDuration, milliseconds: false)).monospacedDigit()
                            Button(role: .destructive) {
                                do { try appModel.repository.delete(session) }
                                catch { appModel.showError(error.localizedDescription) }
                            } label: {
                                Image(systemName: "trash")
                            }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(String(localized: "history.delete.session"))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("history.title")
        .confirmationDialog("history.clear.confirm", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button(String(localized: "history.clear"), role: .destructive) {
                do { try appModel.repository.deleteAll() } catch { appModel.showError(error.localizedDescription) }
            }
        }
    }

    private func summaryCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.bold()).monospacedDigit() }
            .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func export(_ action: () throws -> Void) {
        do { try action() } catch { appModel.showError(error.localizedDescription) }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            Form {
                Toggle("settings.launchAtLogin", isOn: Binding(
                    get: { appModel.settings.preferences.launchAtLogin },
                    set: { appModel.setLaunchAtLogin($0) }
                ))
                Toggle("settings.notifications", isOn: preference(\.notificationsEnabled))
                Toggle("settings.sound", isOn: preference(\.soundEnabled))
                Toggle("settings.milliseconds", isOn: preference(\.showMilliseconds))
                if let error = appModel.shortcutError { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .padding().tabItem { Label("settings.general", systemImage: "gear") }

            Form {
                durationRow("settings.countdown", keyPath: \.countdownDuration, range: 1...180)
                Toggle("settings.countdown.repeat", isOn: preference(\.countdownRepeats))
                durationRow("phase.focus", keyPath: \.focusDuration, range: 1...120)
                durationRow("phase.shortBreak", keyPath: \.shortBreakDuration, range: 1...60)
                durationRow("phase.longBreak", keyPath: \.longBreakDuration, range: 1...90)
                Stepper(value: preference(\.cyclesBeforeLongBreak), in: 1...12) {
                    Text(String(format: String(localized: "settings.cycles"), appModel.settings.preferences.cyclesBeforeLongBreak))
                }
            }
            .padding().tabItem { Label("settings.timer", systemImage: "timer") }

            Form {
                Picker("settings.theme", selection: preference(\.theme)) {
                    Text("theme.premium").tag(HUDTheme.premium)
                    Text("theme.minimal").tag(HUDTheme.minimal)
                }
                Picker("settings.accent", selection: preference(\.accent)) {
                    ForEach(AccentChoice.allCases) { Text(LocalizedStringKey("accent.\($0.rawValue)")).tag($0) }
                }
                Slider(value: preference(\.opacity), in: 0.2...1) { Text("settings.opacity") }
                Toggle("settings.compact", isOn: preference(\.compactMode))
            }
            .padding().tabItem { Label("settings.appearance", systemImage: "paintpalette") }

            Form {
                shortcutRow("shortcut.showHide", action: .showHide, shortcut: appModel.settings.preferences.showHideShortcut)
                shortcutRow("shortcut.clickThrough", action: .clickThrough, shortcut: appModel.settings.preferences.clickThroughShortcut)
                Text("shortcut.modifiers.note").font(.caption).foregroundStyle(.secondary)
            }
            .padding().tabItem { Label("settings.shortcuts", systemImage: "command") }
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<UserPreferences, Value>) -> Binding<Value> {
        Binding(get: { appModel.settings.preferences[keyPath: keyPath] }, set: { value in appModel.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private func durationRow(_ title: LocalizedStringKey, keyPath: WritableKeyPath<UserPreferences, TimeInterval>, range: ClosedRange<Int>) -> some View {
        Stepper(value: Binding(
            get: { Int(appModel.settings.preferences[keyPath: keyPath] / 60) },
            set: { minutes in appModel.updatePreferences { $0[keyPath: keyPath] = TimeInterval(minutes * 60) } }
        ), in: range) {
            LabeledContent(title) { Text("\(Int(appModel.settings.preferences[keyPath: keyPath] / 60)) min").monospacedDigit() }
        }
    }

    private func shortcutRow(_ title: LocalizedStringKey, action: GlobalHotKeyService.Action, shortcut: ShortcutDefinition) -> some View {
        Picker(title, selection: Binding(
            get: { shortcut.keyCode },
            set: { keyCode in
                appModel.updatePreferences {
                    if action == .showHide { $0.showHideShortcut.keyCode = keyCode }
                    else { $0.clickThroughShortcut.keyCode = keyCode }
                }
            }
        )) {
            ForEach(ShortcutKeyOption.all) { option in Text("⌘⇧\(option.label)").tag(option.keyCode) }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("onboarding.front.title", "onboarding.front.body", "rectangle.on.rectangle"),
        ("onboarding.menu.title", "onboarding.menu.body", "menubar.rectangle"),
        ("onboarding.click.title", "onboarding.click.body", "cursorarrow.rays")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: pages[page].2).font(.system(size: 64)).foregroundStyle(.cyan)
            Text(LocalizedStringKey(pages[page].0)).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(LocalizedStringKey(pages[page].1)).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
            Spacer()
            HStack {
                Button("onboarding.skip") { appModel.finishOnboarding() }
                Spacer()
                HStack { ForEach(0..<pages.count, id: \.self) { Circle().fill($0 == page ? Color.accentColor : .secondary.opacity(0.25)).frame(width: 7, height: 7) } }
                Spacer()
                Button(page == pages.count - 1 ? String(localized: "onboarding.done") : String(localized: "onboarding.next")) {
                    if page == pages.count - 1 { appModel.finishOnboarding() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

private struct ChronoPrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.bold()).padding(.horizontal, 16).padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.55 : 0.85), in: Capsule()).foregroundStyle(.black)
    }
}

private struct ChronoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.04 : 0.09), in: Capsule())
    }
}

private struct MinimalControlButtonStyle: ButtonStyle {
    let color: Color
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .frame(width: 32, height: 32)
            .foregroundStyle(isPrimary ? Color.black : Color.primary)
            .background(
                isPrimary ? color.opacity(configuration.isPressed ? 0.62 : 0.92) : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}

private struct OpacityPresetButtonStyle: ButtonStyle {
    let color: Color
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? color : color.opacity(0.55))
            .background(selected ? color.opacity(0.12) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? color : color.opacity(0.22)))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct ChronoLogButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.white.opacity(configuration.isPressed ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView { let view = NSVisualEffectView(); view.material = material; view.blendingMode = blendingMode; view.state = .active; return view }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct ShortcutKeyOption: Identifiable {
    let label: String
    let keyCode: UInt32
    var id: UInt32 { keyCode }
    static let all = [
        ShortcutKeyOption(label: "C", keyCode: 8), ShortcutKeyOption(label: "T", keyCode: 17),
        ShortcutKeyOption(label: "H", keyCode: 4), ShortcutKeyOption(label: "P", keyCode: 35),
        ShortcutKeyOption(label: "S", keyCode: 1), ShortcutKeyOption(label: "O", keyCode: 31)
    ]
}

extension Color {
    static func chronoAccent(_ choice: AccentChoice) -> Color {
        switch choice {
        case .cyan: Color(red: 0, green: 0.96, blue: 1)
        case .green: Color(red: 0.22, green: 1, blue: 0.08)
        case .amber: Color(red: 1, green: 0.65, blue: 0.05)
        case .white: .white
        }
    }
}

func formatInterval(_ interval: TimeInterval, milliseconds: Bool) -> String {
    let safe = max(interval, 0)
    let totalMilliseconds = Int((safe * 1000).rounded(.down))
    let hours = totalMilliseconds / 3_600_000
    let minutes = (totalMilliseconds / 60_000) % 60
    let seconds = (totalMilliseconds / 1_000) % 60
    let millis = totalMilliseconds % 1_000
    let base = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    return milliseconds ? "\(base).\(String(format: "%03d", millis))" : base
}

private func formatEventTimestamp(_ date: Date) -> String {
    date.formatted(
        .dateTime
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
            .locale(Locale(identifier: "en_US_POSIX"))
    )
}

func accessibilityTime(_ interval: TimeInterval) -> String {
    let seconds = max(Int(interval.rounded()), 0)
    let hours = seconds / 3600
    let minutes = (seconds / 60) % 60
    let remainder = seconds % 60
    return String(format: String(localized: "accessibility.time"), hours, minutes, remainder)
}
