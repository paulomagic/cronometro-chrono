import Combine
import SwiftData
import SwiftUI
import UserNotifications
import XCTest
@testable import ChronoHUD

@MainActor
final class TimerEngineTests: XCTestCase {
    private enum TestError: Error {
        case saveFailed
    }

    @MainActor
    private final class NotificationSpy: CompletionNotificationServing {
        private(set) var scheduled: [CompletionNotificationRequest] = []
        private(set) var cancellationCount = 0

        func scheduleCompletion(after interval: TimeInterval, title: String, body: String) {
            scheduled.append(CompletionNotificationRequest(interval: interval, title: title, body: body))
        }

        func cancelCompletion() { cancellationCount += 1 }
        func playCompletionSound() {}
    }

    @MainActor
    private final class NotificationCenterSpy: UserNotificationCenterClient {
        var delegate: UNUserNotificationCenterDelegate?
        var status: NotificationPermissionStatus = .notDetermined
        private(set) var added: [CompletionNotificationRequest] = []
        private(set) var removalCount = 0
        private var authorizationContinuation: CheckedContinuation<Bool, Error>?
        private var addContinuation: CheckedContinuation<Void, Error>?
        var pauseNextAdd = false

        func permissionStatus() async -> NotificationPermissionStatus { status }

        func requestAuthorization() async throws -> Bool {
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
            }
        }

        func add(_ request: CompletionNotificationRequest) async throws {
            if pauseNextAdd {
                pauseNextAdd = false
                try await withCheckedThrowingContinuation { continuation in
                    addContinuation = continuation
                }
            }
            added.append(request)
        }

        func removeCompletionRequest() { removalCount += 1 }

        func resolveAuthorization(_ allowed: Bool) {
            authorizationContinuation?.resume(returning: allowed)
            authorizationContinuation = nil
        }

        func resolveAdd() {
            addContinuation?.resume()
            addContinuation = nil
        }

