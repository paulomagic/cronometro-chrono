import Combine
import Foundation

@MainActor
final class TimerEngine: ObservableObject {
    typealias DateProvider = () -> Date

    @Published private(set) var mode: TimerMode = .stopwatch
    @Published private(set) var state: RunState = .idle
    @Published private(set) var displayedInterval: TimeInterval = 0
    @Published private(set) var pomodoroPhase: PomodoroPhase = .focus
    @Published private(set) var pomodoroCycle = 1
    @Published private(set) var laps: [LapSnapshot] = []
    @Published private(set) var events: [TimerEvent] = []
    @Published var sessionName = ""

    var onSnapshotChanged: ((ActiveSessionSnapshot?) -> Void)?
    var onSessionFinalized: ((SessionDraft) -> Void)?
    var onIntervalCompleted: ((TimerMode, PomodoroPhase?) -> Void)?

    private let now: DateProvider
    private var displayTimer: Timer?
    private var accumulated: TimeInterval = 0
    private var liveStartedAt: Date?
    private var sessionStartedAt: Date?
    private var countdownDuration: TimeInterval
    private var preferences: UserPreferences
    private var hudVisible = true

    init(preferences: UserPreferences = UserPreferences(), now: @escaping DateProvider = Date.init) {
        self.preferences = preferences
        self.now = now
        countdownDuration = preferences.countdownDuration
        updateDisplay(at: now())
    }

    deinit { displayTimer?.invalidate() }

    var isActive: Bool { state == .running || state == .paused }
    var canAddLap: Bool { mode == .stopwatch && state == .running }

    var phaseDuration: TimeInterval {
        switch mode {
        case .stopwatch: return 0
        case .countdown: return countdownDuration
        case .pomodoro:
            switch pomodoroPhase {
            case .focus: return preferences.focusDuration
            case .shortBreak: return preferences.shortBreakDuration
            case .longBreak: return preferences.longBreakDuration
            }
        }
    }

    var progress: Double {
        guard mode != .stopwatch, phaseDuration > 0 else { return 0 }
        return min(max(1 - displayedInterval / phaseDuration, 0), 1)
    }

    func applyPreferences(_ preferences: UserPreferences) {
        self.preferences = preferences
        if state == .idle && mode == .countdown {
            countdownDuration = preferences.countdownDuration
            updateDisplay(at: now())
        }
        restartDisplayTimerIfNeeded()
        persistSnapshot()
    }

    @discardableResult
    func changeMode(to newMode: TimerMode, force: Bool = false) -> Bool {
        guard newMode != mode else { return true }
        guard !isActive || force else { return false }
        if isActive { stop(result: "cancelled") }
        mode = newMode
        reset(clearName: false, logEvent: false)
        return true
    }

    func start() {
        let date = now()
        let previousState = state
        if state == .completed {
            if mode == .pomodoro { advancePomodoroPhase() }
            accumulated = 0
            laps = []
        }
        if state == .idle {
            accumulated = 0
            laps = []
            sessionStartedAt = date
            if mode == .countdown { countdownDuration = preferences.countdownDuration }
        }
        guard state == .idle || state == .paused || state == .completed else { return }
        state = .running
        liveStartedAt = date
        if sessionStartedAt == nil { sessionStartedAt = date }
        restartDisplayTimerIfNeeded()
        updateDisplay(at: date)
        recordEvent(previousState == .paused ? .resumed : .started, at: date)
        persistSnapshot()
    }

    func pause() {
        guard state == .running else { return }
        let date = now()
        accumulated = effectiveElapsed(at: date)
        liveStartedAt = nil
        state = .paused
        stopDisplayTimer()
        updateDisplay(at: date)
        recordEvent(.paused, at: date)
        persistSnapshot()
    }

    func resume() { start() }

    func toggleRunning() {
        switch state {
        case .running: pause()
        case .idle, .paused, .completed: start()
        }
    }

    func stop(result: String = "stopped") {
        guard state != .idle else { return }
        let date = now()
        if state == .running { accumulated = effectiveElapsed(at: date) }
        liveStartedAt = nil
        finalizeSession(at: date, result: result)
        state = .idle
        stopDisplayTimer()
        updateDisplay(at: date)
        recordEvent(.stopped, at: date)
        persistSnapshot()
    }

