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

    func normalizedPosition(cgPoint: CGPoint, on screen: NSScreen) -> CGPoint? {
        let appKitPoint = cgToAppKit(cgPoint)
        let vf = screen.visibleFrame
        guard vf.contains(appKitPoint) else { return nil }
        let nx = (appKitPoint.x - vf.minX) / vf.width
        let ny = (appKitPoint.y - vf.minY) / vf.height
        return CGPoint(x: nx, y: ny)
    }

    // Convert a GridCell on a screen to a CG/AX frame rect.
    func frameForCell(_ cell: GridCell, on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let cellW = vf.width  / CGFloat(GRID_COLS)
        let cellH = vf.height / CGFloat(GRID_ROWS)

        let appKitX = vf.minX + CGFloat(cell.col) * cellW
        let appKitY = vf.minY + CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
        let w = CGFloat(cell.colSpan) * cellW
        let h = CGFloat(cell.rowSpan) * cellH

        let cgY = mainScreenHeight - appKitY - h
        return CGRect(x: appKitX, y: cgY, width: w, height: h)
    }

    // MARK: - Zone Detection (LayoutStore-backed)

    /// Returns the index into the layout's sorted zones whose center is nearest to `cgPoint`.
    /// Among equidistant zones, prefers the smallest (by area).
    func nearestZone(to cgPoint: CGPoint, on screen: NSScreen) -> Int? {
        let layout = LayoutStore.shared.activeLayout(for: screen)
        let zones = layout.sortedZones
        guard !zones.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestArea = Int.max
        for (i, zone) in zones.enumerated() {
            let cell = GridCell(col: zone.col, row: zone.row, colSpan: zone.colSpan, rowSpan: zone.rowSpan)
            let frame = frameForCell(cell, on: screen)
            let dx = cgPoint.x - frame.midX
            let dy = cgPoint.y - frame.midY
            let dist = sqrt(dx * dx + dy * dy)
            let area = zone.colSpan * zone.rowSpan
            if dist < bestDist - 1.0 {
                bestDist = dist; bestIdx = i; bestArea = area
            } else if dist < bestDist + 1.0 && area < bestArea {
                bestDist = dist; bestIdx = i; bestArea = area
            }
        }
        return bestIdx
    }

    /// Returns indices of sorted zones that overlap the same cursor position,
    /// sorted by area ascending (smallest first). Used for F-key cycling during drag.
    func overlapGroup(at index: Int, on screen: NSScreen) -> [Int] {
        let layout = LayoutStore.shared.activeLayout(for: screen)
        let zones = layout.sortedZones
        guard index < zones.count else { return [] }
        let ref = zones[index]
        let refCell = GridCell(col: ref.col, row: ref.row, colSpan: ref.colSpan, rowSpan: ref.rowSpan)
        let refFrame = frameForCell(refCell, on: screen)
        let refCenter = CGPoint(x: refFrame.midX, y: refFrame.midY)

        var group: [(idx: Int, area: Int)] = []
        for (i, zone) in zones.enumerated() {
            let cell = GridCell(col: zone.col, row: zone.row, colSpan: zone.colSpan, rowSpan: zone.rowSpan)
            let frame = frameForCell(cell, on: screen)
            // Zone overlaps if it contains the reference center point
            if frame.contains(refCenter) {
                group.append((i, zone.colSpan * zone.rowSpan))
            }
        }
        group.sort { $0.area < $1.area }
        return group.map { $0.idx }
    }

    func screenFor(window: AXUIElement) -> NSScreen? {
        guard let frame = getWindowFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screenContaining(cgPoint: center)
    }
}
