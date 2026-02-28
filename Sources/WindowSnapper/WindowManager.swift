import AppKit
import ApplicationServices

class WindowManager {

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
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp
        else { return nil }
        var focusedWindow: AnyObject?
        AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard let w = focusedWindow else { return nil }
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

    // Given a normalised cursor position on a screen, return the best predefined snap zone.
    // np.x: 0=left, 1=right
    // np.y: 0=bottom, 1=top  (AppKit y-up)
    func snapZone(forNormalized np: CGPoint) -> WindowPosition {
        let nx = np.x
        let ny = np.y

        // Centre region → Full Screen
        let inCenterX = nx > 0.30 && nx < 0.70
        let inCenterY = ny > 0.30 && ny < 0.70
        if inCenterX && inCenterY {
            return WindowPosition(name: "Full Screen", cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6))
        }

        let isLeft  = nx <= 0.5
        let isRight = nx >  0.5
        let isTop    = ny >  0.5   // AppKit: large y = top
        let isBottom = ny <= 0.5

        let inLeftEdge   = nx < 0.25
        let inRightEdge  = nx > 0.75
        let inTopEdge    = ny > 0.75
        let inBottomEdge = ny < 0.25

        // Corner zones (edge strips)
        if inLeftEdge  && inTopEdge    { return WindowPosition(name: "Top Left",     cell: GridCell(col: 0, row: 0, colSpan: 6, rowSpan: 3)) }
        if inRightEdge && inTopEdge    { return WindowPosition(name: "Top Right",    cell: GridCell(col: 6, row: 0, colSpan: 6, rowSpan: 3)) }
        if inLeftEdge  && inBottomEdge { return WindowPosition(name: "Bottom Left",  cell: GridCell(col: 0, row: 3, colSpan: 6, rowSpan: 3)) }
        if inRightEdge && inBottomEdge { return WindowPosition(name: "Bottom Right", cell: GridCell(col: 6, row: 3, colSpan: 6, rowSpan: 3)) }

        // Half zones
        if isLeft  && !inCenterX { return WindowPosition(name: "Left Half",   cell: GridCell(col: 0, row: 0, colSpan: 6,  rowSpan: 6)) }
        if isRight && !inCenterX { return WindowPosition(name: "Right Half",  cell: GridCell(col: 6, row: 0, colSpan: 6,  rowSpan: 6)) }
        if isTop   && !inCenterY { return WindowPosition(name: "Top Half",    cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 3)) }
        if isBottom && !inCenterY { return WindowPosition(name: "Bottom Half", cell: GridCell(col: 0, row: 3, colSpan: 12, rowSpan: 3)) }

        return WindowPosition(name: "Full Screen", cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6))
    }

    func screenFor(window: AXUIElement) -> NSScreen? {
        guard let frame = getWindowFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screenContaining(cgPoint: center)
    }
}
