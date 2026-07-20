import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    static let essentialSize = NSSize(width: 352, height: 92)

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

    isolated deinit {
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
        panel.contentView = FirstMouseHostingView(rootView: OverlayView().environmentObject(appModel))
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

    func applyPreferences(_ preferences: UserPreferences? = nil) {
        let preferences = preferences ?? appModel.settings.preferences
        let compact = preferences.compactMode
        let fullHeight: CGFloat = appModel.eventLogExpanded ? 620 : 445
        let size = compact ? Self.essentialSize : NSSize(width: 420, height: fullHeight)
        resizePanel(to: size)
        panel.alphaValue = preferences.opacity
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

    private func resizePanel(to contentSize: NSSize) {
        let currentFrame = panel.frame
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let resizedFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        panel.setFrame(resizedFrame, display: true, animate: false)
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
