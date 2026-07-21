import SwiftData
import XCTest
@testable import ChronoHUD

@MainActor
final class GlobalHotKeyServiceTests: XCTestCase {
    func testInitialRegistrationAndHandlerDispatch() {
        let backend = FakeGlobalHotKeyBackend()
        let service = GlobalHotKeyService(backend: backend)
        var callCount = 0
        service.registerInitial(.quickTimer, shortcut: .quickTimer) { callCount += 1 }
        backend.fire(.quickTimer)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(service.registrationCount, 1)
    }

    func testTransactionalReplacementRollsBackOnConflict() {
        let backend = FakeGlobalHotKeyBackend()
        let service = GlobalHotKeyService(backend: backend)
        service.registerInitial(.quickTimer, shortcut: .quickTimer) {}
        let original = backend.registrations[0]
        backend.nextError = .exclusiveConflict
        var persisted = false
        XCTAssertThrowsError(try service.replace(.quickTimer, shortcut: .showHide) { persisted = true })
        XCTAssertFalse(persisted)
        XCTAssertFalse(original.cancelled)
        XCTAssertEqual(service.errors[.quickTimer], .exclusiveConflict)
    }

    func testInitialHandlerInstallationFailureIsReportedForAction() {
        let backend = FakeGlobalHotKeyBackend()
        backend.installError = .handlerInstallation(-987)
        let service = GlobalHotKeyService(backend: backend)

        service.registerInitial(.quickTimer, shortcut: .quickTimer) {}

        XCTAssertEqual(service.errors[.quickTimer], .handlerInstallation(-987))
        XCTAssertEqual(service.registrationCount, 0)
    }

    func testInitialGenericRegistrationFailureIsReportedForAction() {
        let backend = FakeGlobalHotKeyBackend()
        backend.nextError = .registration(-986)
        let service = GlobalHotKeyService(backend: backend)

        service.registerInitial(.quickTimer, shortcut: .quickTimer) {}

        XCTAssertEqual(service.errors[.quickTimer], .registration(-986))
        XCTAssertEqual(service.registrationCount, 0)
    }

    func testSuccessfulReplacementPersistsBeforeCancellingOldToken() throws {
        let backend = FakeGlobalHotKeyBackend()
        let service = GlobalHotKeyService(backend: backend)
        service.registerInitial(.quickTimer, shortcut: .quickTimer) {}
        let original = backend.registrations[0]
        try service.replace(.quickTimer, shortcut: .showHide) {
            XCTAssertFalse(original.cancelled)
        }
        XCTAssertTrue(original.cancelled)
        XCTAssertFalse(backend.registrations[1].cancelled)
    }

    func testOrdinaryPreferenceChangeDoesNotRegisterHotKeys() throws {
        let backend = FakeGlobalHotKeyBackend()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        let container = try makeContainer()
        let engine = TimerEngine(preferences: settings.preferences)
        let model = AppModel(container: container, settings: settings, engine: engine, notificationService: SilentNotificationService(), hotKeyBackend: backend)
        model.start()
        let count = backend.registrations.count
        model.updatePreferences { $0.opacity = 0.5 }
        XCTAssertEqual(backend.registrations.count, count)
        engine.reset()
    }

    func testDuplicateRequestKeepsConfirmedPreference() throws {
        let backend = FakeGlobalHotKeyBackend()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        let model = AppModel(container: try makeContainer(), settings: settings, notificationService: SilentNotificationService(), hotKeyBackend: backend)
        let original = model.effectiveShortcut(for: .quickTimer)
        model.requestShortcutChange(action: .quickTimer, keyCode: model.effectiveShortcut(for: .showHide).keyCode)
        XCTAssertEqual(model.effectiveShortcut(for: .quickTimer), original)
        XCTAssertEqual(model.shortcutErrors[.quickTimer], .duplicate(.showHide))
    }

    func testUnchangedShortcutRequestIsANoOp() throws {
        let backend = FakeGlobalHotKeyBackend()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = AppModel(container: try makeContainer(), settings: settings, notificationService: SilentNotificationService(), hotKeyBackend: backend)
        model.start()
        let count = backend.registrations.count

        model.requestShortcutChange(action: .quickTimer, keyCode: model.effectiveShortcut(for: .quickTimer).keyCode)

        XCTAssertEqual(backend.registrations.count, count)
        XCTAssertNil(model.shortcutErrors[.quickTimer])
        model.engine.reset()
    }

