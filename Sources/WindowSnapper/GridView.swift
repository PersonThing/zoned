import AppKit

// NSView that renders the grid overlay on one screen.
// Coordinate note: NSView uses AppKit coords (y-up). The view's bounds map to
// screen.frame (AppKit). Cells are drawn within screen.visibleFrame (AppKit).
class GridView: NSView {

    var highlightedPosition: WindowPosition?
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
        // row 0 = topmost. AppKit y increases upward, so the topmost row has the largest y.
        let x = vfv.minX + CGFloat(cell.col) * cellW
        let y = vfv.minY + CGFloat(GRID_ROWS - cell.row - cell.rowSpan) * cellH
        let w = CGFloat(cell.colSpan) * cellW
        let h = CGFloat(cell.rowSpan) * cellH
        return NSRect(x: x, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // ── Semi-transparent background ──────────────────────────────────────
        NSColor(white: 0, alpha: 0.38).setFill()
        bounds.fill()

        let vfv  = visibleFrameInView
        let cellW = vfv.width  / CGFloat(GRID_COLS)
        let cellH = vfv.height / CGFloat(GRID_ROWS)

        // ── Grid cells ───────────────────────────────────────────────────────
        for row in 0..<GRID_ROWS {
            for col in 0..<GRID_COLS {
                let x = vfv.minX + CGFloat(col) * cellW
                let y = vfv.minY + CGFloat(row) * cellH
                let cellRect = NSRect(x: x, y: y, width: cellW, height: cellH)

                // Subtle cell fill
                NSColor(white: 1, alpha: 0.05).setFill()
                cellRect.insetBy(dx: 1, dy: 1).fill()

                // Cell border
                NSColor(white: 1, alpha: 0.12).setStroke()
                let border = NSBezierPath(rect: cellRect)
                border.lineWidth = 0.5
                border.stroke()
            }
        }

        // ── Highlighted snap zone ────────────────────────────────────────────
        if let pos = highlightedPosition {
            let rect = rectForCell(pos.cell)
            let inset = rect.insetBy(dx: 3, dy: 3)

            // Glow fill
            NSColor(red: 0.10, green: 0.55, blue: 1.0, alpha: 0.38).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8).fill()

            // Border
            NSColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 0.95).setStroke()
            let borderPath = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
            borderPath.lineWidth = 2.5
            borderPath.stroke()

            // Zone name label
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = NSSize(width: 0, height: -1)

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: max(14, rect.height * 0.18), weight: .semibold),
                .shadow: shadow,
            ]
            let str = pos.name as NSString
            let strSize = str.size(withAttributes: attrs)
            let labelPt = NSPoint(
                x: rect.midX - strSize.width  / 2,
                y: rect.midY - strSize.height / 2
            )
            str.draw(at: labelPt, withAttributes: attrs)
        }

        // ── Column numbers (top edge) ────────────────────────────────────────
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 1, alpha: 0.35),
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
        ]
        for col in 0..<GRID_COLS {
            let label = "\(col + 1)" as NSString
            let x = vfv.minX + CGFloat(col) * cellW + cellW / 2 - 4
            let y = vfv.maxY - 13
            label.draw(at: NSPoint(x: x, y: y), withAttributes: labelAttrs)
        }

        // ── Row numbers (left edge) ──────────────────────────────────────────
        for modelRow in 0..<GRID_ROWS {
            // modelRow 0 = top → highest y in view
            let label = "\(modelRow + 1)" as NSString
            let centerY = vfv.minY + CGFloat(GRID_ROWS - modelRow - 1) * cellH + cellH / 2 - 5
            label.draw(at: NSPoint(x: vfv.minX + 4, y: centerY), withAttributes: labelAttrs)
        }
    }
}