    func reset(clearName: Bool = true, logEvent: Bool = true) {
        stopDisplayTimer()
        state = .idle
        accumulated = 0
        liveStartedAt = nil
        sessionStartedAt = nil
        laps = []
        pomodoroPhase = .focus
        pomodoroCycle = 1
        countdownDuration = preferences.countdownDuration
        if clearName { sessionName = "" }
        let date = now()
        updateDisplay(at: date)
        if logEvent { recordEvent(.reset, at: date) }
        onSnapshotChanged?(nil)
    }

    func clearEvents() { events.removeAll() }

    func addLap() {
        guard canAddLap else { return }
        let date = now()
        let lap = LapSnapshot(id: UUID(), order: laps.count + 1, elapsed: effectiveElapsed(at: date), timestamp: date)
        laps.append(lap)
        persistSnapshot()
    }

    func setHUDVisible(_ visible: Bool) {
        hudVisible = visible
        restartDisplayTimerIfNeeded()
    }

    func restore(_ snapshot: ActiveSessionSnapshot) {
        mode = snapshot.mode
        state = snapshot.state
        accumulated = max(snapshot.accumulated, 0)
        liveStartedAt = snapshot.liveStartedAt
        sessionStartedAt = snapshot.sessionStartedAt
        countdownDuration = max(snapshot.countdownDuration, 1)
        pomodoroPhase = snapshot.pomodoroPhase
        pomodoroCycle = max(snapshot.pomodoroCycle, 1)
        sessionName = snapshot.sessionName
        laps = snapshot.laps
        updateDisplay(at: now())
        if state == .running { restartDisplayTimerIfNeeded() }
    }

    func refreshAfterWake() {
        updateDisplay(at: now())
        persistSnapshot()
    }

    func makeSnapshot() -> ActiveSessionSnapshot? {
        guard state != .idle else { return nil }
        return ActiveSessionSnapshot(
            mode: mode,
            state: state,
            accumulated: accumulated,
            liveStartedAt: liveStartedAt,
            sessionStartedAt: sessionStartedAt,
            countdownDuration: countdownDuration,
            pomodoroPhase: pomodoroPhase,
            pomodoroCycle: pomodoroCycle,
            sessionName: sessionName,
            laps: laps
        )
    }

    private func effectiveElapsed(at date: Date) -> TimeInterval {
        guard state == .running, let liveStartedAt else { return accumulated }
        return accumulated + max(date.timeIntervalSince(liveStartedAt), 0)
    }

    private func updateDisplay(at date: Date) {
        let elapsed = effectiveElapsed(at: date)
        if mode == .stopwatch {
            displayedInterval = elapsed
            return
        }
        let remaining = max(phaseDuration - elapsed, 0)
        displayedInterval = remaining
        if state == .running && remaining <= 0 { completeInterval(at: date) }
    }

    private func completeInterval(at date: Date) {
        accumulated = phaseDuration
        liveStartedAt = nil
        state = .completed
        stopDisplayTimer()
        if mode == .countdown || (mode == .pomodoro && pomodoroPhase == .focus) {
            finalizeSession(at: date, result: "completed")
        }
        recordEvent(.completed, at: date)
        onIntervalCompleted?(mode, mode == .pomodoro ? pomodoroPhase : nil)
        persistSnapshot()
    }

    private func advancePomodoroPhase() {
        switch pomodoroPhase {
        case .focus:
            pomodoroPhase = pomodoroCycle.isMultiple(of: max(preferences.cyclesBeforeLongBreak, 1)) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            pomodoroCycle += 1
            pomodoroPhase = .focus
            sessionStartedAt = nil
        }
    }

    private func finalizeSession(at date: Date, result: String) {
        guard let startedAt = sessionStartedAt else { return }
        if mode == .pomodoro && pomodoroPhase != .focus { return }
        let duration = mode == .stopwatch ? accumulated : min(accumulated, phaseDuration)
        guard duration > 0 else { return }
        onSessionFinalized?(SessionDraft(
            name: sessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mode: mode,
            startedAt: startedAt,
            endedAt: date,
            activeDuration: duration,
            result: result,
            pomodoroCycles: mode == .pomodoro ? pomodoroCycle : 0,
            laps: laps
        ))
        sessionStartedAt = nil
    }

    private func restartDisplayTimerIfNeeded() {
        stopDisplayTimer()
        guard state == .running else { return }
        let interval = hudVisible && (mode == .stopwatch && preferences.showMilliseconds) ? 1.0 / 30.0 : 0.25
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateDisplay(at: self?.now() ?? Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func recordEvent(_ kind: TimerEventKind, at date: Date) {
        events.append(TimerEvent(timestamp: date, kind: kind, interval: displayedInterval))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }

    private func persistSnapshot() { onSnapshotChanged?(makeSnapshot()) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
