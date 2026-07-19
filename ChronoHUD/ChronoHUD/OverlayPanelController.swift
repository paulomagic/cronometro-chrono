import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private let appModel: AppModel
    private let panel: OverlayPanel
    private let defaults: UserDefaults
    private var screenObserver: NSObjectProtocol?

    init(appModel: AppModel, defaults: UserDefaults = .standard) {
        self.appModel = appModel
        self.defaults = defaults
        panel = OverlayPanel(
            contentRect: NSRect(x: 40, y: 40, width: 380, height: 310),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(appModel))
        restorePosition()
        applyPreferences()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.keepOnScreen() } }
    }

    func show() {
        panel.orderFrontRegardless()
        appModel.hudVisible = true
        appModel.engine.setHUDVisible(true)
    }

    func hide() {
        savePosition()
        panel.orderOut(nil)
        appModel.hudVisible = false
        appModel.engine.setHUDVisible(false)
    }

    func toggleVisibility() { panel.isVisible ? hide() : show() }

    func setClickThrough(_ enabled: Bool) {
        panel.ignoresMouseEvents = enabled
    }

    func setPinned(_ pinned: Bool) {
        panel.level = pinned ? .floating : .normal
    }

    func applyPreferences() {
        let compact = appModel.settings.preferences.compactMode
        let fullHeight: CGFloat = appModel.eventLogExpanded ? 620 : 445
        let size = compact ? NSSize(width: 280, height: 86) : NSSize(width: 420, height: fullHeight)
        panel.setContentSize(size)
        panel.alphaValue = appModel.settings.preferences.opacity
        keepOnScreen()
    }

    func windowDidMove(_ notification: Notification) { savePosition() }
    func windowDidEndLiveResize(_ notification: Notification) { savePosition() }

    private func savePosition() {
        guard let screen = panel.screen else { return }
        defaults.set(screen.localizedName, forKey: "chrono.overlay.last-screen")
        defaults.set(NSStringFromRect(panel.frame), forKey: "chrono.overlay.frame.\(screen.localizedName)")
    }

    private func restorePosition() {
        let preferredName = defaults.string(forKey: "chrono.overlay.last-screen")
        let screen = NSScreen.screens.first(where: { $0.localizedName == preferredName }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        if let value = defaults.string(forKey: "chrono.overlay.frame.\(screen.localizedName)") {
            panel.setFrame(NSRectFromString(value), display: false)
        } else {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 32, y: visible.maxY - panel.frame.height - 32))
        }
        keepOnScreen()
    }

    private func keepOnScreen() {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.maxX - frame.width, visible.minX))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.maxY - frame.height, visible.minY))
        panel.setFrame(frame, display: true)
    }
}
