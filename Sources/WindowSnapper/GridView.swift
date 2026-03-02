import AppKit

// NSView that renders zone layout in miniature.
// Shows all zones and highlights the active one.
class GridView: NSView {

    var layout: ZoneLayout?
    var activeZoneIndex: Int? = nil
    var isFullScreen: Bool = false

    static let instructionHeight: CGFloat = 18

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    private var effectiveInstructionHeight: CGFloat {
        isFullScreen ? 36 : Self.instructionHeight
    }

    /// The portion of the view reserved for the grid miniature (above instructions).
    private var gridBounds: NSRect {
        let ih = effectiveInstructionHeight
        return NSRect(x: 0, y: ih,
                      width: bounds.width, height: bounds.height - ih)
    }

    /// Convert a GridCell to a rect within `area`.
    private func rectForCell(_ cell: GridCell, in area: NSRect) -> NSRect {
        let cellW = area.width  / CGFloat(GRID_COLS)
        let cellH = area.height / CGFloat(GRID_ROWS)
        let x = area.minX + CGFloat(cell.col) * cellW
        let y = area.minY + CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
        let w = CGFloat(cell.colSpan) * cellW
        let h = CGFloat(cell.rowSpan) * cellH
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // Muted color palette for zones.
    static let zoneColors: [NSColor] = [
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
        let bgAlpha: CGFloat = isFullScreen ? 0.55 : 0.85
        NSColor(white: 0.1, alpha: bgAlpha).setFill()
        bounds.fill()

        let gb = gridBounds
        guard let layout = layout else { return }
        let zones = layout.sortedZones
        guard !zones.isEmpty else { return }

        let insetPx: CGFloat = isFullScreen ? 4 : 1.5
        let cornerR: CGFloat = isFullScreen ? 8 : 3

        // ── Zones ────────────────────────────────────────────────────────
        for (i, zone) in zones.enumerated() {
            let isActive = (activeZoneIndex == i)
            let cell = GridCell(col: zone.col, row: zone.row, colSpan: zone.colSpan, rowSpan: zone.rowSpan)
            let rect = rectForCell(cell, in: gb)
            let inset = rect.insetBy(dx: insetPx, dy: insetPx)
            let color = Self.zoneColors[i % Self.zoneColors.count]

            // Fill
            let fillAlpha: CGFloat = isActive ? 0.35 : 0.10
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: inset, xRadius: cornerR, yRadius: cornerR).fill()

            // Border
            let borderAlpha: CGFloat = isActive ? 0.90 : 0.35
            let borderWidth: CGFloat = isActive ? 2.0 : 0.75
            color.withAlphaComponent(borderAlpha).setStroke()
            let bp = NSBezierPath(roundedRect: inset, xRadius: cornerR, yRadius: cornerR)
            bp.lineWidth = borderWidth
            bp.stroke()
        }

        // ── Instructions ───────────────────────────────────────────────────
        let ih = effectiveInstructionHeight
        let s = KeyBindingSettings.shared
        let text = "\(s.cyclingModifier.displayString) ←→ zones · [] layouts · \(s.dragModifier.displayString)+drag snap" as NSString
        let fontSize: CGFloat = max(7, ih * 0.55)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: (ih - size.height) / 2
        ), withAttributes: attrs)
    }
}
