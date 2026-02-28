import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

class WindowManager {

    func windowID(for window: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(window, &wid) == .success ? wid : nil
    }

    // MARK: - AX Window Operations

    func windowAtScreenPoint(_ cgPoint: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        let result = AXUIElementCopyElementAtPosition(system, Float(cgPoint.x), Float(cgPoint.y), &element)
        guard result == .success, let el = element else { return nil }
        return windowFromElement(el)
    }

    private func windowFromElement(_ element: AXUIElement) -> AXUIElement? {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let r = role as? String, r == kAXWindowRole as String {
            return element
        }
        var parent: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        if result == .success, let p = parent {
            return windowFromElement(p as! AXUIElement)
        }
        return nil
    }

    func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        var origin = frame.origin
        var size = frame.size

        // Position → Size → Position: some apps (notably Electron-based ones like
        // Claude Desktop) clamp the window origin when the size changes, so we set
        // position a second time to ensure the final frame is correct.
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            let r1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            if r1 != .success { debugLog("setWindowFrame: set position failed (\(r1.rawValue))") }
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let r2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if r2 != .success { debugLog("setWindowFrame: set size failed (\(r2.rawValue))") }
        }
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            let r3 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            if r3 != .success { debugLog("setWindowFrame: set position (2nd) failed (\(r3.rawValue))") }
        }
    }

    func focusedWindow() -> AXUIElement? {
        // Try AX system-wide first, fall back to NSWorkspace for apps where
        // kAXFocusedApplicationAttribute fails (e.g. some terminal emulators).
        let app: AXUIElement? = {
            let system = AXUIElementCreateSystemWide()
            var focusedApp: AnyObject?
            let r = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp)
            if r == .success, let a = focusedApp {
                return (a as! AXUIElement)
            }
            debugLog("focusedWindow: AX focused app failed (\(r.rawValue)), trying NSWorkspace")
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                debugLog("focusedWindow: no frontmost application")
                return nil
            }
            debugLog("focusedWindow: NSWorkspace frontmost=\(frontmost.localizedName ?? "?")")
            return AXUIElementCreateApplication(frontmost.processIdentifier)
        }()

        guard let app = app else { return nil }

        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard let w = focusedWindow else {
            debugLog("focusedWindow: no focused window (error \(result.rawValue))")
            return nil
        }
        return (w as! AXUIElement)
    }

    // MARK: - Coordinate Conversion
    // macOS coordinate systems:
    //   AppKit / NSScreen:  origin = bottom-left of main screen, y increases upward
    //   CG / AX API:        origin = top-left of main screen, y increases downward

    var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    func cgToAppKit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    func screenContaining(cgPoint: CGPoint) -> NSScreen? {
        let appKitPoint = cgToAppKit(cgPoint)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }

    // Returns (nx, ny) normalised within the visible frame.
    // nx: 0 = left edge, 1 = right edge
    // ny: 0 = bottom edge, 1 = top edge  (AppKit y-up)
    func normalizedPosition(cgPoint: CGPoint, on screen: NSScreen) -> CGPoint? {
        let appKitPoint = cgToAppKit(cgPoint)
        let vf = screen.visibleFrame
        guard vf.contains(appKitPoint) else { return nil }
        let nx = (appKitPoint.x - vf.minX) / vf.width
        let ny = (appKitPoint.y - vf.minY) / vf.height
        return CGPoint(x: nx, y: ny)
    }

    // Convert a GridCell on a screen to a CG/AX frame rect.
    // The AX API uses top-left origin (y-down), matching CGEvent coordinates.
    func frameForCell(_ cell: GridCell, on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame      // AppKit coords (y-up, bottom-left origin)
        let cellW = vf.width  / CGFloat(GRID_COLS)
        let cellH = vf.height / CGFloat(GRID_ROWS)

        // row 0 = topmost; AppKit y increases upward, so topmost row has the largest y.
        let appKitX = vf.minX + CGFloat(cell.col) * cellW
        let appKitY = vf.minY + CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
        let w = CGFloat(cell.colSpan) * cellW
        let h = CGFloat(cell.rowSpan) * cellH

        // Flip to CG/AX coords
        let cgY = mainScreenHeight - appKitY - h
        return CGRect(x: appKitX, y: cgY, width: w, height: h)
    }

    // MARK: - Zone Detection

    /// Returns the registry zone whose center is nearest to `cgPoint` on `screen`,
    /// along with its index in the zone array.
    func nearestZone(to cgPoint: CGPoint, on screen: NSScreen) -> (index: Int, zone: WindowPosition)? {
        let zones = zoneRegistry.zones(for: screen)
        guard !zones.isEmpty else { return nil }

        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude

        for (i, zone) in zones.enumerated() {
            let frame = frameForCell(zone.cell, on: screen)  // CG coords
            let cx = frame.midX
            let cy = frame.midY
            let dx = cgPoint.x - cx
            let dy = cgPoint.y - cy
            let dist = dx * dx + dy * dy  // squared distance is fine for comparison
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }

        return (bestIdx, zones[bestIdx])
    }

    /// Returns the index of the horizontal zone whose center x is nearest to `cgPoint.x`.
    /// Among zones with the same center distance, prefers the smallest (by colSpan).
    func nearestHorizontalZone(to cgPoint: CGPoint, on screen: NSScreen) -> Int? {
        let zones = horizontalZoneRegistry.zones(for: screen)
        guard !zones.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestSpan = Int.max
        for (i, zone) in zones.enumerated() {
            let frame = frameForCell(zone.cell, on: screen)
            let dist = abs(cgPoint.x - frame.midX)
            if dist < bestDist - 1.0 {
                bestDist = dist; bestIdx = i; bestSpan = zone.cell.colSpan
            } else if dist < bestDist + 1.0 && zone.cell.colSpan < bestSpan {
                bestDist = dist; bestIdx = i; bestSpan = zone.cell.colSpan
            }
        }
        return bestIdx
    }

    /// Returns indices of horizontal zones sharing the same center X as zone at `index`,
    /// sorted by colSpan ascending (smallest first).
    func horizontalOverlapGroup(at index: Int, on screen: NSScreen) -> [Int] {
        let zones = horizontalZoneRegistry.zones(for: screen)
        guard index < zones.count else { return [] }
        let refFrame = frameForCell(zones[index].cell, on: screen)
        let refCenterX = refFrame.midX
        var group: [(idx: Int, span: Int)] = []
        for (i, zone) in zones.enumerated() {
            let frame = frameForCell(zone.cell, on: screen)
            if abs(frame.midX - refCenterX) < 1.0 {
                group.append((i, zone.cell.colSpan))
            }
        }
        group.sort { $0.span < $1.span }
        return group.map { $0.idx }
    }

    /// Returns the index of the vertical zone whose center y is nearest to `cgPoint.y`.
    func nearestVerticalZone(to cgPoint: CGPoint, on screen: NSScreen) -> Int? {
        let zones = verticalZoneRegistry.zones(for: screen)
        guard !zones.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, zone) in zones.enumerated() {
            let frame = frameForCell(zone.cell, on: screen)
            let dist = abs(cgPoint.y - frame.midY)
            if dist < bestDist { bestDist = dist; bestIdx = i }
        }
        return bestIdx
    }

    func screenFor(window: AXUIElement) -> NSScreen? {
        guard let frame = getWindowFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screenContaining(cgPoint: center)
    }
}
