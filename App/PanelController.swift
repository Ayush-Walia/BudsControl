import AppKit
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Floating, Control Center-style panel anchored under the top-right of the menu bar.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private lazy var panel: KeyablePanel = makePanel()
    private var clickMonitor: Any?

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private var shownAt = Date.distantPast

    /// Delay lets Control Center finish dismissing; otherwise its focus change closes the panel instantly.
    func show(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.present() }
    }

    private func present() {
        BudsConnection.shared.refresh()
        position()
        shownAt = Date()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.hideIfSettled() }
            }
        }
    }

    private func hideIfSettled() {
        guard Date().timeIntervalSince(shownAt) > 0.5 else { return }
        hide()
    }

    func hide() {
        panel.orderOut(nil)
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hideIfSettled()
    }

    private func makePanel() -> KeyablePanel {
        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let host = NSHostingView(rootView: PanelView { mode in BudsConnection.shared.setMode(mode) })
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        p.contentView = blur
        p.setContentSize(host.fittingSize)
        return p
    }

    private func position() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 10, y: visible.maxY - size.height - 6))
    }
}
