import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct ChronoHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    private let container: ModelContainer

    init() {
        let (container, startupError) = Self.makeContainer()
        self.container = container
        let model = AppModel(container: container, startupError: startupError)
        _appModel = StateObject(wrappedValue: model)
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appModel)
                .modelContainer(container)
        } label: {
            Image(systemName: appModel.engine.state == .running ? "timer.circle.fill" : "timer")
                .accessibilityLabel("CHRONO HUD")
        }
        .menuBarExtraStyle(.menu)

        Window(String(localized: "history.title"), id: "history") {
            HistoryView()
                .environmentObject(appModel)
                .modelContainer(container)
                .frame(minWidth: 620, minHeight: 460)
        }
        .defaultSize(width: 720, height: 540)

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .modelContainer(container)
                .frame(width: 560, height: 500)
        }
    }

    private static func makeContainer() -> (ModelContainer, String?) {
        let schema = Schema([SessionRecord.self, LapRecord.self])
        let configuration = ModelConfiguration("ChronoHUD", schema: schema)
        do {
            return (try ModelContainer(for: schema, configurations: configuration), nil)
        } catch {
            let persistentError = error
            do {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: fallback)
                let message = String(
                    format: String(localized: "storage.fallback.message"),
                    persistentError.localizedDescription
                )
                return (container, message)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = String(localized: "storage.unavailable.title")
                alert.informativeText = error.localizedDescription
                alert.runModal()
                Foundation.exit(EXIT_FAILURE)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak static var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.engine.isActive else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "confirm.quit.title")
        alert.informativeText = String(localized: "confirm.quit.message")
        alert.addButton(withTitle: String(localized: "action.quit"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let engine: TimerEngine
    let repository: SessionRepository

    @Published var isPinned = true
    @Published var isClickThrough = false
    @Published var hudVisible = true
    @Published private(set) var shortcutErrors: [GlobalHotKeyService.Action: ShortcutRegistrationError] = [:]
    @Published var completionPulse = false
    @Published var eventLogExpanded = true

    private let snapshotStore = SnapshotStore()
    private let notificationService: any CompletionNotificationServing
    private let hotKeys: GlobalHotKeyService
    private var cancellables: Set<AnyCancellable> = []
    private var completionPulseTask: Task<Void, Never>?
    private var hasStarted = false
    private let startupError: String?
    private var onboardingController: OnboardingWindowController?

    lazy var overlayController = OverlayPanelController(appModel: self)
    lazy var quickTimerController = QuickTimerPanelController(appModel: self)

    var shortcutError: String? {
        shortcutErrors.isEmpty ? nil : String(localized: "shortcut.conflict")
    }

    init(
        container: ModelContainer,
        settings: SettingsStore? = nil,
        engine: TimerEngine? = nil,
        repository: SessionRepository? = nil,
        notificationService: (any CompletionNotificationServing)? = nil,
        startupError: String? = nil,
        hotKeyBackend: (any GlobalHotKeyBackend)? = nil
    ) {
        let resolvedSettings = settings ?? SettingsStore()
        self.settings = resolvedSettings
        self.engine = engine ?? TimerEngine(preferences: resolvedSettings.preferences)
        self.repository = repository ?? SessionRepository(container: container)
        self.notificationService = notificationService ?? NotificationService()
        hotKeys = GlobalHotKeyService(backend: hotKeyBackend ?? SystemGlobalHotKeyBackend())
        self.startupError = startupError
        wireServices()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        AppDelegate.model = self
        isClickThrough = false
        if let snapshot = snapshotStore.load() { engine.restore(snapshot) }
        registerHotKeys()
        overlayController.show()
        observeSystemEvents()
        if !UserDefaults.standard.bool(forKey: "chrono.onboarding.completed") { showOnboarding() }
        scheduleCompletionIfNeeded()
        if let startupError { showError(startupError) }
    }

    func toggleTimer() {
        engine.toggleRunning()
        if engine.state == .running { scheduleCompletionIfNeeded() }
        else { notificationService.cancelCompletion() }
    }

    func stopTimer() {
        engine.stop()
        notificationService.cancelCompletion()
    }

    func resetTimer() {
        engine.reset()
        notificationService.cancelCompletion()
    }

    func toggleEventLog() {
        eventLogExpanded.toggle()
        overlayController.applyPreferences()
    }

    func requestModeChange(_ mode: TimerMode) {
        guard engine.isActive else { engine.changeMode(to: mode); return }
        let alert = NSAlert()
        alert.messageText = String(localized: "confirm.mode.title")
        alert.informativeText = String(localized: "confirm.mode.message")
        alert.addButton(withTitle: String(localized: "action.change"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            notificationService.cancelCompletion()
            engine.changeMode(to: mode, force: true)
        }
    }

    func toggleHUD() { overlayController.toggleVisibility() }

    func toggleClickThrough() {
        if !hudVisible { overlayController.show() }
        isClickThrough.toggle()
        overlayController.setClickThrough(isClickThrough)
    }

    func togglePinned() {
        isPinned.toggle()
        overlayController.setPinned(isPinned)
    }

    func updatePreferences(_ change: (inout UserPreferences) -> Void) {
        settings.update(change)
    }

    func effectiveShortcut(for action: GlobalHotKeyService.Action) -> ShortcutDefinition {
        switch action {
        case .showHide: settings.preferences.showHideShortcut
        case .clickThrough: settings.preferences.clickThroughShortcut
        case .quickTimer: settings.preferences.effectiveQuickTimerShortcut
        }
    }

    func requestShortcutChange(action: GlobalHotKeyService.Action, keyCode: UInt32) {
        let candidateShortcut = ShortcutDefinition(keyCode: keyCode, modifiers: ShortcutDefinition.quickTimer.modifiers)
        guard candidateShortcut != effectiveShortcut(for: action) else { return }
        if let duplicate = GlobalHotKeyService.Action.allCases.first(where: {
            $0 != action && effectiveShortcut(for: $0) == candidateShortcut
        }) {
            shortcutErrors[action] = .duplicate(duplicate)
            return
        }

        var candidate = settings.preferences
        switch action {
        case .showHide: candidate.showHideShortcut = candidateShortcut
        case .clickThrough: candidate.clickThroughShortcut = candidateShortcut
        case .quickTimer: candidate.quickTimerShortcut = candidateShortcut
        }

        do {
            let encoded = try settings.encoded(candidate)
            try hotKeys.replace(action, shortcut: candidateShortcut) {
                settings.replace(with: candidate, encodedData: encoded)
            }
            shortcutErrors[action] = nil
        } catch let error as ShortcutRegistrationError {
            shortcutErrors[action] = error
        } catch {
            shortcutErrors[action] = .registration(OSStatus(paramErr))
        }
    }

    func submitQuickTimer(
        duration: TimeInterval,
        policy: QuickTimerSubmissionPolicy
    ) throws -> QuickTimerSubmissionResult {
        switch policy {
        case .requireIdle:
            do { try engine.startCountdown(duration: duration, repeats: false) }
            catch TimerEngineError.activeSession {
                return .confirmationRequired(.sessionBecameActive)
            }
        case .replaceIfActive:
            if engine.isActive {
                try engine.replaceActiveSessionWithCountdown(duration: duration, repeats: false)
            } else {
                try engine.startCountdown(duration: duration, repeats: false)
            }
        }
        notificationService.cancelCompletion()
        scheduleCompletionIfNeeded()
        overlayController.show()
        return .started
    }

    func showQuickTimerFromMenu() {
        guard let target = QuickTimerPlacementTarget.capture() else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.quickTimerController.present(at: target)
        }
    }

    func showQuickTimerFromHotKey() {
        guard let target = QuickTimerPlacementTarget.capture() else { return }
        quickTimerController.present(at: target)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            settings.update { $0.launchAtLogin = enabled }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func showOnboarding() {
        if onboardingController == nil { onboardingController = OnboardingWindowController(appModel: self) }
        onboardingController?.showWindow(nil)
        onboardingController?.window?.center()
        onboardingController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "chrono.onboarding.completed")
        onboardingController?.close()
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "error.title")
        alert.informativeText = message
        alert.runModal()
    }

    func quit() { NSApp.terminate(nil) }

    private func wireServices() {
        engine.onSnapshotChanged = { [weak self] in self?.snapshotStore.save($0) }
        engine.onSessionFinalized = { [weak self] draft in
            guard let self else { return }
            do { try repository.insert(draft) }
            catch { showError(error.localizedDescription) }
        }
        engine.onIntervalCompleted = { [weak self] _, _ in
            guard let self else { return }
            notificationService.cancelCompletion()
            if settings.preferences.soundEnabled { notificationService.playCompletionSound() }
            completionPulse = true
            completionPulseTask?.cancel()
            completionPulseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.completionPulse = false
            }
            scheduleCompletionIfNeeded()
        }
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.$preferences
            .dropFirst()
            .sink { [weak self] preferences in
                guard let self else { return }
                engine.applyPreferences(preferences)
                guard hasStarted else { return }
                overlayController.applyPreferences(preferences)
                scheduleCompletionIfNeeded(preferences)
            }
            .store(in: &cancellables)
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.engine.refreshAfterWake()
                    self?.scheduleCompletionIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func registerHotKeys(_ preferences: UserPreferences? = nil) {
        let preferences = preferences ?? settings.preferences
        var startupErrors: [GlobalHotKeyService.Action: ShortcutRegistrationError] = [:]
        let shortcuts: [GlobalHotKeyService.Action: ShortcutDefinition] = [
            .showHide: preferences.showHideShortcut,
            .clickThrough: preferences.clickThroughShortcut,
            .quickTimer: preferences.effectiveQuickTimerShortcut
        ]
        for action in GlobalHotKeyService.Action.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            if let duplicate = GlobalHotKeyService.Action.allCases.first(where: {
                $0.rawValue < action.rawValue && shortcuts[$0] == shortcut
            }) {
                startupErrors[action] = .duplicate(duplicate)
                continue
            }
            switch action {
            case .showHide:
                hotKeys.registerInitial(action, shortcut: shortcut) { [weak self] in self?.toggleHUD() }
            case .clickThrough:
                hotKeys.registerInitial(action, shortcut: shortcut) { [weak self] in self?.toggleClickThrough() }
            case .quickTimer:
                hotKeys.registerInitial(action, shortcut: shortcut) { [weak self] in self?.showQuickTimerFromHotKey() }
            }
        }
        shortcutErrors = hotKeys.errors.merging(startupErrors) { _, startupError in startupError }
    }

    private func scheduleCompletionIfNeeded(_ preferences: UserPreferences? = nil) {
        let preferences = preferences ?? settings.preferences
        guard engine.state == .running, engine.mode != .stopwatch, preferences.notificationsEnabled else {
            notificationService.cancelCompletion()
            return
        }
        let title = engine.mode == .pomodoro ? String(localized: "notification.pomodoro.title") : String(localized: "notification.timer.title")
        let body = engine.mode == .pomodoro ? String(localized: "notification.pomodoro.body") : String(localized: "notification.timer.body")
        notificationService.scheduleCompletion(after: engine.displayedInterval, title: title, body: body)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(appModel: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CHRONO HUD"
        window.contentView = NSHostingView(rootView: OnboardingView().environmentObject(appModel))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
