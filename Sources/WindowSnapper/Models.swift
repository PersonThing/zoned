import AppKit
import Foundation

let GRID_COLS = 12
let GRID_ROWS = 6

struct GridCell {
    var col: Int      // 0-indexed, 0 = leftmost column
    var row: Int      // 0-indexed, 0 = topmost row
    var colSpan: Int
    var rowSpan: Int
}

// MARK: - Aspect Ratio

struct AspectRatio: Codable, Hashable {
    let width: Int   // simplified ratio, e.g. 16
    let height: Int  // simplified ratio, e.g. 9

    static func fromScreen(_ screen: NSScreen) -> AspectRatio {
        let w = Int(screen.frame.width)
        let h = Int(screen.frame.height)
        let g = gcd(w, h)
        return AspectRatio(width: w / g, height: h / g)
    }

    var displayString: String {
        "\(width):\(height)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

// MARK: - Zone

struct Zone: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var col: Int
    var colSpan: Int
    var row: Int
    var rowSpan: Int

    var centerCol: Double { Double(col) + Double(colSpan) / 2.0 }
    var centerRow: Double { Double(row) + Double(rowSpan) / 2.0 }

    init(id: UUID = UUID(), name: String, col: Int, colSpan: Int, row: Int = 0, rowSpan: Int = GRID_ROWS) {
        self.id = id; self.name = name; self.col = col; self.colSpan = colSpan
        self.row = row; self.rowSpan = rowSpan
    }
}

// MARK: - Zone Layout

struct ZoneLayout: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var aspectRatio: AspectRatio?  // nil = any aspect ratio
    var zones: [Zone]

    init(id: UUID = UUID(), name: String, aspectRatio: AspectRatio? = nil, zones: [Zone]) {
        self.id = id; self.name = name; self.aspectRatio = aspectRatio; self.zones = zones
    }

    /// Sorted zones: left-to-right by center col, top-to-bottom on ties, smallest area first.
    var sortedZones: [Zone] {
        zones.sorted {
            if abs($0.centerCol - $1.centerCol) > 0.01 { return $0.centerCol < $1.centerCol }
            if abs($0.centerRow - $1.centerRow) > 0.01 { return $0.centerRow < $1.centerRow }
            return ($0.colSpan * $0.rowSpan) < ($1.colSpan * $1.rowSpan)
        }
    }
}

// MARK: - Default Layouts

func makeDefaultLayouts() -> [ZoneLayout] {
    let defaultLayout = ZoneLayout(
        name: "Default",
        aspectRatio: nil,
        zones: [
            Zone(name: "Left Third",  col: 0, colSpan: 4),
            Zone(name: "Left Half",   col: 0, colSpan: 6),
            Zone(name: "Left 2/3",    col: 0, colSpan: 8),
            Zone(name: "Full",        col: 0, colSpan: 12),
            Zone(name: "Middle 1/3",  col: 4, colSpan: 4),
            Zone(name: "Right 2/3",   col: 4, colSpan: 8),
            Zone(name: "Right Half",  col: 6, colSpan: 6),
            Zone(name: "Right Third", col: 8, colSpan: 4),
        ]
    )

    let ultrawideLayout = ZoneLayout(
        name: "Ultrawide",
        aspectRatio: AspectRatio(width: 32, height: 9),
        zones: [
            Zone(name: "Left 1/4",   col: 0, colSpan: 3),
            Zone(name: "Left 1/3",   col: 0, colSpan: 4),
            Zone(name: "Left 1/2",   col: 0, colSpan: 6),
            Zone(name: "Left 2/3",   col: 0, colSpan: 8),
            Zone(name: "Full",       col: 0, colSpan: 12),
            Zone(name: "Middle 1/2", col: 3, colSpan: 6),
            Zone(name: "Middle 1/3", col: 4, colSpan: 4),
            Zone(name: "Right 2/3",  col: 4, colSpan: 8),
            Zone(name: "Right 1/2",  col: 6, colSpan: 6),
            Zone(name: "Right 1/3",  col: 8, colSpan: 4),
            Zone(name: "Right 1/4",  col: 9, colSpan: 3),
        ]
    )

    return [defaultLayout, ultrawideLayout]
}
