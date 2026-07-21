import XCTest
@testable import ChronoHUD

@MainActor
final class TimerEngineQuickTimerTests: XCTestCase {
    func testStartCountdownValidatesBeforeMutation() throws {
        let engine = TimerEngine()
        for duration in [0, -1, .infinity, .nan, 86_401] {
            XCTAssertThrowsError(try engine.startCountdown(duration: duration, repeats: false)) {
                XCTAssertEqual($0 as? TimerEngineError, .invalidDuration)
            }
            XCTAssertEqual(engine.state, .idle)
            XCTAssertEqual(engine.mode, .stopwatch)
        }
    }

    func testStandaloneCountdownStartsFromIdleAndCompletedWithoutChangingPreferences() throws {
        let clock = QuickTimerClock()
        var preferences = UserPreferences()
        preferences.countdownDuration = 600
        preferences.countdownRepeats = true
        let engine = TimerEngine(preferences: preferences, now: { clock.date })

        try engine.startCountdown(duration: 10, repeats: false)
        XCTAssertEqual(engine.mode, .countdown)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.displayedInterval, 10)
        XCTAssertEqual(engine.countdownRepeatsOverride, false)
        clock.advance(10)
        engine.refreshAfterWake()
        XCTAssertEqual(engine.state, .completed)

        try engine.startCountdown(duration: 20, repeats: false)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.displayedInterval, 20)
        XCTAssertEqual(engine.countdownRepeatsOverride, false)
        engine.reset()
    }

    func testStartRejectsActiveSessionWithoutMutation() throws {
        let clock = QuickTimerClock()
        let engine = TimerEngine(now: { clock.date })
        engine.start()
        clock.advance(4)
        let before = engine.makeSnapshot()
        XCTAssertThrowsError(try engine.startCountdown(duration: 30, repeats: false)) {
            XCTAssertEqual($0 as? TimerEngineError, .activeSession)
        }
        XCTAssertEqual(engine.makeSnapshot(), before)
        engine.reset()
    }

    func testReplaceRunningAndPausedSessionsCreatesReplacedHistory() throws {
        for pauseFirst in [false, true] {
            let clock = QuickTimerClock()
            let engine = TimerEngine(now: { clock.date })
            var drafts: [SessionDraft] = []
            engine.onSessionFinalized = { drafts.append($0) }
            engine.start()
            clock.advance(7)
            if pauseFirst { engine.pause() }

            try engine.replaceActiveSessionWithCountdown(duration: 45, repeats: false)

            XCTAssertEqual(drafts.count, 1)
            XCTAssertEqual(drafts[0].result, "replaced")
            XCTAssertEqual(drafts[0].activeDuration, 7, accuracy: 0.001)
            XCTAssertEqual(engine.state, .running)
            XCTAssertEqual(engine.mode, .countdown)
            XCTAssertEqual(engine.displayedInterval, 45)
            XCTAssertEqual(engine.countdownRepeatsOverride, false)
            engine.reset()
        }
    }

    func testReplacementPublishesOnlyTheFinalCountdownSnapshot() throws {
        let clock = QuickTimerClock()
        let engine = TimerEngine(now: { clock.date })
        engine.start()
        clock.advance(2)
        var snapshots: [ActiveSessionSnapshot?] = []
        engine.onSnapshotChanged = { snapshots.append($0) }

        try engine.replaceActiveSessionWithCountdown(duration: 45, repeats: false)

        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots[0])
        XCTAssertEqual(snapshot.mode, .countdown)
        XCTAssertEqual(snapshot.state, .running)
        XCTAssertEqual(snapshot.countdownDuration, 45)
        XCTAssertEqual(snapshot.countdownRepeatsOverride, false)
        engine.reset()
    }

    func testZeroDurationReplacementDoesNotCreateHistory() throws {
        let clock = QuickTimerClock()
        let engine = TimerEngine(now: { clock.date })
        var drafts: [SessionDraft] = []
        engine.onSessionFinalized = { drafts.append($0) }
        engine.start()
        try engine.replaceActiveSessionWithCountdown(duration: 30, repeats: false)
        XCTAssertTrue(drafts.isEmpty)
        engine.reset()
    }

    func testOverrideSurvivesPreferencesPauseRestoreAndManualRestartButResetClearsIt() throws {
        let clock = QuickTimerClock()
        var preferences = UserPreferences()
        preferences.countdownRepeats = true
        let source = TimerEngine(preferences: preferences, now: { clock.date })
        try source.startCountdown(duration: 5, repeats: false)
        source.pause()
        preferences.countdownRepeats = false
        source.applyPreferences(preferences)
        source.resume()
        guard let snapshot = source.makeSnapshot() else { return XCTFail("missing snapshot") }
        source.reset()

        let restored = TimerEngine(preferences: preferences, now: { clock.date })
        restored.restore(snapshot)
        XCTAssertEqual(restored.countdownRepeatsOverride, false)
        clock.advance(5)
        restored.refreshAfterWake()
        XCTAssertEqual(restored.state, .completed)
        restored.start()
        XCTAssertEqual(restored.countdownRepeatsOverride, false)
        restored.reset()
        XCTAssertNil(restored.countdownRepeatsOverride)
    }

    func testLegacySnapshotDecodesNilOverride() throws {
        let json = #"{"mode":"countdown","state":"paused","accumulated":1,"sessionStartedAt":0,"countdownDuration":30,"pomodoroPhase":"focus","pomodoroCycle":1,"sessionName":"","laps":[]}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(ActiveSessionSnapshot.self, from: json)
        XCTAssertNil(snapshot.countdownRepeatsOverride)
    }

    func testLegacyPreferencesDecodeNilQuickTimerShortcutAndUseDefault() throws {
        let current = UserPreferences()
        let data = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "quickTimerShortcut")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyData)
        XCTAssertNil(decoded.quickTimerShortcut)
        XCTAssertEqual(decoded.effectiveQuickTimerShortcut, .quickTimer)
    }

    func testTrueOverrideRepeatsDespiteDisabledGlobalPreference() throws {
        let clock = QuickTimerClock()
        var preferences = UserPreferences()
        preferences.countdownRepeats = false
        let engine = TimerEngine(preferences: preferences, now: { clock.date })
        try engine.startCountdown(duration: 3, repeats: true)
        clock.advance(3)
        engine.refreshAfterWake()
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.countdownRepeatsOverride, true)
        XCTAssertEqual(engine.displayedInterval, 3)
        engine.reset()
    }
}

private final class QuickTimerClock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000)
    func advance(_ interval: TimeInterval) { date = date.addingTimeInterval(interval) }
}
