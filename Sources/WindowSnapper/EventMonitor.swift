import AppKit
import Carbon.HIToolbox

// Monitors global mouse events (via CGEventTap) and a global hotkey (via Carbon).
//
// Shift + drag behaviour:
//   1. leftMouseDown  with Shift held → record the AX window under the cursor.
//   2. leftMouseDragged with Shift    → show overlay; highlight the snap zone.
//   3. leftMouseUp   with Shift       → snap the recorded window; hide overlay.
//   Releasing Shift at any point hides the overlay without snapping.
//
// Cycle hotkey (⌃⌥Space):
//   Moves the focused window through predefinedPositions on its current screen,
//   then wraps around; each additional press moves to the next monitor.

class EventMonitor {

    private let windowManager: WindowManager
    private let gridOverlay: GridOverlayController

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var carbonHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    // Drag state
    private var isShiftHeld = false
    private var draggedWindow: AXUIElement?
    private var mouseDownPoint: CGPoint?
    private var lastHighlightedPosition: WindowPosition?
    private var lastHighlightedScreen: NSScreen?

    // Cycle state
    private var cycleIndex = -1
    private var cycleScreenIndex = 0

    init(windowManager: WindowManager, gridOverlay: GridOverlayController) {
        self.windowManager = windowManager
        self.gridOverlay   = gridOverlay
    }

    // MARK: - Start / Stop

    func start() {
        setupEventTap()
        setupCycleHotkey()
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    // MARK: - CGEventTap

    private func setupEventTap() {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)    |
            (1 << CGEventType.leftMouseUp.rawValue)      |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        // Use listenOnly so normal macOS window dragging is not disrupted.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                if let refcon = refcon {
                    let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.handleCGEvent(type: type, event: event)
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[WindowSnapper] Failed to create event tap – check Accessibility permission.")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {

        case .flagsChanged:
            let shiftWasHeld = isShiftHeld
            isShiftHeld = event.flags.contains(.maskShift)
            if shiftWasHeld && !isShiftHeld {
                // Shift released → discard overlay without snapping
                DispatchQueue.main.async { self.cancelOverlay() }
            }

        case .leftMouseDown:
            mouseDownPoint = event.location
            if isShiftHeld {
                // Capture the window under the cursor before the drag begins.
                let loc = event.location
                DispatchQueue.main.async {
                    self.draggedWindow = self.windowManager.windowAtScreenPoint(loc)
                }
            }

        case .leftMouseDragged:
            guard isShiftHeld else { break }
            let loc = event.location

            // Require a minimum drag distance before showing the overlay.
            if let start = mouseDownPoint {
                let dx = loc.x - start.x, dy = loc.y - start.y
                guard sqrt(dx*dx + dy*dy) > 8 else { break }
            }

            DispatchQueue.main.async {
                if !self.gridOverlay.isVisible { self.gridOverlay.show() }

                guard let screen = self.windowManager.screenContaining(cgPoint: loc),
                      let np     = self.windowManager.normalizedPosition(cgPoint: loc, on: screen)
                else { return }

                let zone = self.windowManager.snapZone(forNormalized: np)
                self.lastHighlightedPosition = zone
                self.lastHighlightedScreen   = screen
                self.gridOverlay.updateHighlight(zone, on: screen)
            }

        case .leftMouseUp:
            guard isShiftHeld, gridOverlay.isVisible else { break }
            let loc = event.location

            DispatchQueue.main.async {
                defer { self.cancelOverlay() }

                guard let pos    = self.lastHighlightedPosition,
                      let screen = self.lastHighlightedScreen
                else { return }

                // Use the window captured at mouseDown, falling back to the focused window.
                let window = self.draggedWindow ?? self.windowManager.focusedWindow()
                guard let window = window else { return }

                let frame = self.windowManager.frameForCell(pos.cell, on: screen)
                self.windowManager.setWindowFrame(window, frame: frame)
                _ = loc   // suppress warning; loc already read above
            }

        default:
            break
        }
    }

    private func cancelOverlay() {
        gridOverlay.hide()
        draggedWindow = nil
        mouseDownPoint = nil
        lastHighlightedPosition = nil
        lastHighlightedScreen   = nil
    }

    // MARK: - Cycle Hotkey  (⌃⌥Space)

    private func setupCycleHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallApplicationEventHandler(
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                Unmanaged<EventMonitor>.fromOpaque(ptr).takeUnretainedValue().cycleWindowPosition()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonHandler
        )

        // Signature 'WSNP' = 0x574F534E... let's just use a numeric literal.
        var hotKeyID = EventHotKeyID(signature: 0x57534E50, id: 1)  // 'WSNP'
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // Cycle through predefined positions on the current screen, then advance to the next screen.
    private func cycleWindowPosition() {
        guard let window = windowManager.focusedWindow() else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Advance the position index; wrap to next screen after the last position.
        cycleIndex += 1
        if cycleIndex >= predefinedPositions.count {
            cycleIndex = 0
            cycleScreenIndex = (cycleScreenIndex + 1) % screens.count
        }

        // Make sure the screen index is still valid (screens can change).
        cycleScreenIndex = min(cycleScreenIndex, screens.count - 1)
        let screen = screens[cycleScreenIndex]

        let position = predefinedPositions[cycleIndex]
        let frame = windowManager.frameForCell(position.cell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)
    }
}
