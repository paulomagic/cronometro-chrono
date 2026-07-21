import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class SessionRepository {
    typealias SaveAction = @MainActor (ModelContext) throws -> Void

    let context: ModelContext
    private let saveAction: SaveAction

    init(
        container: ModelContainer,
        saveAction: @escaping SaveAction = { try $0.save() }
    ) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.saveAction = saveAction
    }

    func insert(_ draft: SessionDraft) throws {
        let record = SessionRecord(draft: draft)
        context.insert(record)
        do {
            try saveAction(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(_ record: SessionRecord) throws {
        context.delete(record)
        do {
            try saveAction(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteAll() throws {
        do {
            try context.delete(model: SessionRecord.self)
            try saveAction(context)
        } catch {
            context.rollback()
            throw error
        }
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

enum NotificationPermissionStatus {
    case allowed
    case notDetermined
    case denied
}

struct CompletionNotificationRequest: Equatable {
    let interval: TimeInterval
    let title: String
    let body: String
}

@MainActor
protocol UserNotificationCenterClient: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func permissionStatus() async -> NotificationPermissionStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: CompletionNotificationRequest) async throws
    func removeCompletionRequest()
}

@MainActor
final class SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter
    private let completionID = "chrono.active-completion"

    var delegate: UNUserNotificationCenterDelegate? {
        get { center.delegate }
        set { center.delegate = newValue }
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func permissionStatus() async -> NotificationPermissionStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .allowed
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func add(_ request: CompletionNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(request.interval, 1), repeats: false)
        try await center.add(UNNotificationRequest(identifier: completionID, content: content, trigger: trigger))
    }

    func removeCompletionRequest() {
        center.removePendingNotificationRequests(withIdentifiers: [completionID])
    }
}

@MainActor
protocol CompletionNotificationServing: AnyObject {
    func scheduleCompletion(after interval: TimeInterval, title: String, body: String)
    func cancelCompletion()
    func playCompletionSound()
}

@MainActor
final class NotificationService: NSObject, CompletionNotificationServing, UNUserNotificationCenterDelegate {
    private let center: any UserNotificationCenterClient
    private var schedulingTask: Task<Void, Never>?

    init(center: any UserNotificationCenterClient = SystemUserNotificationCenterClient()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestPermissionIfNeeded() async -> Bool {
        switch await center.permissionStatus() {
        case .allowed: return true
        case .notDetermined:
            return (try? await center.requestAuthorization()) ?? false
        case .denied: return false
        }
    }

    func scheduleCompletion(after interval: TimeInterval, title: String, body: String) {
        let previousTask = schedulingTask
        previousTask?.cancel()
        center.removeCompletionRequest()
        guard interval > 0 else { return }
        let request = CompletionNotificationRequest(interval: interval, title: title, body: body)
        schedulingTask = Task { [weak self] in
            await previousTask?.value
            guard let self, await requestPermissionIfNeeded(), !Task.isCancelled else { return }
            do {
                try await center.add(request)
                if Task.isCancelled { center.removeCompletionRequest() }
            } catch is CancellationError {
                center.removeCompletionRequest()
            } catch {
                // A notification is supplemental; scheduling failure must not stop the timer.
            }
        }
    }

    func cancelCompletion() {
        schedulingTask?.cancel()
        schedulingTask = nil
        center.removeCompletionRequest()
    }

    func playCompletionSound() {
        if NSSound(named: "Glass")?.play() != true { NSSound.beep() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
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
protocol GlobalHotKeyRegistration: AnyObject {
    func cancel()
}

@MainActor
protocol GlobalHotKeyBackend: AnyObject {
    func install(handler: @escaping (GlobalHotKeyService.Action) -> Void) throws
    func register(
        _ action: GlobalHotKeyService.Action,
        shortcut: ShortcutDefinition
    ) throws -> any GlobalHotKeyRegistration
}

enum GlobalHotKeyBackendError: Error, Equatable {
    case handlerInstallation(OSStatus)
    case exclusiveConflict
    case registration(OSStatus)
}

@MainActor
private final class SystemGlobalHotKeyRegistration: GlobalHotKeyRegistration {
    private var reference: EventHotKeyRef?
    private let cancellation: (EventHotKeyRef) -> Void

    init(reference: EventHotKeyRef, cancellation: @escaping (EventHotKeyRef) -> Void) {
        self.reference = reference
        self.cancellation = cancellation
    }

    func cancel() {
        guard let reference else { return }
        self.reference = nil
        cancellation(reference)
    }

    isolated deinit {
        if let reference { UnregisterEventHotKey(reference) }
    }
}

@MainActor
final class SystemGlobalHotKeyBackend: GlobalHotKeyBackend {
    private var eventHandler: EventHandlerRef?
    private var handler: ((GlobalHotKeyService.Action) -> Void)?
    private var routes: [UInt32: GlobalHotKeyService.Action] = [:]
    private var nextIdentifier: UInt32 = 1

    func install(handler: @escaping (GlobalHotKeyService.Action) -> Void) throws {
        self.handler = handler
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
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
                guard status == noErr else { return status }
                let backend = Unmanaged<SystemGlobalHotKeyBackend>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    guard let action = backend.routes[identifier.id] else { return }
                    backend.handler?(action)
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw GlobalHotKeyBackendError.handlerInstallation(status) }
    }

    func register(
        _ action: GlobalHotKeyService.Action,
        shortcut: ShortcutDefinition
    ) throws -> any GlobalHotKeyRegistration {
        let identifierValue = nextIdentifier
        nextIdentifier &+= 1
        let identifier = EventHotKeyID(signature: OSType(0x4348524F), id: identifierValue) // CHRO
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
        // Carbon reports exclusive conflicts, but another process with a non-exclusive
        // registration can still coexist. System/app conflicts also need manual validation.
        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr { throw GlobalHotKeyBackendError.exclusiveConflict }
            throw GlobalHotKeyBackendError.registration(status)
        }
        routes[identifierValue] = action
        return SystemGlobalHotKeyRegistration(reference: reference) { [weak self] reference in
            UnregisterEventHotKey(reference)
            self?.routes[identifierValue] = nil
        }
    }

    isolated deinit {
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

enum ShortcutRegistrationError: Error, Equatable {
    case duplicate(GlobalHotKeyService.Action)
    case exclusiveConflict
    case handlerInstallation(OSStatus)
    case registration(OSStatus)
}

@MainActor
final class GlobalHotKeyService {
    enum Action: UInt32, CaseIterable, Hashable {
        case showHide = 1
        case clickThrough = 2
        case quickTimer = 3
    }

    private let backend: any GlobalHotKeyBackend
    private var registrations: [Action: any GlobalHotKeyRegistration] = [:]
    private var handlers: [Action: () -> Void] = [:]
    private(set) var errors: [Action: ShortcutRegistrationError] = [:]
    private var installed = false

    init(backend: any GlobalHotKeyBackend = SystemGlobalHotKeyBackend()) {
        self.backend = backend
    }

    func registerInitial(_ action: Action, shortcut: ShortcutDefinition, handler: @escaping () -> Void) {
        handlers[action] = handler
        do {
            try installIfNeeded()
            let registration = try backend.register(action, shortcut: shortcut)
            registrations[action]?.cancel()
            registrations[action] = registration
            errors[action] = nil
        } catch let error as ShortcutRegistrationError {
            errors[action] = error
        } catch {
            errors[action] = map(error)
        }
    }

    func replace(
        _ action: Action,
        shortcut: ShortcutDefinition,
        persist: () throws -> Void
    ) throws {
        do {
            try installIfNeeded()
            let candidate = try backend.register(action, shortcut: shortcut)
            do { try persist() }
            catch {
                candidate.cancel()
                throw error
            }
            let previous = registrations.updateValue(candidate, forKey: action)
            previous?.cancel()
            errors[action] = nil
        } catch let error as ShortcutRegistrationError {
            errors[action] = error
            throw error
        } catch {
            let mapped = map(error)
            errors[action] = mapped
            throw mapped
        }
    }

    var registrationCount: Int { registrations.count }

    private func installIfNeeded() throws {
        guard !installed else { return }
        do {
            try backend.install { [weak self] action in self?.handlers[action]?() }
            installed = true
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> ShortcutRegistrationError {
        guard let backendError = error as? GlobalHotKeyBackendError else { return .registration(OSStatus(paramErr)) }
        switch backendError {
        case .handlerInstallation(let status): return .handlerInstallation(status)
        case .exclusiveConflict: return .exclusiveConflict
        case .registration(let status): return .registration(status)
        }
    }
}