        var isWaitingForAuthorization: Bool { authorizationContinuation != nil }
        var isWaitingToAdd: Bool { addContinuation != nil }
    }

    private final class TestClock {
        var date = Date(timeIntervalSinceReferenceDate: 1_000)

        func advance(by interval: TimeInterval) {
            date.addTimeInterval(interval)
        }
    }

    func testStopwatchExcludesPausedTimeAndFinalizesSession() {
        let clock = TestClock()
        let engine = TimerEngine(now: { clock.date })
        var finalized: SessionDraft?
        engine.onSessionFinalized = { finalized = $0 }

        engine.start()
        clock.advance(by: 10)
        engine.pause()
        clock.advance(by: 5)
        engine.resume()
        clock.advance(by: 3)
        engine.refreshAfterWake()

        XCTAssertEqual(engine.displayedInterval, 13, accuracy: 0.001)
        XCTAssertEqual(engine.state, .running)

        engine.stop()
        XCTAssertEqual(finalized?.activeDuration ?? -1, 13, accuracy: 0.001)
        XCTAssertEqual(finalized?.result, "stopped")
        XCTAssertEqual(engine.state, .idle)
    }

    func testCountdownCompletesAndReportsProgress() {
        let clock = TestClock()
        var preferences = UserPreferences()
        preferences.countdownDuration = 60
        let engine = TimerEngine(preferences: preferences, now: { clock.date })
        var finalized: SessionDraft?
        var completion: (TimerMode, PomodoroPhase?)?
        engine.onSessionFinalized = { finalized = $0 }
        engine.onIntervalCompleted = { completion = ($0, $1) }

        XCTAssertTrue(engine.changeMode(to: .countdown))
        XCTAssertEqual(engine.displayedInterval, 60, accuracy: 0.001)
        engine.start()
        clock.advance(by: 20)
        engine.refreshAfterWake()

        XCTAssertEqual(engine.displayedInterval, 40, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 1.0 / 3.0, accuracy: 0.001)

        clock.advance(by: 40)
        engine.refreshAfterWake()
        XCTAssertEqual(engine.state, .completed)
        XCTAssertEqual(engine.displayedInterval, 0, accuracy: 0.001)
        XCTAssertEqual(finalized?.activeDuration ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(completion?.0, .countdown)
        XCTAssertNil(completion?.1)
        XCTAssertEqual(engine.events.map(\.kind), [.started, .completed])
    }

    func testCountdownRepeatsAutomaticallyAndStartsANewSession() {
        let clock = TestClock()
        var preferences = UserPreferences()
        preferences.countdownDuration = 10
        preferences.countdownRepeats = true
        let engine = TimerEngine(preferences: preferences, now: { clock.date })
        var finalized: [SessionDraft] = []
        var stateObservedByCompletion: RunState?
        engine.onSessionFinalized = { finalized.append($0) }
        engine.onIntervalCompleted = { _, _ in stateObservedByCompletion = engine.state }

        XCTAssertTrue(engine.changeMode(to: .countdown))
        engine.start()
        clock.advance(by: 10)
        engine.refreshAfterWake()

        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.displayedInterval, 10, accuracy: 0.001)
        XCTAssertEqual(finalized.count, 1)
        XCTAssertEqual(finalized[0].activeDuration, 10, accuracy: 0.001)
        XCTAssertEqual(engine.events.map(\.kind), [.started, .completed, .started])
        XCTAssertEqual(stateObservedByCompletion, .running)

        clock.advance(by: 4)
        engine.refreshAfterWake()
        XCTAssertEqual(engine.displayedInterval, 6, accuracy: 0.001)
        engine.reset()
    }

    func testRepeatedCountdownSnapshotRestoresCurrentCycle() {
        let clock = TestClock()
        var preferences = UserPreferences()
        preferences.countdownDuration = 8
        preferences.countdownRepeats = true
        let engine = TimerEngine(preferences: preferences, now: { clock.date })

        XCTAssertTrue(engine.changeMode(to: .countdown))
        engine.start()
        clock.advance(by: 8)
        engine.refreshAfterWake()
        guard let snapshot = engine.makeSnapshot() else {
            return XCTFail("Expected repeated countdown snapshot")
        }
        engine.reset()

        clock.advance(by: 3)
        let restored = TimerEngine(preferences: preferences, now: { clock.date })
        restored.restore(snapshot)
        XCTAssertEqual(restored.state, .running)
        XCTAssertEqual(restored.displayedInterval, 5, accuracy: 0.001)
        restored.reset()
    }

    func testLapsCaptureCumulativeElapsedTime() {
        let clock = TestClock()
        let engine = TimerEngine(now: { clock.date })

        engine.start()
        clock.advance(by: 3)
        engine.addLap()
        clock.advance(by: 2)
        engine.addLap()

        XCTAssertEqual(engine.laps.map(\.order), [1, 2])
        XCTAssertEqual(engine.laps[0].elapsed, 3, accuracy: 0.001)
        XCTAssertEqual(engine.laps[1].elapsed, 5, accuracy: 0.001)
        engine.reset()
    }

    func testActiveModeChangeRequiresForce() {
        let clock = TestClock()
        let engine = TimerEngine(now: { clock.date })

        engine.start()
        clock.advance(by: 2)
        XCTAssertFalse(engine.changeMode(to: .countdown))
        XCTAssertEqual(engine.mode, .stopwatch)
        XCTAssertTrue(engine.changeMode(to: .countdown, force: true))
        XCTAssertEqual(engine.mode, .countdown)
        XCTAssertEqual(engine.state, .idle)
    }

    func testPomodoroAdvancesFromFocusToBreakAndNextCycle() {
        let clock = TestClock()
        var preferences = UserPreferences()
        preferences.focusDuration = 10
        preferences.shortBreakDuration = 5
        preferences.longBreakDuration = 15
        preferences.cyclesBeforeLongBreak = 2
        let engine = TimerEngine(preferences: preferences, now: { clock.date })
        var finalizedSessions: [SessionDraft] = []
        engine.onSessionFinalized = { finalizedSessions.append($0) }

        XCTAssertTrue(engine.changeMode(to: .pomodoro))
        engine.start()
        clock.advance(by: 10)
        engine.refreshAfterWake()
        XCTAssertEqual(engine.state, .completed)
        XCTAssertEqual(finalizedSessions.count, 1)

        engine.start()
        XCTAssertEqual(engine.pomodoroPhase, .shortBreak)
        XCTAssertEqual(engine.displayedInterval, 5, accuracy: 0.001)
        clock.advance(by: 5)
        engine.refreshAfterWake()

        engine.start()
        XCTAssertEqual(engine.pomodoroPhase, .focus)
        XCTAssertEqual(engine.pomodoroCycle, 2)
        clock.advance(by: 10)
        engine.refreshAfterWake()
        XCTAssertEqual(finalizedSessions.count, 2)

        engine.start()
        XCTAssertEqual(engine.pomodoroPhase, .longBreak)
        XCTAssertEqual(engine.displayedInterval, 15, accuracy: 0.001)
        engine.reset()
    }

    func testSnapshotRestoresRunningElapsedTime() {
        let clock = TestClock()
        let source = TimerEngine(now: { clock.date })
        source.sessionName = "Deep work"
        source.start()
        clock.advance(by: 8)
        guard let snapshot = source.makeSnapshot() else {
            return XCTFail("Expected an active snapshot")
        }
        source.reset()

        clock.advance(by: 2)
        let restored = TimerEngine(now: { clock.date })
        restored.restore(snapshot)

        XCTAssertEqual(restored.state, .running)
        XCTAssertEqual(restored.sessionName, "Deep work")
        XCTAssertEqual(restored.displayedInterval, 10, accuracy: 0.001)
        restored.reset()
    }

    func testEventLogCapturesTimerTransitionsAndCanBeCleared() {
        let clock = TestClock()
        let engine = TimerEngine(now: { clock.date })

        engine.start()
        clock.advance(by: 4)
        engine.pause()
        engine.resume()
        clock.advance(by: 2)
        engine.stop()
        engine.reset()

        XCTAssertEqual(engine.events.map(\.kind), [.started, .paused, .resumed, .stopped, .reset])
        XCTAssertEqual(engine.events.map(\.interval), [0, 4, 4, 6, 0])

        engine.clearEvents()
        XCTAssertTrue(engine.events.isEmpty)
    }

    func testAppModelForwardsEngineAndSettingsChanges() throws {
        let container = try makeInMemoryContainer()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let engine = TimerEngine(preferences: settings.preferences)
        let model = AppModel(
            container: container,
            settings: settings,
            engine: engine,
            notificationService: NotificationSpy()
        )
        var changeCount = 0
        let cancellable = model.objectWillChange.sink { changeCount += 1 }

        engine.start()
        let afterEngineChange = changeCount
        settings.update { $0.theme = .minimal }

        XCTAssertGreaterThan(afterEngineChange, 0)
        XCTAssertGreaterThan(changeCount, afterEngineChange)
        withExtendedLifetime(cancellable) {}
        engine.reset()
    }

    func testSettingsStorePublishesUpdatedOpacity() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        var publishedOpacity: Double?
        let cancellable = settings.$preferences
            .dropFirst()
            .sink { publishedOpacity = $0.opacity }

        settings.update { $0.opacity = 0.6 }

        XCTAssertEqual(settings.preferences.opacity, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(publishedOpacity), 0.6, accuracy: 0.000_001)
        withExtendedLifetime(cancellable) {}
    }

    func testSettingsStorePersistsEssentialLayoutPreference() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        settings.update { $0.compactMode = true }

        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.preferences.compactMode)
    }

    func testOverlayHostingViewAcceptsFirstMouse() {
        let hostingView = FirstMouseHostingView(rootView: EmptyView())

        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))
    }

    func testCancellingNotificationWhileAuthorizationIsPendingPreventsScheduling() async {
        let center = NotificationCenterSpy()
        let service = NotificationService(center: center)
        service.scheduleCompletion(after: 30, title: "Done", body: "Finished")

        for _ in 0..<10 where !center.isWaitingForAuthorization {
            await Task.yield()
        }
        XCTAssertTrue(center.isWaitingForAuthorization)
        service.cancelCompletion()
        center.resolveAuthorization(true)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(center.added.isEmpty)
        XCTAssertGreaterThanOrEqual(center.removalCount, 2)
    }

    func testReplacingNotificationWaitsForCancelledSchedulingTask() async {
        let center = NotificationCenterSpy()
        center.status = .allowed
        center.pauseNextAdd = true
        let service = NotificationService(center: center)
        let first = CompletionNotificationRequest(interval: 30, title: "First", body: "Old")
        let second = CompletionNotificationRequest(interval: 60, title: "Second", body: "New")

        service.scheduleCompletion(after: first.interval, title: first.title, body: first.body)
        for _ in 0..<10 where !center.isWaitingToAdd {
            await Task.yield()
        }
        XCTAssertTrue(center.isWaitingToAdd)

        service.scheduleCompletion(after: second.interval, title: second.title, body: second.body)
        await Task.yield()
        XCTAssertTrue(center.added.isEmpty)

        center.resolveAdd()
        for _ in 0..<10 where center.added.count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(center.added, [first, second])
    }

    func testSessionRepositoryPersistsAndCascadeDeletesInMemory() throws {
        let container = try makeInMemoryContainer()
        let repository = SessionRepository(container: container)
        let draft = makeDraft(laps: [
            LapSnapshot(id: UUID(), order: 1, elapsed: 2, timestamp: Date())
        ])

        try repository.insert(draft)
        XCTAssertEqual(try repository.context.fetchCount(FetchDescriptor<SessionRecord>()), 1)
        XCTAssertEqual(try repository.context.fetchCount(FetchDescriptor<LapRecord>()), 1)

        let record = try XCTUnwrap(repository.context.fetch(FetchDescriptor<SessionRecord>()).first)
        try repository.delete(record)
        XCTAssertEqual(try repository.context.fetchCount(FetchDescriptor<SessionRecord>()), 0)
        XCTAssertEqual(try repository.context.fetchCount(FetchDescriptor<LapRecord>()), 0)
    }

    func testSessionRepositoryPropagatesSaveFailure() throws {
        let container = try makeInMemoryContainer()
        let repository = SessionRepository(container: container) { _ in throw TestError.saveFailed }

        XCTAssertThrowsError(try repository.insert(makeDraft())) { error in
            XCTAssertTrue(error is TestError)
        }
        XCTAssertEqual(try repository.context.fetchCount(FetchDescriptor<SessionRecord>()), 0)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([SessionRecord.self, LapRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func makeDraft(laps: [LapSnapshot] = []) -> SessionDraft {
        SessionDraft(
            name: "Test",
            mode: .stopwatch,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
            endedAt: Date(timeIntervalSinceReferenceDate: 20),
            activeDuration: 10,
            result: "stopped",
            pomodoroCycles: 0,
            laps: laps
        )
    }
}
