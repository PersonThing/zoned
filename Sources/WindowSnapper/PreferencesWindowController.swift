import AppKit
import Carbon.HIToolbox

class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    private let settings = KeyBindingSettings.shared

    // Cycling modifier checkboxes
    private var ctrlCheck:  NSButton!
    private var optCheck:   NSButton!
    private var cmdCheck:   NSButton!
    private var shiftCheck: NSButton!

    // Key recorders
    private var nextHRecorder: KeyRecorderView!
    private var prevHRecorder: KeyRecorderView!
    private var nextVRecorder: KeyRecorderView!
    private var prevVRecorder: KeyRecorderView!

    // Drag modifier radio buttons
    private var dragCtrl:  NSButton!
    private var dragOpt:   NSButton!
    private var dragCmd:   NSButton!
    private var dragShift: NSButton!

    // Overlay mode
    private var fullScreenOverlayCheck: NSButton!

    /// Set by the preferences window to tell EventMonitor to pass through key events.
    static var isActive = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 590),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowSnapper Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        setupUI()
        loadFromSettings()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        Self.isActive = true
    }

    func windowDidResignKey(_ notification: Notification) {
        Self.isActive = false
    }

    // MARK: - UI Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // ── Zone Cycling Modifier ────────────────────────────────────────
        mainStack.addArrangedSubview(sectionLabel("ZONE CYCLING MODIFIER"))

        ctrlCheck  = makeCheckbox("Control (⌃)", action: #selector(cyclingModChanged))
        optCheck   = makeCheckbox("Option (⌥)",  action: #selector(cyclingModChanged))
        cmdCheck   = makeCheckbox("Command (⌘)", action: #selector(cyclingModChanged))
        shiftCheck = makeCheckbox("Shift (⇧)",   action: #selector(cyclingModChanged))

        let modRow1 = hStack([ctrlCheck, optCheck])
        let modRow2 = hStack([cmdCheck, shiftCheck])
        mainStack.addArrangedSubview(modRow1)
        mainStack.addArrangedSubview(modRow2)

        // ── Action Keys ──────────────────────────────────────────────────
        mainStack.addArrangedSubview(spacer(8))
        mainStack.addArrangedSubview(sectionLabel("ACTION KEYS"))

        nextHRecorder = KeyRecorderView()
        prevHRecorder = KeyRecorderView()
        nextVRecorder = KeyRecorderView()
        prevVRecorder = KeyRecorderView()

        nextHRecorder.onKeyRecorded = { [weak self] code in
            self?.settings.nextHorizontalKey = code; self?.settings.save()
        }
        prevHRecorder.onKeyRecorded = { [weak self] code in
            self?.settings.prevHorizontalKey = code; self?.settings.save()
        }
        nextVRecorder.onKeyRecorded = { [weak self] code in
            self?.settings.nextVerticalKey = code; self?.settings.save()
        }
        prevVRecorder.onKeyRecorded = { [weak self] code in
            self?.settings.prevVerticalKey = code; self?.settings.save()
        }

        mainStack.addArrangedSubview(keyRow("Next horizontal zone:", nextHRecorder))
        mainStack.addArrangedSubview(keyRow("Prev horizontal zone:", prevHRecorder))
        mainStack.addArrangedSubview(keyRow("Next vertical zone:",   nextVRecorder))
        mainStack.addArrangedSubview(keyRow("Prev vertical zone:",   prevVRecorder))

        // ── Drag Modifier ────────────────────────────────────────────────
        mainStack.addArrangedSubview(spacer(8))
        mainStack.addArrangedSubview(sectionLabel("DRAG MODIFIER"))

        dragCtrl  = makeRadio("Control (⌃)", action: #selector(dragModChanged))
        dragOpt   = makeRadio("Option (⌥)",  action: #selector(dragModChanged))
        dragCmd   = makeRadio("Command (⌘)", action: #selector(dragModChanged))
        dragShift = makeRadio("Shift (⇧)",   action: #selector(dragModChanged))

        let dragRow1 = hStack([dragCtrl, dragOpt])
        let dragRow2 = hStack([dragCmd, dragShift])
        mainStack.addArrangedSubview(dragRow1)
        mainStack.addArrangedSubview(dragRow2)

        // ── Overlay ──────────────────────────────────────────────────────
        mainStack.addArrangedSubview(spacer(8))
        mainStack.addArrangedSubview(sectionLabel("OVERLAY"))

        fullScreenOverlayCheck = makeCheckbox("Full-screen overlay", action: #selector(overlayModeChanged))
        mainStack.addArrangedSubview(fullScreenOverlayCheck)

        // ── Restore Defaults ─────────────────────────────────────────────
        mainStack.addArrangedSubview(spacer(12))

        let restoreBtn = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restoreBtn.bezelStyle = .rounded
        mainStack.addArrangedSubview(restoreBtn)
    }

    // MARK: - Actions

    @objc private func cyclingModChanged(_ sender: NSButton) {
        let proposed = ModifierSet(
            control: ctrlCheck.state == .on,
            option:  optCheck.state == .on,
            command: cmdCheck.state == .on,
            shift:   shiftCheck.state == .on
        )
        // Require at least one modifier
        if !proposed.hasAnyModifier {
            sender.state = .on
            return
        }
        settings.cyclingModifier = proposed
        settings.save()
    }

    @objc private func dragModChanged(_ sender: NSButton) {
        // Radio-button behavior: turn off the others
        for btn in [dragCtrl, dragOpt, dragCmd, dragShift] where btn !== sender {
            btn?.state = .off
        }
        sender.state = .on

        settings.dragModifier = ModifierSet(
            control: dragCtrl.state == .on,
            option:  dragOpt.state == .on,
            command: dragCmd.state == .on,
            shift:   dragShift.state == .on
        )
        settings.save()
    }

    @objc private func overlayModeChanged(_ sender: NSButton) {
        settings.fullScreenOverlay = (sender.state == .on)
        settings.save()
    }

    @objc private func restoreDefaults(_ sender: Any?) {
        settings.resetToDefaults()
        loadFromSettings()
    }

    // MARK: - Load / Refresh

    private func loadFromSettings() {
        ctrlCheck.state  = settings.cyclingModifier.control ? .on : .off
        optCheck.state   = settings.cyclingModifier.option  ? .on : .off
        cmdCheck.state   = settings.cyclingModifier.command ? .on : .off
        shiftCheck.state = settings.cyclingModifier.shift   ? .on : .off

        nextHRecorder.keyCode = settings.nextHorizontalKey
        prevHRecorder.keyCode = settings.prevHorizontalKey
        nextVRecorder.keyCode = settings.nextVerticalKey
        prevVRecorder.keyCode = settings.prevVerticalKey

        dragCtrl.state  = settings.dragModifier.control ? .on : .off
        dragOpt.state   = settings.dragModifier.option  ? .on : .off
        dragCmd.state   = settings.dragModifier.command ? .on : .off
        dragShift.state = settings.dragModifier.shift   ? .on : .off

        fullScreenOverlayCheck.state = settings.fullScreenOverlay ? .on : .off
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeCheckbox(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.font = NSFont.systemFont(ofSize: 13)
        return btn
    }

    private func makeRadio(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(radioButtonWithTitle: title, target: self, action: action)
        btn.font = NSFont.systemFont(ofSize: 13)
        return btn
    }

    private func keyRow(_ label: String, _ recorder: KeyRecorderView) -> NSView {
        let textField = NSTextField(labelWithString: label)
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        recorder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(equalToConstant: 72),
            recorder.heightAnchor.constraint(equalToConstant: 26),
        ])

        let row = NSStackView(views: [textField, recorder])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func hStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 20
        return stack
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
}
