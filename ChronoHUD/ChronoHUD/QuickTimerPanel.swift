import AppKit
import Combine
import SwiftUI

final class QuickTimerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum QuickTimerDismissReason {
    case started
    case cancelled
    case focusLost
}

struct QuickTimerKeyEvent: Equatable {
    enum Action: Equatable { case submit(optionPressed: Bool), escape }

    static func action(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Action? {
        guard !isRepeat else { return nil }
        if keyCode == 53 { return .escape }
        guard keyCode == 36 || keyCode == 76 else { return nil }
        return .submit(optionPressed: modifiers.contains(.option))
    }
}

@MainActor
final class QuickTimerPanelController: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 520
    private static let baseHeight: CGFloat = 142
    private static let expandedHeight: CGFloat = 190

    private let appModel: AppModel
    private let panel: QuickTimerPanel
    private var model = QuickTimerPanelModel()
    private var stateCancellable: AnyCancellable?
    private var keyEventMonitor: Any?
    private let focusRequests = CurrentValueSubject<UInt, Never>(0)
    private weak var previousWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var isDismissing = false
    private var hasPresentationCapture = false

    init(appModel: AppModel) {
        self.appModel = appModel
        panel = QuickTimerPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.baseHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func present(at target: QuickTimerPlacementTarget) {
        isDismissing = false
        if !panel.isVisible || !hasPresentationCapture {
            previousApplication = NSWorkspace.shared.frontmostApplication
            previousWindow = NSApp.keyWindow
            hasPresentationCapture = true
        }

        model = QuickTimerPanelModel()
        installContent()
        resize(for: model.phase)
        position(using: target)
        observeSession()
        installKeyEventMonitor()
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusRequests.send(focusRequests.value &+ 1)
    }

    func dismiss(reason: QuickTimerDismissReason) {
        guard !isDismissing, panel.isVisible else { return }
        isDismissing = true
        stateCancellable = nil
        removeKeyEventMonitor()
        panel.orderOut(nil)
        if reason != .focusLost { restorePreviousContext() }
        previousApplication = nil
        previousWindow = nil
        hasPresentationCapture = false
        isDismissing = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible, !isDismissing else { return }
        dismiss(reason: .focusLost)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = false
    }

    private func installContent() {
        let root = QuickTimerPanelView(
            model: model,
            sessionIsActive: { [weak appModel] in appModel?.engine.isActive ?? false },
            focusRequests: focusRequests.eraseToAnyPublisher(),
            phaseChanged: { [weak self] phase in self?.resize(for: phase) }
        )
        .id(UUID())
        panel.contentView = NSHostingView(rootView: root)
    }

    private func submit(optionPressed: Bool) {
        do {
            let started = try model.submit(
                optionPressed: optionPressed,
                sessionIsActive: appModel.engine.isActive,
                validationFeedback: { NSSound.beep() },
                action: appModel.submitQuickTimer
            )
            if started { dismiss(reason: .started) }
        } catch {
            appModel.showError(error.localizedDescription)
        }
    }

    private func handleEscape() {
        if model.escape() { dismiss(reason: .cancelled) }
    }

    private func handleKeyAction(_ action: QuickTimerKeyEvent.Action) {
        switch action {
        case .submit(let optionPressed): submit(optionPressed: optionPressed)
        case .escape: handleEscape()
        }
    }

    private func installKeyEventMonitor() {
        removeKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isVisible, panel.isKeyWindow,
                  let action = QuickTimerKeyEvent.action(
                      keyCode: event.keyCode,
                      modifiers: event.modifierFlags,
                      isRepeat: event.isARepeat
                  ) else { return event }
            handleKeyAction(action)
            return nil
        }
    }

    private func removeKeyEventMonitor() {
        guard let keyEventMonitor else { return }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }

    private func observeSession() {
        stateCancellable = appModel.engine.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                model.sessionActivityChanged(isActive: state == .running || state == .paused)
            }
    }

    private func resize(for phase: QuickTimerPanelPhase) {
        let height: CGFloat
        switch phase {
        case .entry(let error): height = error == nil ? Self.baseHeight : Self.expandedHeight
        case .confirmation: height = Self.expandedHeight
        }
        let oldFrame = panel.frame
        panel.setFrame(
            NSRect(x: oldFrame.minX, y: oldFrame.maxY - height, width: Self.width, height: height),
            display: true,
            animate: false
        )
    }

    private func position(using target: QuickTimerPlacementTarget) {
        let visible = target.visibleFrame
        var origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + visible.height * 0.68 - panel.frame.height / 2
        )
        origin.x = min(max(origin.x, visible.minX), max(visible.maxX - panel.frame.width, visible.minX))
        origin.y = min(max(origin.y, visible.minY), max(visible.maxY - panel.frame.height, visible.minY))
        panel.setFrameOrigin(origin)
    }

    private func restorePreviousContext() {
        if let previousWindow, previousWindow.isVisible {
            previousWindow.makeKeyAndOrderFront(nil)
            return
        }
        guard let previousApplication, !previousApplication.isTerminated,
              previousApplication != NSRunningApplication.current else { return }
        previousApplication.activate(options: [])
    }
}

private struct QuickTimerPanelView: View {
    @Bindable var model: QuickTimerPanelModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var fieldFocused: Bool

    let sessionIsActive: () -> Bool
    let focusRequests: AnyPublisher<UInt, Never>
    let phaseChanged: (QuickTimerPanelPhase) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("quickTimer.title", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text("quickTimer.example")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("quickTimer.placeholder", text: $model.input)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .focused($fieldFocused)
                .accessibilityLabel("quickTimer.field.label")
                .accessibilityHint("quickTimer.field.hint")

            message
        }
        .padding(18)
        .frame(width: 520)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                QuickTimerVisualEffect(material: .hudWindow, blendingMode: .behindWindow)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorSchemeContrast == .increased ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
        }
        .clipShape(.rect(cornerRadius: 14))
        .defaultFocus($fieldFocused, true)
        .onReceive(focusRequests) { _ in
            fieldFocused = true
        }
        .onChange(of: model.phase) { _, phase in
            phaseChanged(phase)
            if case .entry = phase { fieldFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("quickTimer.context")
    }

    @ViewBuilder
    private var message: some View {
        switch model.phase {
        case .entry(let error):
            if let error {
                Text(errorMessage(error))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(errorMessage(error))
            } else if sessionIsActive() {
                Text("quickTimer.activeSession")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .confirmation(let duration, let origin):
            VStack(alignment: .leading, spacing: 4) {
                Text(origin == .sessionBecameActive ? "quickTimer.confirm.race" : "quickTimer.confirm.active")
                    .font(.caption)
                Text(formatInterval(duration, milliseconds: false))
                    .font(.caption.monospacedDigit().bold())
                Text("quickTimer.confirm.instruction")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorMessage(_ error: QuickTimerParseError) -> LocalizedStringKey {
        switch error {
        case .empty: "quickTimer.error.empty"
        case .invalidFormat: "quickTimer.error.invalid"
        case .outOfRange: "quickTimer.error.range"
        }
    }
}

private struct QuickTimerVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
