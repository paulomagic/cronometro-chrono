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
        let schema = Schema([SessionRecord.self, LapRecord.self])
        let configuration = ModelConfiguration("ChronoHUD", schema: schema)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Unable to create the local data store: \(error)")
        }
        self.container = container
        let model = AppModel(container: container)
        _appModel = StateObject(wrappedValue: model)
        DispatchQueue.main.async { model.start() }
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
}

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
    @Published var shortcutError: String?
    @Published var completionPulse = false
    @Published var eventLogExpanded = true

    private let snapshotStore = SnapshotStore()
    private let notificationService = NotificationService()
    private let hotKeys = GlobalHotKeyService()
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var onboardingController: OnboardingWindowController?

    lazy var overlayController = OverlayPanelController(appModel: self)

    init(container: ModelContainer) {
        settings = SettingsStore()
        engine = TimerEngine(preferences: settings.preferences)
        repository = SessionRepository(container: container)
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
        engine.onSessionFinalized = { [weak self] in self?.repository.insert($0) }
        engine.onIntervalCompleted = { [weak self] _, _ in
            guard let self else { return }
            notificationService.cancelCompletion()
            if settings.preferences.soundEnabled { notificationService.playCompletionSound() }
            completionPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.completionPulse = false }
        }
        settings.$preferences
            .dropFirst()
            .sink { [weak self] preferences in
                guard let self else { return }
                engine.applyPreferences(preferences)
                overlayController.applyPreferences()
                registerHotKeys()
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

    private func registerHotKeys() {
        let showStatus = hotKeys.register(.showHide, shortcut: settings.preferences.showHideShortcut) { [weak self] in self?.toggleHUD() }
        let clickStatus = hotKeys.register(.clickThrough, shortcut: settings.preferences.clickThroughShortcut) { [weak self] in self?.toggleClickThrough() }
        shortcutError = (showStatus == noErr && clickStatus == noErr) ? nil : String(localized: "shortcut.conflict")
    }

    private func scheduleCompletionIfNeeded() {
        guard engine.state == .running, engine.mode != .stopwatch, settings.preferences.notificationsEnabled else { return }
        let title = engine.mode == .pomodoro ? String(localized: "notification.pomodoro.title") : String(localized: "notification.timer.title")
        let body = engine.mode == .pomodoro ? String(localized: "notification.pomodoro.body") : String(localized: "notification.timer.body")
        Task {
            await notificationService.scheduleCompletion(
                after: engine.displayedInterval,
                title: title,
                body: body,
                sound: settings.preferences.soundEnabled
            )
        }
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
