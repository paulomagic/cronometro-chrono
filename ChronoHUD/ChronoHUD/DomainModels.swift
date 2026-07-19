import Foundation
import SwiftData

enum TimerMode: String, CaseIterable, Codable, Identifiable {
    case stopwatch
    case countdown
    case pomodoro

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .stopwatch: "mode.stopwatch"
        case .countdown: "mode.countdown"
        case .pomodoro: "mode.pomodoro"
        }
    }
}

enum RunState: String, Codable {
    case idle
    case running
    case paused
    case completed

    var localizedTitle: String {
        switch self {
        case .idle: String(localized: "state.idle")
        case .running: String(localized: "state.running")
        case .paused: String(localized: "state.paused")
        case .completed: String(localized: "state.completed")
        }
    }

    var localizedActionTitle: String {
        switch self {
        case .running: String(localized: "action.pause")
        case .paused: String(localized: "action.resume")
        case .idle, .completed: String(localized: "action.start")
        }
    }
}

enum TimerEventKind: Equatable {
    case started
    case resumed
    case paused
    case stopped
    case reset
    case completed

    var localizedTitle: String {
        switch self {
        case .started: String(localized: "event.started")
        case .resumed: String(localized: "event.resumed")
        case .paused: String(localized: "event.paused")
        case .stopped: String(localized: "event.stopped")
        case .reset: String(localized: "event.reset")
        case .completed: String(localized: "event.completed")
        }
    }
}

struct TimerEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: TimerEventKind
    let interval: TimeInterval
}

enum PomodoroPhase: String, Codable {
    case focus
    case shortBreak
    case longBreak

    var titleKey: String {
        switch self {
        case .focus: "phase.focus"
        case .shortBreak: "phase.shortBreak"
        case .longBreak: "phase.longBreak"
        }
    }
}

enum HUDTheme: String, CaseIterable, Codable, Identifiable {
    case premium
    case minimal
    var id: String { rawValue }
}

enum AccentChoice: String, CaseIterable, Codable, Identifiable {
    case cyan, green, amber, white
    var id: String { rawValue }
}

struct LapSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let order: Int
    let elapsed: TimeInterval
    let timestamp: Date
}

struct ActiveSessionSnapshot: Codable, Equatable {
    var mode: TimerMode
    var state: RunState
    var accumulated: TimeInterval
    var liveStartedAt: Date?
    var sessionStartedAt: Date?
    var countdownDuration: TimeInterval
    var pomodoroPhase: PomodoroPhase
    var pomodoroCycle: Int
    var sessionName: String
    var laps: [LapSnapshot]
}

struct SessionDraft {
    var id = UUID()
    var name: String?
    var mode: TimerMode
    var startedAt: Date
    var endedAt: Date
    var activeDuration: TimeInterval
    var result: String
    var pomodoroCycles: Int
    var laps: [LapSnapshot]
}

@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var name: String?
    var modeRaw: String
    var startedAt: Date
    var endedAt: Date
    var activeDuration: TimeInterval
    var result: String
    var pomodoroCycles: Int
    @Relationship(deleteRule: .cascade) var laps: [LapRecord]

    init(draft: SessionDraft) {
        id = draft.id
        name = draft.name
        modeRaw = draft.mode.rawValue
        startedAt = draft.startedAt
        endedAt = draft.endedAt
        activeDuration = draft.activeDuration
        result = draft.result
        pomodoroCycles = draft.pomodoroCycles
        laps = draft.laps.map { LapRecord(snapshot: $0) }
    }

    var mode: TimerMode { TimerMode(rawValue: modeRaw) ?? .stopwatch }
}

@Model
final class LapRecord {
    @Attribute(.unique) var id: UUID
    var order: Int
    var elapsed: TimeInterval
    var timestamp: Date

    init(snapshot: LapSnapshot) {
        id = snapshot.id
        order = snapshot.order
        elapsed = snapshot.elapsed
        timestamp = snapshot.timestamp
    }
}

struct ShortcutDefinition: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let showHide = ShortcutDefinition(keyCode: 8, modifiers: 0x0100 | 0x0200) // C, cmd+shift
    static let clickThrough = ShortcutDefinition(keyCode: 17, modifiers: 0x0100 | 0x0200) // T, cmd+shift
}

struct UserPreferences: Codable, Equatable {
    var countdownDuration: TimeInterval = 25 * 60
    var countdownRepeats = false
    var focusDuration: TimeInterval = 25 * 60
    var shortBreakDuration: TimeInterval = 5 * 60
    var longBreakDuration: TimeInterval = 15 * 60
    var cyclesBeforeLongBreak = 4
    var soundEnabled = true
    var notificationsEnabled = true
    var showMilliseconds = true
    var opacity = 0.96
    var compactMode = false
    var theme: HUDTheme = .premium
    var accent: AccentChoice = .cyan
    var launchAtLogin = false
    var showHideShortcut = ShortcutDefinition.showHide
    var clickThroughShortcut = ShortcutDefinition.clickThrough
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: UserPreferences {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "chrono.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = UserPreferences()
        }
    }

    func update(_ change: (inout UserPreferences) -> Void) {
        var copy = preferences
        change(&copy)
        preferences = copy
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
