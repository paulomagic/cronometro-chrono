import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class SessionRepository {
    let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = true
    }

    func insert(_ draft: SessionDraft) {
        context.insert(SessionRecord(draft: draft))
        try? context.save()
    }

    func delete(_ record: SessionRecord) {
        context.delete(record)
        try? context.save()
    }

    func deleteAll() throws {
        try context.delete(model: SessionRecord.self)
        try context.save()
    }
}

final class SnapshotStore {
    private let defaults: UserDefaults
    private let key = "chrono.active-session.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func save(_ snapshot: ActiveSessionSnapshot?) {
        guard let snapshot else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }

    func load() -> ActiveSessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data) }
        catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let completionID = "chrono.active-completion"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    func scheduleCompletion(after interval: TimeInterval, title: String, body: String, sound: Bool) async {
        cancelCompletion()
        guard interval > 0, await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: completionID, content: content, trigger: trigger))
    }

    func cancelCompletion() { center.removePendingNotificationRequests(withIdentifiers: [completionID]) }

    func playCompletionSound() {
        if NSSound(named: "Glass")?.play() != true { NSSound.beep() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

enum ExportError: LocalizedError {
    case encoding
    var errorDescription: String? { String(localized: "export.error.encoding") }
}

@MainActor
enum ExportService {
    static func exportCSV(_ sessions: [SessionRecord]) throws {
        var rows = ["id,name,mode,started_at,ended_at,duration_seconds,result,pomodoro_cycles"]
        let iso = ISO8601DateFormatter()
        for session in sessions {
            rows.append([
                session.id.uuidString,
                session.name ?? "",
                session.modeRaw,
                iso.string(from: session.startedAt),
                iso.string(from: session.endedAt),
                String(format: "%.3f", session.activeDuration),
                session.result,
                String(session.pomodoroCycles)
            ].map(csvEscape).joined(separator: ","))
        }
        try save(Data(rows.joined(separator: "\n").utf8), suggestedName: "chrono-history.csv", type: "csv")
    }

    static func exportJSON(_ sessions: [SessionRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let records = sessions.map { session in
            ExportedSession(
                id: session.id,
                name: session.name,
                mode: session.modeRaw,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                durationSeconds: session.activeDuration,
                result: session.result,
                pomodoroCycles: session.pomodoroCycles,
                laps: session.laps.map { ExportedLap(order: $0.order, elapsedSeconds: $0.elapsed, timestamp: $0.timestamp) }
            )
        }
        let document = ExportDocument(formatVersion: 1, exportedAt: Date(), sessions: records)
        try save(try encoder.encode(document), suggestedName: "chrono-history.json", type: "json")
    }

    static func exportEventLog(_ events: [TimerEvent]) throws {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm:ss"
        var lines = [String(localized: "event.log.export.header"), String(repeating: "=", count: 32), ""]
        for event in events {
            lines.append("[\(time.string(from: event.timestamp))] \(event.kind.localizedTitle) @ \(formatInterval(event.interval, milliseconds: true))")
        }
        try save(
            Data(lines.joined(separator: "\n").utf8),
            suggestedName: "chrono-log-\(day.string(from: Date())).txt",
            type: "txt"
        )
    }

    static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func save(_ data: Data, suggestedName: String, type: String) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        switch type {
        case "csv": panel.allowedContentTypes = [.commaSeparatedText]
        case "txt": panel.allowedContentTypes = [.plainText]
        default: panel.allowedContentTypes = [.json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }
}

private struct ExportDocument: Encodable {
    let formatVersion: Int
    let exportedAt: Date
    let sessions: [ExportedSession]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
        case sessions
    }
}

private struct ExportedSession: Encodable {
    let id: UUID
    let name: String?
    let mode: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let result: String
    let pomodoroCycles: Int
    let laps: [ExportedLap]
}

private struct ExportedLap: Encodable {
    let order: Int
    let elapsedSeconds: TimeInterval
    let timestamp: Date
}

@MainActor
enum LoginItemService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class GlobalHotKeyService {
    enum Action: UInt32 { case showHide = 1, clickThrough = 2 }

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private var actions: [Action: () -> Void] = [:]

    deinit {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func install() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, let action = Action(rawValue: identifier.id) else { return status }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in service.actions[action]?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func register(_ action: Action, shortcut: ShortcutDefinition, handler: @escaping () -> Void) -> OSStatus {
        install()
        if let existing = hotKeys[action] { UnregisterEventHotKey(existing); hotKeys[action] = nil }
        actions[action] = handler
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x4348524F), id: action.rawValue) // CHRO
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { hotKeys[action] = reference }
        return status
    }
}
