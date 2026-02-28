import AppKit
import Carbon.HIToolbox

// Listens for global key/mouse events via CGEventTap.
//
// Keyboard:
//   Hold ⌃⌥       — show zone overlay
//   ⌃⌥↑           — full screen on current monitor
//   ⌃⌥→           — next zone (wraps across monitors left-to-right)
//   ⌃⌥←           — previous zone (wraps across monitors right-to-left)
//   Release ⌃⌥    — hide overlay
//
// Mouse:
//   ⇧ + drag      — show zone overlay, snap window on release

class EventMonitor {

    private let windowManager: WindowManager
    private let gridOverlay: GridOverlayController

    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var auxTap: CFMachPort?
    private var auxTapSource: CFRunLoopSource?

    // Tracks the last-applied zone index per display (keyed by CGDirectDisplayID).
    private var lastZoneIndex: [UInt32: Int] = [:]

    // Modifier overlay state
    private var ctrlOptHeld = false

    // Shift+drag state
    private var isShiftHeld = false
    private var draggedWindow: AXUIElement?
    private var mouseDownPoint: CGPoint?
    private var lastHighlightedPosition: WindowPosition?
    private var lastHighlightedScreen: NSScreen?
    private var shiftDragOverlayShown = false

    init(windowManager: WindowManager, gridOverlay: GridOverlayController) {
        self.windowManager = windowManager
        self.gridOverlay   = gridOverlay
    }

    // MARK: - Start / Stop

    func start() {
        setupEventTap()
    }

    func stop() {
        if let tap = keyTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let tap = auxTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = auxTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }

    // MARK: - CGEventTap
    //
    // Two taps:
    //   1. Active (.defaultTap) for keyDown — allows swallowing ⌃⌥+arrow events.
    //   2. Listen-only (.listenOnly) for flagsChanged + mouse — these don't need
    //      to be swallowed, and .defaultTap doesn't reliably deliver them.

    private func setupEventTap() {
        // ── Active tap: keyDown only ──────────────────────────────────────────
        let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let kTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleKeyEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("Failed to create key event tap – check Accessibility permission.")
            return
        }

