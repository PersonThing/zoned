import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager?
    private var gridOverlay: GridOverlayController?
    private var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request / verify Accessibility permission; the prompt appears automatically.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            showPermissionAlert()
        }

        setupStatusBar()

        windowManager = WindowManager()
        gridOverlay   = GridOverlayController()
        eventMonitor  = EventMonitor(windowManager: windowManager!, gridOverlay: gridOverlay!)
        eventMonitor?.start()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // SF Symbol available in macOS 11+
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "WindowSnapper")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let header = NSMenuItem(title: "WindowSnapper", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(NSMenuItem.separator())

        let infoItem = NSMenuItem(title: "⌃⌥Space — cycle positions", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        let dragItem = NSMenuItem(title: "⇧ + drag — snap to grid", action: nil, keyEquivalent: "")
        dragItem.isEnabled = false
        menu.addItem(dragItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "About WindowSnapper",
                                action: #selector(showAbout),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "WindowSnapper v0"
        alert.informativeText = """
        A minimal macOS window manager.

        Hold ⇧ while dragging any window to snap it to a predefined zone.
        Press ⌃⌥Space to cycle the focused window through layout presets.

        Grid: 12 columns × 6 rows
        """
        alert.runModal()
    }

    // MARK: - Permissions

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        WindowSnapper needs Accessibility access to read and move windows.

        Go to: System Settings → Privacy & Security → Accessibility
        Then enable WindowSnapper.

        Restart the app after granting permission.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}
