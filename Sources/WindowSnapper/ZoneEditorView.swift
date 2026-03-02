import AppKit

/// Interactive NSView for editing zones on a 12×6 grid.
/// Supports creating, selecting, moving, resizing, and deleting zones.
class ZoneEditorView: NSView {

    var layout: ZoneLayout = ZoneLayout(name: "", zones: []) {
        didSet { needsDisplay = true }
    }
    var onLayoutChanged: ((ZoneLayout) -> Void)?

    var selectedZoneID: UUID? = nil {
        didSet { needsDisplay = true }
    }
    var onSelectionChanged: (() -> Void)?

    // Drag state
    private enum DragMode {
        case none
        case creating(startCol: Int, startRow: Int)
        case moving(zoneID: UUID,
                     origCol: Int, origColSpan: Int,
                     origRow: Int, origRowSpan: Int,
                     startCol: Int, startRow: Int)
        case resizingLeft(zoneID: UUID)
        case resizingRight(zoneID: UUID)
        case resizingTop(zoneID: UUID)
        case resizingBottom(zoneID: UUID)
    }
    private var dragMode: DragMode = .none
    private var dragCurrentCol: Int = 0
    private var dragCurrentRow: Int = 0

    private let gridPadding: CGFloat = 8
    private let edgeHitSize: CGFloat = 7

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }  // top-left origin matches grid model

    // MARK: - Grid Geometry

    private var gridBounds: NSRect {
        return NSRect(x: gridPadding, y: gridPadding,
                      width: bounds.width - gridPadding * 2,
                      height: bounds.height - gridPadding * 2)
    }

    private var cellWidth: CGFloat { gridBounds.width / CGFloat(GRID_COLS) }
    private var cellHeight: CGFloat { gridBounds.height / CGFloat(GRID_ROWS) }

    private func colFromX(_ x: CGFloat) -> Int {
        let col = Int((x - gridBounds.minX) / cellWidth)
        return max(0, min(col, GRID_COLS - 1))
    }

    private func rowFromY(_ y: CGFloat) -> Int {
        let row = Int((y - gridBounds.minY) / cellHeight)
        return max(0, min(row, GRID_ROWS - 1))
    }

    private func rectForZone(_ zone: Zone) -> NSRect {
        let gb = gridBounds
        let x = gb.minX + CGFloat(zone.col) * cellWidth
        let y = gb.minY + CGFloat(zone.row) * cellHeight
        let w = CGFloat(zone.colSpan) * cellWidth
        let h = CGFloat(zone.rowSpan) * cellHeight
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Edge Hit Testing

    private enum Edge {
        case left, right, top, bottom
    }

    /// Returns the edge and zone ID if `loc` is near a zone edge.
    /// Prefers the selected zone, then smallest area.
    private func edgeHit(at loc: NSPoint) -> (zone: Zone, edge: Edge)? {
        let zones = layout.sortedZones
        // Check selected zone first, then others
        let ordered: [Zone]
        if let selID = selectedZoneID, let sel = zones.first(where: { $0.id == selID }) {
            ordered = [sel] + zones.filter { $0.id != selID }
        } else {
            ordered = zones
        }

        for zone in ordered {
            let r = rectForZone(zone)
            let h = edgeHitSize

            // Top edge
            if abs(loc.y - r.minY) < h && loc.x >= r.minX - h && loc.x <= r.maxX + h {
                return (zone, .top)
            }
            // Bottom edge
            if abs(loc.y - r.maxY) < h && loc.x >= r.minX - h && loc.x <= r.maxX + h {
                return (zone, .bottom)
            }
            // Left edge
            if abs(loc.x - r.minX) < h && loc.y >= r.minY - h && loc.y <= r.maxY + h {
                return (zone, .left)
            }
            // Right edge
            if abs(loc.x - r.maxX) < h && loc.y >= r.minY - h && loc.y <= r.maxY + h {
                return (zone, .right)
            }
        }
        return nil
    }

    private func cursorForEdge(_ edge: Edge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        }
    }

    // MARK: - Cursor Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if let hit = edgeHit(at: loc) {
            cursorForEdge(hit.edge).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gb = gridBounds

        // Background
        NSColor(white: 0.15, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: gb, xRadius: 4, yRadius: 4).fill()

        // Grid lines
        NSColor.white.withAlphaComponent(0.08).setStroke()
        for col in 0...GRID_COLS {
            let x = gb.minX + CGFloat(col) * cellWidth
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: gb.minY))
            path.line(to: NSPoint(x: x, y: gb.maxY))
            path.lineWidth = 0.5
            path.stroke()
        }
        for row in 0...GRID_ROWS {
            let y = gb.minY + CGFloat(row) * cellHeight
            let path = NSBezierPath()
            path.move(to: NSPoint(x: gb.minX, y: y))
            path.line(to: NSPoint(x: gb.maxX, y: y))
            path.lineWidth = 0.5
            path.stroke()
        }

        let zones = layout.sortedZones

        // Draw zones
        for (i, zone) in zones.enumerated() {
            let isSelected = (zone.id == selectedZoneID)
            let rect = rectForZone(zone).insetBy(dx: 1.5, dy: 1.5)
            let color = GridView.zoneColors[i % GridView.zoneColors.count]

            // Fill
            let fillAlpha: CGFloat = isSelected ? 0.30 : 0.12
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()

            // Border
            let borderAlpha: CGFloat = isSelected ? 0.90 : 0.40
            let borderWidth: CGFloat = isSelected ? 2.0 : 0.75
            color.withAlphaComponent(borderAlpha).setStroke()
            let bp = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            bp.lineWidth = borderWidth
            bp.stroke()

            // Zone name
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color.withAlphaComponent(isSelected ? 0.9 : 0.5),
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            ]
            let name = zone.name as NSString
            let nameSize = name.size(withAttributes: nameAttrs)
            if nameSize.width < rect.width - 4 && nameSize.height < rect.height - 2 {
                name.draw(at: NSPoint(
                    x: rect.midX - nameSize.width / 2,
                    y: rect.midY - nameSize.height / 2
                ), withAttributes: nameAttrs)
            }
        }

        // Draw drag preview
        drawDragPreview(in: gb)
    }

    private func drawDragPreview(in gb: NSRect) {
        switch dragMode {
        case .creating(let startCol, let startRow):
            let minCol = min(startCol, dragCurrentCol)
            let maxCol = max(startCol, dragCurrentCol)
            let minRow = min(startRow, dragCurrentRow)
            let maxRow = max(startRow, dragCurrentRow)
            let colSpan = maxCol - minCol + 1
            let rowSpan = maxRow - minRow + 1
            let x = gb.minX + CGFloat(minCol) * cellWidth
            let w = CGFloat(colSpan) * cellWidth
            let y = gb.minY + CGFloat(minRow) * cellHeight
            let h = CGFloat(rowSpan) * cellHeight
            let rect = NSRect(x: x, y: y, width: w, height: h).insetBy(dx: 1.5, dy: 1.5)
            NSColor.white.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let bp = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            bp.lineWidth = 1.5
            bp.setLineDash([4, 3], count: 2, phase: 0)
            bp.stroke()

        default:
            break
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let loc = convert(event.locationInWindow, from: nil)
        let col = colFromX(loc.x)
        let row = rowFromY(loc.y)

        guard gridBounds.contains(loc) else { return }

        // 1. Check resize handles on zone edges
        if let hit = edgeHit(at: loc) {
            selectedZoneID = hit.zone.id
            onSelectionChanged?()
            switch hit.edge {
            case .top:    dragMode = .resizingTop(zoneID: hit.zone.id); dragCurrentRow = row
            case .bottom: dragMode = .resizingBottom(zoneID: hit.zone.id); dragCurrentRow = row
            case .left:   dragMode = .resizingLeft(zoneID: hit.zone.id); dragCurrentCol = col
            case .right:  dragMode = .resizingRight(zoneID: hit.zone.id); dragCurrentCol = col
            }
            return
        }

        let zones = layout.sortedZones

        // 2. Click on a zone → select + move (prefer smallest area)
        var bestZone: Zone? = nil
        var bestArea = Int.max
        for zone in zones {
            let zRect = rectForZone(zone)
            let area = zone.colSpan * zone.rowSpan
            if zRect.contains(loc) && area < bestArea {
                bestZone = zone
                bestArea = area
            }
        }
        if let zone = bestZone {
            selectedZoneID = zone.id
            onSelectionChanged?()
            dragMode = .moving(
                zoneID: zone.id,
                origCol: zone.col, origColSpan: zone.colSpan,
                origRow: zone.row, origRowSpan: zone.rowSpan,
                startCol: col, startRow: row
            )
            return
        }

        // 3. Empty space → start creating a new zone rectangle
        selectedZoneID = nil
        onSelectionChanged?()
        dragMode = .creating(startCol: col, startRow: row)
        dragCurrentCol = col
        dragCurrentRow = row
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let col = colFromX(loc.x)
        let row = rowFromY(loc.y)

        switch dragMode {
        case .creating:
            dragCurrentCol = col
            dragCurrentRow = row
            needsDisplay = true

        case .moving(let zoneID, let origCol, let origColSpan, let origRow, let origRowSpan, let startCol, let startRow):
            let deltaCol = col - startCol
            let deltaRow = row - startRow

            if let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) {
                let newCol = max(0, min(origCol + deltaCol, GRID_COLS - origColSpan))
                let newRow = max(0, min(origRow + deltaRow, GRID_ROWS - origRowSpan))
                layout.zones[idx].col = newCol
                layout.zones[idx].row = newRow
                layout.zones[idx].name = autoName(col: newCol, colSpan: origColSpan, row: newRow, rowSpan: origRowSpan)
            }
            needsDisplay = true

        case .resizingLeft(let zoneID):
            guard let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) else { return }
            let zone = layout.zones[idx]
            let rightEdge = zone.col + zone.colSpan
            let newCol = min(col, rightEdge - 1)
            layout.zones[idx].col = newCol
            layout.zones[idx].colSpan = rightEdge - newCol
            layout.zones[idx].name = autoName(col: newCol, colSpan: rightEdge - newCol, row: zone.row, rowSpan: zone.rowSpan)
            needsDisplay = true

        case .resizingRight(let zoneID):
            guard let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) else { return }
            let zone = layout.zones[idx]
            let newSpan = max(1, col - zone.col + 1)
            let clampedSpan = min(newSpan, GRID_COLS - zone.col)
            layout.zones[idx].colSpan = clampedSpan
            layout.zones[idx].name = autoName(col: zone.col, colSpan: clampedSpan, row: zone.row, rowSpan: zone.rowSpan)
            needsDisplay = true

        case .resizingTop(let zoneID):
            guard let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) else { return }
            let zone = layout.zones[idx]
            let bottomEdge = zone.row + zone.rowSpan
            let newRow = min(row, bottomEdge - 1)
            layout.zones[idx].row = newRow
            layout.zones[idx].rowSpan = bottomEdge - newRow
            layout.zones[idx].name = autoName(col: zone.col, colSpan: zone.colSpan, row: newRow, rowSpan: bottomEdge - newRow)
            needsDisplay = true

        case .resizingBottom(let zoneID):
            guard let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) else { return }
            let zone = layout.zones[idx]
            let newSpan = max(1, row - zone.row + 1)
            let clampedSpan = min(newSpan, GRID_ROWS - zone.row)
            layout.zones[idx].rowSpan = clampedSpan
            layout.zones[idx].name = autoName(col: zone.col, colSpan: zone.colSpan, row: zone.row, rowSpan: clampedSpan)
            needsDisplay = true

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .creating(let startCol, let startRow):
            let minCol = min(startCol, dragCurrentCol)
            let maxCol = max(startCol, dragCurrentCol)
            let minRow = min(startRow, dragCurrentRow)
            let maxRow = max(startRow, dragCurrentRow)
            let colSpan = maxCol - minCol + 1
            let rowSpan = maxRow - minRow + 1
            let name = autoName(col: minCol, colSpan: colSpan, row: minRow, rowSpan: rowSpan)
            let newZone = Zone(name: name, col: minCol, colSpan: colSpan, row: minRow, rowSpan: rowSpan)
            layout.zones.append(newZone)
            selectedZoneID = newZone.id
            onSelectionChanged?()
            onLayoutChanged?(layout)

        case .moving(let zoneID, let origCol, _, let origRow, _, _, _):
            var moved = false
            if let idx = layout.zones.firstIndex(where: { $0.id == zoneID }) {
                if layout.zones[idx].col != origCol || layout.zones[idx].row != origRow {
                    moved = true
                }
            }
            if moved { onLayoutChanged?(layout) }

        case .resizingLeft, .resizingRight, .resizingTop, .resizingBottom:
            onLayoutChanged?(layout)

        case .none:
            break
        }

        dragMode = .none
        NSCursor.arrow.set()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
            deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    func deleteSelected() {
        guard let zoneID = selectedZoneID else { return }
        layout.zones.removeAll { $0.id == zoneID }
        selectedZoneID = nil
        onSelectionChanged?()
        onLayoutChanged?(layout)
        needsDisplay = true
    }

    // MARK: - Auto-naming

    private func autoName(col: Int, colSpan: Int, row: Int, rowSpan: Int) -> String {
        let hPart: String
        if colSpan == GRID_COLS {
            hPart = "Full"
        } else {
            let frac = fractionName(span: colSpan, total: GRID_COLS)
            if col == 0 { hPart = "Left \(frac)" }
            else if col + colSpan == GRID_COLS { hPart = "Right \(frac)" }
            else { hPart = "Mid \(frac)" }
        }

        if rowSpan == GRID_ROWS { return hPart }

        let vFrac = fractionName(span: rowSpan, total: GRID_ROWS)
        let vPart: String
        if row == 0 { vPart = "Top \(vFrac)" }
        else if row + rowSpan == GRID_ROWS { vPart = "Bot \(vFrac)" }
        else { vPart = "Mid \(vFrac)" }

        return "\(hPart) · \(vPart)"
    }

    private func fractionName(span: Int, total: Int) -> String {
        let g = gcd(span, total)
        let num = span / g
        let den = total / g
        if num == 1 { return "1/\(den)" }
        return "\(num)/\(den)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
