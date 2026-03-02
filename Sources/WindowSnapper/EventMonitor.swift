import AppKit
import Carbon.HIToolbox

// Listens for global key/mouse events via CGEventTap.
// Keybindings are read from KeyBindingSettings.shared.
// Zone layouts are read from LayoutStore.shared.

class EventMonitor {

    private let windowManager: WindowManager
    private let gridOverlay: GridOverlayController

    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var auxTap: CFMachPort?
    private var auxTapSource: CFRunLoopSource?

    // Tracks the last-applied zone index per window (keyed by CGWindowID).
    private var lastZoneIndex: [CGWindowID: Int] = [:]

    // Modifier overlay state
    private var cyclingModHeld = false
    private var overlayScreen: NSScreen?

    // Drag modifier state
    private var isDragModHeld = false
    private var draggedWindow: AXUIElement?
    private var mouseDownPoint: CGPoint?
    private var lastHighlightedCell: GridCell?
    private var lastHighlightedScreen: NSScreen?
    private var shiftDragOverlayShown = false

    // Drag overlap cycling (for zones overlapping the same center)
    private var dragOverlapGroup: [Int] = []
    private var dragOverlapCycleIdx: Int = 0

    init(windowManager: WindowManager, gridOverlay: GridOverlayController) {
        self.windowManager = windowManager
        self.gridOverlay   = gridOverlay

        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutsDidChange),
            name: LayoutStore.didChangeNotification, object: nil
        )
    }

    @objc private func layoutsDidChange() {
        lastZoneIndex.removeAll()
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

    private func setupEventTap() {
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

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown, handleKeyDown(event) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

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
        let settings = KeyBindingSettings.shared

        let wasHeld = cyclingModHeld
        cyclingModHeld = settings.cyclingModifier.isSubset(of: flags)

        if cyclingModHeld && !wasHeld {
            debugLog("cycling modifier held — showing overlay")
            DispatchQueue.main.async {
                if let win = self.windowManager.focusedWindow(),
                   let screen = self.windowManager.screenFor(window: win) {
                    let wid = self.windowManager.windowID(for: win)
                    self.showOverlay(on: screen, forWindow: wid)
                }
            }
        } else if !cyclingModHeld && wasHeld && !shiftDragOverlayShown {
            debugLog("cycling modifier released — hiding overlay")
            DispatchQueue.main.async { self.gridOverlay.hide(); self.overlayScreen = nil }
        }

        let dragWasHeld = isDragModHeld
        isDragModHeld = settings.dragModifier.isSubset(of: flags)
        if dragWasHeld && !isDragModHeld {
            DispatchQueue.main.async { self.cancelShiftDrag() }
        }
    }

    // MARK: - Key Down

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        // Pass through when preferences window is capturing keys
        if PreferencesWindowController.isActive { return false }

        // During drag: F cycles overlapping zones at the same position
        if shiftDragOverlayShown {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == kVK_ANSI_F {
                DispatchQueue.main.async { self.cycleDragOverlap() }
                return true
            }
        }

        let settings = KeyBindingSettings.shared
        guard settings.cyclingModifier.matchesExactly(event.flags) else { return false }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == settings.nextZoneKey {
            cycleZone(direction: 1); return true
        } else if keyCode == settings.prevZoneKey {
            cycleZone(direction: -1); return true
        } else if keyCode == settings.nextLayoutKey {
            cycleLayout(direction: 1); return true
        } else if keyCode == settings.prevLayoutKey {
            cycleLayout(direction: -1); return true
        }
        return false
    }

    // MARK: - Modifier + Drag

    private func handleMouseDown(_ event: CGEvent) {
        mouseDownPoint = event.location
        if isDragModHeld {
            debugLog("drag modifier+mouseDown at \(event.location)")
            let loc = event.location
            DispatchQueue.main.async {
                self.draggedWindow = self.windowManager.windowAtScreenPoint(loc)
            }
        }
    }

    private func handleMouseDragged(_ event: CGEvent) {
        guard isDragModHeld else { return }
        let loc = event.location

        if let start = mouseDownPoint {
            let dx = loc.x - start.x, dy = loc.y - start.y
            guard sqrt(dx*dx + dy*dy) > 8 else { return }
        }

        DispatchQueue.main.async {
            guard let screen = self.windowManager.screenContaining(cgPoint: loc)
            else { return }

            // Show or move the overlay
            if !self.gridOverlay.isVisible || screen != self.overlayScreen {
                self.showOverlay(on: screen)
            }
            self.shiftDragOverlayShown = true

            // Find nearest zone
            let zoneIdx = self.windowManager.nearestZone(to: loc, on: screen)

            // Resolve overlap group
            var effectiveIdx = zoneIdx
            if let zi = zoneIdx {
                let newGroup = self.windowManager.overlapGroup(at: zi, on: screen)
                if newGroup != self.dragOverlapGroup {
                    self.dragOverlapGroup = newGroup
                    self.dragOverlapCycleIdx = 0
                }
                if !self.dragOverlapGroup.isEmpty {
                    effectiveIdx = self.dragOverlapGroup[self.dragOverlapCycleIdx]
                }
            }

            // Build snap target
            let layout = LayoutStore.shared.activeLayout(for: screen)
            let zones = layout.sortedZones
            if let zi = effectiveIdx, zi < zones.count {
                let zone = zones[zi]
                self.lastHighlightedCell = GridCell(
                    col: zone.col, row: zone.row,
                    colSpan: zone.colSpan, rowSpan: zone.rowSpan
                )
                self.lastHighlightedScreen = screen
            }

            self.gridOverlay.updateHighlight(zoneIndex: effectiveIdx)
        }
    }

    private func handleMouseUp(_ event: CGEvent) {
        guard isDragModHeld, shiftDragOverlayShown else { return }

        DispatchQueue.main.async {
            defer { self.cancelShiftDrag() }

            guard let cell = self.lastHighlightedCell,
                  let screen = self.lastHighlightedScreen
            else { return }

            let window = self.draggedWindow ?? self.windowManager.focusedWindow()
            guard let window = window else { return }

            let frame = self.windowManager.frameForCell(cell, on: screen)
            self.windowManager.setWindowFrame(window, frame: frame)
        }
    }

    private func cycleDragOverlap() {
        guard dragOverlapGroup.count > 1,
              let screen = lastHighlightedScreen else { return }

        dragOverlapCycleIdx = (dragOverlapCycleIdx + 1) % dragOverlapGroup.count
        let zoneIdx = dragOverlapGroup[dragOverlapCycleIdx]

        let layout = LayoutStore.shared.activeLayout(for: screen)
        let zones = layout.sortedZones

        if zoneIdx < zones.count {
            let zone = zones[zoneIdx]
            lastHighlightedCell = GridCell(
                col: zone.col, row: zone.row,
                colSpan: zone.colSpan, rowSpan: zone.rowSpan
            )
        }

        gridOverlay.updateHighlight(zoneIndex: zoneIdx)
    }

    private func cancelShiftDrag() {
        if shiftDragOverlayShown {
            gridOverlay.hide()
            shiftDragOverlayShown = false
            overlayScreen = nil
        }
        draggedWindow = nil
        mouseDownPoint = nil
        lastHighlightedCell = nil
        lastHighlightedScreen = nil
        dragOverlapGroup = []
        dragOverlapCycleIdx = 0
    }

    // MARK: - Layout Cycling (⌃⌥↑ / ⌃⌥↓)

    private func cycleLayout(direction: Int) {
        guard let window = windowManager.focusedWindow(),
              let screen = windowManager.screenFor(window: window)
        else { return }

        let newLayout = LayoutStore.shared.cycleLayout(for: screen, direction: direction)
        debugLog("Cycled to layout: \(newLayout.name)")

        lastZoneIndex.removeAll()

        DispatchQueue.main.async {
            self.showOverlay(on: screen)
        }
    }

    // MARK: - Zone Cycling (⌃⌥← / ⌃⌥→)

    private func cycleZone(direction: Int) {
        guard let window = windowManager.focusedWindow(),
              let wid = windowManager.windowID(for: window),
              let currentScreen = windowManager.screenFor(window: window)
        else { return }

        let screens = sortedScreens()
        guard !screens.isEmpty else { return }

        let currentScreenIdx = screens.firstIndex(of: currentScreen) ?? 0
        var screenIdx = currentScreenIdx
        var screen = screens[screenIdx]
        var layout = LayoutStore.shared.activeLayout(for: screen)
        var zones = layout.sortedZones

        var zoneIdx: Int
        if direction > 0 {
            zoneIdx = (lastZoneIndex[wid] ?? -1) + 1
            if zoneIdx >= zones.count {
                screenIdx = (screenIdx + 1) % screens.count
                screen = screens[screenIdx]
                layout = LayoutStore.shared.activeLayout(for: screen)
                zones = layout.sortedZones
                zoneIdx = 0
            }
        } else {
            if let lastIdx = lastZoneIndex[wid] {
                zoneIdx = lastIdx - 1
            } else {
                zoneIdx = -1
            }
            if zoneIdx < 0 {
                screenIdx = (screenIdx - 1 + screens.count) % screens.count
                screen = screens[screenIdx]
                layout = LayoutStore.shared.activeLayout(for: screen)
                zones = layout.sortedZones
                zoneIdx = zones.count - 1
            }
        }

        guard !zones.isEmpty, zoneIdx >= 0, zoneIdx < zones.count else { return }

        let zone = zones[zoneIdx]
        lastZoneIndex[wid] = zoneIdx

        let cell = GridCell(col: zone.col, row: zone.row, colSpan: zone.colSpan, rowSpan: zone.rowSpan)
        let frame = windowManager.frameForCell(cell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)

        DispatchQueue.main.async {
            if !self.gridOverlay.isVisible || screen != self.overlayScreen {
                self.showOverlay(on: screen, forWindow: wid, activeZoneIndex: zoneIdx)
            } else {
                self.gridOverlay.updateHighlight(zoneIndex: zoneIdx)
            }
        }
    }

    // MARK: - Helpers

    private func showOverlay(on screen: NSScreen, forWindow wid: CGWindowID? = nil, activeZoneIndex zIdx: Int? = nil) {
        if gridOverlay.isVisible { gridOverlay.hide() }
        let layout = LayoutStore.shared.activeLayout(for: screen)
        let z = zIdx ?? wid.flatMap { lastZoneIndex[$0] }
        gridOverlay.show(on: screen, layout: layout, activeZoneIndex: z)
        overlayScreen = screen
    }

    private func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }
}
