import AppKit

// NSView that renders the zone layout in miniature.
// The entire view bounds represent the screen's visible area, scaled down.
class GridView: NSView {

    var zones: [WindowPosition] = []
    var highlightedIndex: Int? = nil      // index into zones[]

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    // Convert a GridCell to a rect within the view bounds.
    func rectForCell(_ cell: GridCell) -> NSRect {
        let cellW = bounds.width  / CGFloat(GRID_COLS)
        let cellH = bounds.height / CGFloat(GRID_ROWS)
        let x = CGFloat(cell.col) * cellW
        let y = CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
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

        // ── Background ─────────────────────────────────────────────────────
        NSColor(white: 0.1, alpha: 0.85).setFill()
        bounds.fill()

        guard !zones.isEmpty else { return }

        let insetPx: CGFloat = 2

        // ── Draw each zone ──────────────────────────────────────────────────
        for (i, zone) in zones.enumerated() {
            let rect = rectForCell(zone.cell)
            let inset = rect.insetBy(dx: insetPx, dy: insetPx)
            let isActive = (highlightedIndex == i)
            let color = GridView.zoneColors[i % GridView.zoneColors.count]
            let cornerR: CGFloat = 4

            // Fill
            let fillAlpha: CGFloat = isActive ? 0.50 : 0.15
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: inset, xRadius: cornerR, yRadius: cornerR).fill()

            // Border
            let borderAlpha: CGFloat = isActive ? 0.95 : 0.45
            let borderWidth: CGFloat = isActive ? 2.0 : 1.0
            color.withAlphaComponent(borderAlpha).setStroke()
            let borderPath = NSBezierPath(roundedRect: inset, xRadius: cornerR, yRadius: cornerR)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()

            // ── Label: zone number ──────────────────────────────────────────
            let fontSize: CGFloat = max(9, min(rect.height * 0.35, 14))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 1.0 : 0.6),
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            ]
            let numStr = "\(i + 1)" as NSString
            let numSize = numStr.size(withAttributes: attrs)
            numStr.draw(at: NSPoint(
                x: rect.midX - numSize.width / 2,
                y: rect.midY - numSize.height / 2
            ), withAttributes: attrs)
        }
    }
}
