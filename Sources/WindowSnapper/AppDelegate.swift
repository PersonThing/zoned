import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager?
    private var gridOverlay: GridOverlayController?
    private var eventMonitor: EventMonitor?
    private var preferencesWindowController: PreferencesWindowController?
    private var hotkeyMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching")
        // Check Accessibility trust silently — don't prompt or block.
        // The user must grant access manually in System Settings → Privacy & Security → Accessibility.
        if !AXIsProcessTrusted() {
            debugLog("Accessibility not trusted — hotkeys will register but window operations will fail")
        }

        setupStatusBar()

        windowManager = WindowManager()
        gridOverlay   = GridOverlayController()
        eventMonitor  = EventMonitor(windowManager: windowManager!, gridOverlay: gridOverlay!)
        eventMonitor?.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: KeyBindingSettings.didChangeNotification, object: nil
        )
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // SF Symbol available in macOS 11+
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Zoned")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let header = NSMenuItem(title: "Zoned", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(NSMenuItem.separator())

        hotkeyMenuItems = buildHotkeyItems()
        for item in hotkeyMenuItems { menu.addItem(item) }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Preferences…",
                                action: #selector(showPreferences),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Zoned",
                                action: #selector(showAbout),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let s = KeyBindingSettings.shared
        let mod = s.cyclingModifier.displayString
        let alert = NSAlert()
        alert.messageText = "Zoned v0"
        alert.informativeText = """
        A minimal macOS window manager.

        \(mod)\(s.prevHorizontalKeyName)/\(s.nextHorizontalKeyName)  Cycle horizontal zones
        \(mod)\(s.prevVerticalKeyName)/\(s.nextVerticalKeyName)  Cycle vertical zones
        \(s.dragModifier.displayString)+drag  Snap window to zone
        """
        alert.runModal()
    }

    @objc private func settingsDidChange() {
        refreshHotkeyItems()
    }

    private func buildHotkeyItems() -> [NSMenuItem] {
        let s = KeyBindingSettings.shared
        let mod = s.cyclingModifier.displayString
        let labels = [
            "\(mod)\(s.prevHorizontalKeyName)/\(s.nextHorizontalKeyName) — horizontal zones",
            "\(mod)\(s.prevVerticalKeyName)/\(s.nextVerticalKeyName) — vertical zones",
            "\(s.dragModifier.displayString)+drag — snap window",
        ]
        return labels.map { label in
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
    }

    private func refreshHotkeyItems() {
        guard let menu = statusItem?.menu else { return }
        // Remove old hotkey items
        for item in hotkeyMenuItems { menu.removeItem(item) }
        // Build new items and insert at the same position (after header + separator)
        hotkeyMenuItems = buildHotkeyItems()
        let insertIdx = 2 // after header and separator
        for (i, item) in hotkeyMenuItems.enumerated() {
            menu.insertItem(item, at: insertIdx + i)
        }
    }

    // MARK: - Permissions

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Zoned needs Accessibility access to read and move windows.

        Go to: System Settings → Privacy & Security → Accessibility
        Then enable Zoned.

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