    func testFailedShortcutReplacementKeepsPreferenceAndOriginalRegistration() throws {
        let backend = FakeGlobalHotKeyBackend()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = AppModel(container: try makeContainer(), settings: settings, notificationService: SilentNotificationService(), hotKeyBackend: backend)
        model.start()
        let originalShortcut = model.effectiveShortcut(for: .quickTimer)
        let originalRegistration = backend.registrations[2]
        backend.nextError = .exclusiveConflict

        model.requestShortcutChange(action: .quickTimer, keyCode: 4)

        XCTAssertEqual(model.effectiveShortcut(for: .quickTimer), originalShortcut)
        XCTAssertFalse(originalRegistration.cancelled)
        XCTAssertEqual(model.shortcutErrors[.quickTimer], .exclusiveConflict)
        model.engine.reset()
    }

    func testStartupDuplicateRemainsVisibleAlongsideBackendErrors() throws {
        let backend = FakeGlobalHotKeyBackend()
        backend.nextError = .registration(-985)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.update { $0.quickTimerShortcut = $0.showHideShortcut }
        let model = AppModel(container: try makeContainer(), settings: settings, notificationService: SilentNotificationService(), hotKeyBackend: backend)

        model.start()

        XCTAssertEqual(model.shortcutErrors[.showHide], .registration(-985))
        XCTAssertEqual(model.shortcutErrors[.quickTimer], .duplicate(.showHide))
        model.engine.reset()
    }

    func testNotificationSchedulingFailureDoesNotInterruptQuickTimerOrPlaySound() throws {
        let service = FailingNotificationService()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.update {
            $0.countdownDuration = 600
            $0.countdownRepeats = true
        }
        let engine = TimerEngine(preferences: settings.preferences)
        let model = AppModel(
            container: try makeContainer(),
            settings: settings,
            engine: engine,
            notificationService: service,
            hotKeyBackend: FakeGlobalHotKeyBackend()
        )
        XCTAssertEqual(try model.submitQuickTimer(duration: 30, policy: .requireIdle), .started)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.displayedInterval, 30, accuracy: 0.1)
        XCTAssertEqual(service.scheduleCount, 1)
        XCTAssertEqual(service.soundCount, 0)
        XCTAssertEqual(service.events, [.cancel, .schedule])
        XCTAssertEqual(settings.preferences.countdownDuration, 600)
        XCTAssertTrue(settings.preferences.countdownRepeats)
        engine.reset()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SessionRecord.self, LapRecord.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
}

@MainActor
private final class FakeGlobalHotKeyBackend: GlobalHotKeyBackend {
    var handler: ((GlobalHotKeyService.Action) -> Void)?
    var registrations: [FakeRegistration] = []
    var nextError: GlobalHotKeyBackendError?
    var installError: GlobalHotKeyBackendError?

    func install(handler: @escaping (GlobalHotKeyService.Action) -> Void) throws {
        if let installError { self.installError = nil; throw installError }
        self.handler = handler
    }
    func register(_ action: GlobalHotKeyService.Action, shortcut: ShortcutDefinition) throws -> any GlobalHotKeyRegistration {
        if let nextError { self.nextError = nil; throw nextError }
        let token = FakeRegistration()
        registrations.append(token)
        return token
    }
    func fire(_ action: GlobalHotKeyService.Action) { handler?(action) }
}

@MainActor
private final class FakeRegistration: GlobalHotKeyRegistration {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}

@MainActor
private final class SilentNotificationService: CompletionNotificationServing {
    func scheduleCompletion(after interval: TimeInterval, title: String, body: String) {}
    func cancelCompletion() {}
    func playCompletionSound() {}
}

@MainActor
private final class FailingNotificationService: CompletionNotificationServing {
    enum Event: Equatable { case cancel, schedule }

    private(set) var scheduleCount = 0
    private(set) var soundCount = 0
    private(set) var events: [Event] = []
    func scheduleCompletion(after interval: TimeInterval, title: String, body: String) {
        scheduleCount += 1
        events.append(.schedule)
    }
    func cancelCompletion() { events.append(.cancel) }
    func playCompletionSound() { soundCount += 1 }
}
