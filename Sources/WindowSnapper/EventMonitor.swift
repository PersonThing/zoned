import AppKit
import Carbon.HIToolbox

// Listens for global key/mouse events via CGEventTap.
// Keybindings are read from KeyBindingSettings.shared.

class EventMonitor {

    private let windowManager: WindowManager
    private let gridOverlay: GridOverlayController

    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var auxTap: CFMachPort?
    private var auxTapSource: CFRunLoopSource?

    // Tracks the last-applied zone index per window (keyed by CGWindowID).
    private var lastHorizontalZoneIndex: [CGWindowID: Int] = [:]
    private var lastVerticalZoneIndex: [CGWindowID: Int] = [:]

    // Default vertical zone index — "Full Height" is the middle entry (index 3).
    // This means first ↑ goes to Top 2/3, first ↓ goes to Bottom 2/3.
    private let defaultVerticalIndex = 3

    // Modifier overlay state
    private var cyclingModHeld = false
    private var overlayScreen: NSScreen?

    // Drag modifier state
    private var isDragModHeld = false
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

        let settings = KeyBindingSettings.shared
        guard settings.cyclingModifier.matchesExactly(event.flags) else { return false }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == settings.nextHorizontalKey {
            handleNextHorizontalZone(); return true
        } else if keyCode == settings.prevHorizontalKey {
            handlePrevHorizontalZone(); return true
        } else if keyCode == settings.nextVerticalKey {
            handleNextVerticalZone(); return true
        } else if keyCode == settings.prevVerticalKey {
            handlePrevVerticalZone(); return true
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

            // Find nearest H and V zones independently
            let hIdx = self.windowManager.nearestHorizontalZone(to: loc, on: screen)
            let vIdx = self.windowManager.nearestVerticalZone(to: loc, on: screen)

            // Compose snap target from nearest H + V
            if let hi = hIdx, let vi = vIdx {
                let hZones = horizontalZoneRegistry.zones(for: screen)
                let vZones = verticalZoneRegistry.zones(for: screen)
                let composed = GridCell(
                    col: hZones[hi].cell.col, row: vZones[vi].cell.row,
                    colSpan: hZones[hi].cell.colSpan, rowSpan: vZones[vi].cell.rowSpan
                )
                self.lastHighlightedPosition = WindowPosition(name: "drag", cell: composed)
                self.lastHighlightedScreen = screen
            }

            self.gridOverlay.updateHighlight(horizontalIndex: hIdx, verticalIndex: vIdx)
        }
    }

    private func handleMouseUp(_ event: CGEvent) {
        guard isDragModHeld, shiftDragOverlayShown else { return }

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
            overlayScreen = nil
        }
        draggedWindow = nil
        mouseDownPoint = nil
        lastHighlightedPosition = nil
        lastHighlightedScreen = nil
    }

    // MARK: - Horizontal Zones (⌃⌥← / ⌃⌥→)

    private func handleNextHorizontalZone() {
        cycleZone(
            registry: horizontalZoneRegistry,
            indexMap: &lastHorizontalZoneIndex,
            axis: .horizontal,
            direction: .forward
        )
    }

    private func handlePrevHorizontalZone() {
        cycleZone(
            registry: horizontalZoneRegistry,
            indexMap: &lastHorizontalZoneIndex,
            axis: .horizontal,
            direction: .backward
        )
    }

    // MARK: - Vertical Zones (⌃⌥↑ / ⌃⌥↓)

    private func handlePrevVerticalZone() {
        cycleZone(
            registry: verticalZoneRegistry,
            indexMap: &lastVerticalZoneIndex,
            axis: .vertical,
            direction: .backward,
            defaultIndex: defaultVerticalIndex,
            wrapAcrossScreens: false
        )
    }

    private func handleNextVerticalZone() {
        cycleZone(
            registry: verticalZoneRegistry,
            indexMap: &lastVerticalZoneIndex,
            axis: .vertical,
            direction: .forward,
            defaultIndex: defaultVerticalIndex,
            wrapAcrossScreens: false
        )
    }

    // MARK: - Generic Zone Cycling

    private enum CycleDirection { case forward, backward }
    private enum Axis { case horizontal, vertical }

    private func currentHorizontalCell(forWindow wid: CGWindowID, on screen: NSScreen) -> GridCell {
        guard let idx = lastHorizontalZoneIndex[wid]
        else { return GridCell(col: 0, row: 0, colSpan: GRID_COLS, rowSpan: GRID_ROWS) }
        let zones = horizontalZoneRegistry.zones(for: screen)
        guard idx < zones.count else { return GridCell(col: 0, row: 0, colSpan: GRID_COLS, rowSpan: GRID_ROWS) }
        return zones[idx].cell
    }

    private func currentVerticalCell(forWindow wid: CGWindowID, on screen: NSScreen) -> GridCell {
        let idx = lastVerticalZoneIndex[wid] ?? defaultVerticalIndex
        let zones = verticalZoneRegistry.zones(for: screen)
        guard idx < zones.count else { return GridCell(col: 0, row: 0, colSpan: GRID_COLS, rowSpan: GRID_ROWS) }
        return zones[idx].cell
    }

    private func currentVerticalHighlightIndex(forWindow wid: CGWindowID) -> Int {
        lastVerticalZoneIndex[wid] ?? defaultVerticalIndex
    }

    private func cycleZone(
        registry: ZoneRegistry,
        indexMap: inout [CGWindowID: Int],
        axis: Axis,
        direction: CycleDirection,
        defaultIndex: Int = -1,
        wrapAcrossScreens: Bool = true
    ) {
        guard let window = windowManager.focusedWindow(),
              let wid = windowManager.windowID(for: window),
              let currentScreen = windowManager.screenFor(window: window)
        else { return }

        let screens = sortedScreens()
        guard !screens.isEmpty else { return }

        let currentScreenIdx = screens.firstIndex(of: currentScreen) ?? 0
        var screenIdx = currentScreenIdx
        var screen = screens[screenIdx]
        var zones = registry.zones(for: screen)

        var zoneIdx: Int
        switch direction {
        case .forward:
            zoneIdx = (indexMap[wid] ?? defaultIndex) + 1
            if zoneIdx >= zones.count {
                if wrapAcrossScreens {
                    screenIdx = (screenIdx + 1) % screens.count
                    screen = screens[screenIdx]
                    zones = registry.zones(for: screen)
                }
                zoneIdx = 0
            }
        case .backward:
            if let lastIdx = indexMap[wid] {
                zoneIdx = lastIdx - 1
            } else {
                zoneIdx = defaultIndex - 1
            }
            if zoneIdx < 0 {
                if wrapAcrossScreens {
                    screenIdx = (screenIdx - 1 + screens.count) % screens.count
                    screen = screens[screenIdx]
                    zones = registry.zones(for: screen)
                }
                zoneIdx = zones.count - 1
            }
        }

        guard !zones.isEmpty else { return }

        let zone = zones[zoneIdx]
        indexMap[wid] = zoneIdx

        // Compose the final cell: this axis from the new zone, other axis from current state.
        let composedCell: GridCell
        switch axis {
        case .horizontal:
            let v = currentVerticalCell(forWindow: wid, on: screen)
            composedCell = GridCell(col: zone.cell.col, row: v.row,
                                   colSpan: zone.cell.colSpan, rowSpan: v.rowSpan)
        case .vertical:
            let h = currentHorizontalCell(forWindow: wid, on: screen)
            composedCell = GridCell(col: h.col, row: zone.cell.row,
                                   colSpan: h.colSpan, rowSpan: zone.cell.rowSpan)
        }

        let frame = windowManager.frameForCell(composedCell, on: screen)
        windowManager.setWindowFrame(window, frame: frame)

        // Update overlay
        DispatchQueue.main.async {
            let hHighlight = (axis == .horizontal) ? zoneIdx : self.currentHorizontalZoneIndex(forWindow: wid)
            let vHighlight = (axis == .vertical) ? zoneIdx : self.currentVerticalHighlightIndex(forWindow: wid)

            if !self.gridOverlay.isVisible || screen != self.overlayScreen {
                self.showOverlay(on: screen, forWindow: wid, activeHorizontalIndex: hHighlight, activeVerticalIndex: vHighlight)
            } else {
                self.gridOverlay.updateHighlight(horizontalIndex: hHighlight, verticalIndex: vHighlight)
            }
        }
    }

    // MARK: - Helpers

    private func currentHorizontalZoneIndex(forWindow wid: CGWindowID) -> Int? {
        lastHorizontalZoneIndex[wid]
    }

    /// Show (or recreate) the overlay on `screen` with the current H/V zone state.
    private func showOverlay(on screen: NSScreen, forWindow wid: CGWindowID? = nil, activeHorizontalIndex hIdx: Int? = nil, activeVerticalIndex vIdx: Int? = nil) {
        if gridOverlay.isVisible { gridOverlay.hide() }
        let h = hIdx ?? wid.flatMap { currentHorizontalZoneIndex(forWindow: $0) }
        let v = vIdx ?? wid.map { currentVerticalHighlightIndex(forWindow: $0) } ?? defaultVerticalIndex
        gridOverlay.show(on: screen, activeHorizontalIndex: h, activeVerticalIndex: v)
        overlayScreen = screen
    }

    private func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }
}
