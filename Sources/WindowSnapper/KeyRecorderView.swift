import AppKit
import Carbon.HIToolbox

/// A small rounded-rect view that captures a single key press.
/// Click to start recording, press a key to assign it, Escape to cancel.
class KeyRecorderView: NSView {

    var keyCode: Int? {
        didSet { needsDisplay = true }
    }

    var onKeyRecorded: ((Int) -> Void)?

    private(set) var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 72, height: 26)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let code = Int(event.keyCode)

        // Escape cancels
        if code == kVK_Escape {
            isRecording = false
            return
        }

        // Reject modifier-only key codes
        let modifierCodes = [
            kVK_Shift, kVK_RightShift,
            kVK_Control, kVK_RightControl,
            kVK_Option, kVK_RightOption,
            kVK_Command, kVK_RightCommand,
            kVK_CapsLock, kVK_Function,
        ]
        if modifierCodes.contains(code) { return }

        keyCode = code
        isRecording = false
        onKeyRecorded?(code)
    }

    override func flagsChanged(with event: NSEvent) {
        // Swallow modifier-only presses while recording
        if isRecording { return }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false }
        return super.resignFirstResponder()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let cornerR: CGFloat = 6

        // Background
        let bgColor: NSColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor(white: 0.95, alpha: 1.0)
        bgColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerR, yRadius: cornerR).fill()

        // Border
        let borderColor: NSColor = isRecording
            ? NSColor.controlAccentColor
            : NSColor(white: 0.75, alpha: 1.0)
        borderColor.setStroke()
        let bp = NSBezierPath(roundedRect: rect, xRadius: cornerR, yRadius: cornerR)
        bp.lineWidth = isRecording ? 2.0 : 1.0
        bp.stroke()

        // Text
        let text: String
        if isRecording {
            text = "Press key..."
        } else if let code = keyCode {
            text = displayNameForKeyCode(code)
        } else {
            text = "—"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isRecording
                ? NSColor.controlAccentColor
                : NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ), withAttributes: attrs)
    }
}