        keyTap = kTap
        let kSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, kTap, 0)
        keyTapSource = kSrc
        CFRunLoopAddSource(CFRunLoopGetMain(), kSrc, .commonModes)
        CGEvent.tapEnable(tap: kTap, enable: true)
        debugLog("Key event tap (active) created and enabled")

        // ── Listen-only tap: flagsChanged + mouse ─────────────────────────────
        let auxMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)     |
            (1 << CGEventType.leftMouseDown.rawValue)    |
            (1 << CGEventType.leftMouseUp.rawValue)      |
            (1 << CGEventType.leftMouseDragged.rawValue)
        )

        guard let aTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: auxMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleAuxEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("Failed to create aux event tap – check Accessibility permission.")
            return
        }

        auxTap = aTap
        let aSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, aTap, 0)
        auxTapSource = aSrc
        CFRunLoopAddSource(CFRunLoopGetMain(), aSrc, .commonModes)
        CGEvent.tapEnable(tap: aTap, enable: true)
        debugLog("Aux event tap (listen-only) created and enabled")
    }

    /// Active tap router (keyDown). Returns nil to swallow, or the event to pass through.
    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown, handleKeyDown(event) {
            return nil  // swallow
        }
        return Unmanaged.passUnretained(event)
    }

    /// Listen-only tap router (flagsChanged + mouse). Return value ignored by OS.
    private func handleAuxEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .leftMouseDown:
            handleMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
        case .leftMouseUp:
            handleMouseUp(event)
        default:
            break
        }
    }

    // MARK: - Flags Changed (modifier tracking)

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags

        // ── Ctrl+Opt overlay ────────────────────────────────────────────────
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt  = flags.contains(.maskAlternate)
        let wasHeld = ctrlOptHeld
        ctrlOptHeld = hasCtrl && hasOpt

        if ctrlOptHeld && !wasHeld {
            debugLog("⌃⌥ held — showing overlay")
            DispatchQueue.main.async {
                if !self.gridOverlay.isVisible {
                    // Show overlay on the focused window's screen
                    let screen: NSScreen? = {
                        guard let win = self.windowManager.focusedWindow() else { return nil }
                        return self.windowManager.screenFor(window: win)
                    }()
                    self.gridOverlay.show(on: screen)
                }
                self.highlightCurrentZone()
            }
        } else if !ctrlOptHeld && wasHeld && !shiftDragOverlayShown {
            debugLog("⌃⌥ released — hiding overlay")
            DispatchQueue.main.async { self.gridOverlay.hide() }
        }

        // ── Shift tracking for drag ─────────────────────────────────────────
        let shiftWasHeld = isShiftHeld
        isShiftHeld = flags.contains(.maskShift)
        if shiftWasHeld && !isShiftHeld {
            // Shift released mid-drag → cancel without snapping
            DispatchQueue.main.async { self.cancelShiftDrag() }
        }
    }

    // MARK: - Key Down (⌃⌥ + arrow keys)

    /// Returns true if the event was handled (should be swallowed).
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let hasCtrl  = flags.contains(.maskControl)
        let hasOpt   = flags.contains(.maskAlternate)
        let hasCmd   = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        guard hasCtrl && hasOpt && !hasCmd && !hasShift else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch Int(keyCode) {
        case kVK_UpArrow:
            handleFullScreen()
            return true
        case kVK_RightArrow:
            handleNextZone()
            return true
        case kVK_LeftArrow:
            handlePrevZone()
            return true
        default:
            return false
        }
    }

    // MARK: - Shift + Drag

    private func handleMouseDown(_ event: CGEvent) {
        mouseDownPoint = event.location
        if isShiftHeld {
            debugLog("shift+mouseDown at \(event.location)")
            let loc = event.location
            DispatchQueue.main.async {
                self.draggedWindow = self.windowManager.windowAtScreenPoint(loc)
            }
        }
    }

    private func handleMouseDragged(_ event: CGEvent) {
        guard isShiftHeld else { return }
        let loc = event.location

        // Require minimum drag distance
        if let start = mouseDownPoint {
            let dx = loc.x - start.x, dy = loc.y - start.y
            guard sqrt(dx*dx + dy*dy) > 8 else { return }
        }

        DispatchQueue.main.async {
            guard let screen = self.windowManager.screenContaining(cgPoint: loc)
            else { return }

            if !self.gridOverlay.isVisible {
                self.gridOverlay.show(on: screen)
                self.shiftDragOverlayShown = true
            }

            guard let (idx, zone) = self.windowManager.nearestZone(to: loc, on: screen)
            else { return }
            self.lastHighlightedPosition = zone
            self.lastHighlightedScreen = screen
            self.gridOverlay.highlightZone(index: idx, on: screen)
        }
    }

    private func handleMouseUp(_ event: CGEvent) {
        guard isShiftHeld, shiftDragOverlayShown else { return }

        DispatchQueue.main.async {
            defer { self.cancelShiftDrag() }

            guard let pos = self.lastHighlightedPosition,
                  let screen = self.lastHighlightedScreen
            else { return }

            let window = self.draggedWindow ?? self.windowManager.focusedWindow()
            guard let window = window else { return }

            let frame = self.windowManager.frameForCell(pos.cell, on: screen)
            self.windowManager.setWindowFrame(window, frame: frame)
        }
    }

    private func cancelShiftDrag() {
        if shiftDragOverlayShown {
            gridOverlay.hide()
            shiftDragOverlayShown = false
        }
        draggedWindow = nil
        mouseDownPoint = nil
        lastHighlightedPosition = nil
        lastHighlightedScreen = nil
    }

    // MARK: - Full Screen (⌃⌥↑)

    private func handleFullScreen() {
        guard let window = windowManager.focusedWindow(),
              let screen = windowManager.screenFor(window: window)
        else { return }

        let frame = windowManager.frameForCell(fullScreenZone.cell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)

        if let did = displayID(for: screen) {
            lastZoneIndex.removeValue(forKey: did)
        }

        DispatchQueue.main.async { self.highlightCurrentZone() }
    }

    // MARK: - Next Zone (⌃⌥→)

    private func handleNextZone() {
        guard let window = windowManager.focusedWindow(),
              let currentScreen = windowManager.screenFor(window: window)
        else { return }

        let screens = sortedScreens()
        guard !screens.isEmpty else { return }

        let currentScreenIdx = screens.firstIndex(of: currentScreen) ?? 0
        var screenIdx = currentScreenIdx
        var screen = screens[screenIdx]
        var zones = zoneRegistry.zones(for: screen)
        let did = displayID(for: screen) ?? 0

        var zoneIdx = (lastZoneIndex[did] ?? -1) + 1

        if zoneIdx >= zones.count {
            screenIdx = (screenIdx + 1) % screens.count
            screen = screens[screenIdx]
            zones = zoneRegistry.zones(for: screen)
            zoneIdx = 0
        }

        guard !zones.isEmpty else { return }

        let zone = zones[zoneIdx]
        let frame = windowManager.frameForCell(zone.cell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)

        let newDid = displayID(for: screen) ?? 0
        lastZoneIndex[newDid] = zoneIdx

        DispatchQueue.main.async {
            self.gridOverlay.highlightZone(index: zoneIdx, on: screen)
        }
    }

    // MARK: - Previous Zone (⌃⌥←)

    private func handlePrevZone() {
        guard let window = windowManager.focusedWindow(),
              let currentScreen = windowManager.screenFor(window: window)
        else { return }

        let screens = sortedScreens()
        guard !screens.isEmpty else { return }

        let currentScreenIdx = screens.firstIndex(of: currentScreen) ?? 0
        var screenIdx = currentScreenIdx
        var screen = screens[screenIdx]
        var zones = zoneRegistry.zones(for: screen)
        let did = displayID(for: screen) ?? 0

        let lastIdx = lastZoneIndex[did]
        var zoneIdx: Int

        if let lastIdx = lastIdx {
            zoneIdx = lastIdx - 1
        } else {
            zoneIdx = zones.count - 1
        }

        if zoneIdx < 0 {
            screenIdx = (screenIdx - 1 + screens.count) % screens.count
            screen = screens[screenIdx]
            zones = zoneRegistry.zones(for: screen)
            zoneIdx = zones.count - 1
        }

        guard !zones.isEmpty else { return }

        let zone = zones[zoneIdx]
        let frame = windowManager.frameForCell(zone.cell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)

        let newDid = displayID(for: screen) ?? 0
        lastZoneIndex[newDid] = zoneIdx

        DispatchQueue.main.async {
            self.gridOverlay.highlightZone(index: zoneIdx, on: screen)
        }
    }

    // MARK: - Helpers

    private func highlightCurrentZone() {
        guard let window = windowManager.focusedWindow(),
              let screen = windowManager.screenFor(window: window),
              let did = displayID(for: screen),
              let idx = lastZoneIndex[did]
        else { return }
        gridOverlay.highlightZone(index: idx, on: screen)
    }

    private func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }
}
