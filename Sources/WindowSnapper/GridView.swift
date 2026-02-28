import AppKit

// NSView that renders the zone overlay on one screen.
// Coordinate note: NSView uses AppKit coords (y-up). The view's bounds map to
// screen.frame (AppKit). Cells are drawn within screen.visibleFrame (AppKit).
class GridView: NSView {

    var zones: [WindowPosition] = []
    var highlightedIndex: Int? = nil      // index into zones[]
    var screen: NSScreen?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    // Visible frame expressed in view-local coordinates (view origin = screen.frame.origin).
    private var visibleFrameInView: NSRect {
        guard let screen = screen else { return bounds }
        let sf = screen.frame
        let vf = screen.visibleFrame
        return NSRect(
            x: vf.minX - sf.minX,
            y: vf.minY - sf.minY,
            width: vf.width,
            height: vf.height
        )
    }

    // Convert a GridCell to a rect in view-local coordinates.
    func rectForCell(_ cell: GridCell) -> NSRect {
        let vfv = visibleFrameInView
        let cellW = vfv.width  / CGFloat(GRID_COLS)
        let cellH = vfv.height / CGFloat(GRID_ROWS)
        let x = vfv.minX + CGFloat(cell.col) * cellW
        let y = vfv.minY + CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
        let w = CGFloat(cell.colSpan) * cellW
        let h = CGFloat(cell.rowSpan) * cellH
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // Muted color palette for zones.
    private static let zoneColors: [NSColor] = [
        NSColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1.0),
        NSColor(red: 0.30, green: 0.70, blue: 0.45, alpha: 1.0),
        NSColor(red: 0.75, green: 0.50, blue: 0.20, alpha: 1.0),
        NSColor(red: 0.65, green: 0.30, blue: 0.65, alpha: 1.0),
        NSColor(red: 0.25, green: 0.65, blue: 0.65, alpha: 1.0),
        NSColor(red: 0.80, green: 0.40, blue: 0.40, alpha: 1.0),
        NSColor(red: 0.50, green: 0.60, blue: 0.30, alpha: 1.0),
        NSColor(red: 0.45, green: 0.45, blue: 0.75, alpha: 1.0),
        NSColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1.0),
        NSColor(red: 0.55, green: 0.40, blue: 0.60, alpha: 1.0),
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // ── Semi-transparent background ──────────────────────────────────────
        NSColor(white: 0, alpha: 0.45).setFill()
        bounds.fill()

        guard !zones.isEmpty else { return }

        // ── Draw each zone ──────────────────────────────────────────────────
        for (i, zone) in zones.enumerated() {
            let rect = rectForCell(zone.cell)
            let inset = rect.insetBy(dx: 4, dy: 4)
            let isActive = (highlightedIndex == i)
            let color = GridView.zoneColors[i % GridView.zoneColors.count]

            // Fill
            let fillAlpha: CGFloat = isActive ? 0.40 : 0.15
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8).fill()

            // Border
            let borderAlpha: CGFloat = isActive ? 0.95 : 0.50
            let borderWidth: CGFloat = isActive ? 3.0 : 1.5
            color.withAlphaComponent(borderAlpha).setStroke()
            let borderPath = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()

            // ── Labels ──────────────────────────────────────────────────────

            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.7)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)

            // Order number — large
            let numAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.7),
                .font: NSFont.monospacedDigitSystemFont(ofSize: max(24, rect.height * 0.25), weight: .bold),
                .shadow: shadow,
            ]
            let numStr = "\(i + 1)" as NSString
            let numSize = numStr.size(withAttributes: numAttrs)

            // Zone name — smaller
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 0.95 : 0.6),
                .font: NSFont.systemFont(ofSize: max(11, rect.height * 0.10), weight: .medium),
                .shadow: shadow,
            ]
            let nameStr = zone.name as NSString
            let nameSize = nameStr.size(withAttributes: nameAttrs)

            // Stack number above name, centered
            let totalH = numSize.height + 2 + nameSize.height
            let baseY = rect.midY - totalH / 2

            numStr.draw(at: NSPoint(
                x: rect.midX - numSize.width / 2,
                y: baseY + nameSize.height + 2
            ), withAttributes: numAttrs)

            nameStr.draw(at: NSPoint(
                x: rect.midX - nameSize.width / 2,
                y: baseY
            ), withAttributes: nameAttrs)
        }
    }
}
