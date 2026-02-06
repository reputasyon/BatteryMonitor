import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var service: BatteryService!
    private var clickMonitor: Any?

    private let panelW: CGFloat = 320
    private let panelH: CGFloat = 520

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Desktop Macs have no battery — show alert and quit
        if BatteryService.readBattery() == nil {
            let alert = NSAlert()
            alert.messageText = "Pil Bulunamadı"
            alert.informativeText = "Bu uygulama sadece pilli Mac bilgisayarlarda çalışır."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Kapat")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        service = BatteryService()

        NSApp.setActivationPolicy(.accessory)

        // Status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
        }

        // Floating panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 1
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.isOpaque = false

        let hosting = NSHostingController(rootView: BatteryPopoverView(service: service))
        panel.contentView = hosting.view

        // Single timer — service calls onUpdate after each refresh
        service.onUpdate = { [weak self] in
            self?.updateButton()
        }
        service.start()
        updateButton()
    }

    func applicationWillTerminate(_ notification: Notification) {
        service?.stop()
        closePanel()
    }

    // MARK: - Menu Bar Button

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if let info = service.current {
            button.image = nil
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
            button.attributedTitle = NSAttributedString(string: info.menuBarText, attributes: attrs)
        } else {
            button.title = "..."
        }
    }

    // MARK: - Panel Toggle

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button,
              let btnWindow = button.window else { return }

        let btnRect = button.convert(button.bounds, to: nil)
        let screenRect = btnWindow.convertToScreen(btnRect)

        // Position panel centered below the status item with 6pt gap
        let x = screenRect.midX - panelW / 2
        let y = screenRect.minY - panelH - 6

        // Clamp to the screen where the status bar lives (not NSScreen.main)
        let screen = btnWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screen {
            let cx = max(screen.minX + 4, min(x, screen.maxX - panelW - 4))
            panel.setFrame(NSRect(x: cx, y: y, width: panelW, height: panelH), display: true)
        } else {
            panel.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: true)
        }

        // Fade-in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        NSApp.activate()

        // Close when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
