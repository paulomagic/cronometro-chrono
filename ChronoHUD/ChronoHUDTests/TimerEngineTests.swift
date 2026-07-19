import XCTest
@testable import ChronoHUD

@MainActor
final class TimerEngineTests: XCTestCase {
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
}
