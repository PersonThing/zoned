import AppKit

let GRID_COLS = 12
let GRID_ROWS = 6

struct GridCell {
    var col: Int      // 0-indexed, 0 = leftmost column
    var row: Int      // 0-indexed, 0 = topmost row
    var colSpan: Int
    var rowSpan: Int
}

struct WindowPosition: Equatable {
    var name: String
    var cell: GridCell

    static func == (lhs: WindowPosition, rhs: WindowPosition) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Per-Resolution Zone Registry

struct ScreenResolution: Hashable {
    let width: Int
    let height: Int
}

struct ZoneRegistry {
    let defaultZones: [WindowPosition]
    let resolutionOverrides: [ScreenResolution: [WindowPosition]]

    func zones(for screen: NSScreen) -> [WindowPosition] {
        let pw = Int(screen.frame.width * screen.backingScaleFactor)
        let ph = Int(screen.frame.height * screen.backingScaleFactor)
        let res = ScreenResolution(width: pw, height: ph)
        return resolutionOverrides[res] ?? defaultZones
    }
}

// Horizontal zones — cycled with ⌃⌥← / ⌃⌥→
// Only col/colSpan matter; row/rowSpan is preserved from the current vertical state.
let horizontalZoneRegistry = ZoneRegistry(
    defaultZones: [
        WindowPosition(name: "Left Third",  cell: GridCell(col: 0, row: 0, colSpan: 4, rowSpan: 6)),
        WindowPosition(name: "Left Half",   cell: GridCell(col: 0, row: 0, colSpan: 6, rowSpan: 6)),
        WindowPosition(name: "Left 2/3",    cell: GridCell(col: 0, row: 0, colSpan: 8, rowSpan: 6)),
        WindowPosition(name: "Full Width",  cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6)),
        WindowPosition(name: "Right 2/3",   cell: GridCell(col: 4, row: 0, colSpan: 8, rowSpan: 6)),
        WindowPosition(name: "Right Half",  cell: GridCell(col: 6, row: 0, colSpan: 6, rowSpan: 6)),
        WindowPosition(name: "Right Third", cell: GridCell(col: 8, row: 0, colSpan: 4, rowSpan: 6)),
    ],
    resolutionOverrides: [
        ScreenResolution(width: 5120, height: 1440): [
            WindowPosition(name: "Left 1/4",  cell: GridCell(col: 0, row: 0, colSpan: 3, rowSpan: 6)),
            WindowPosition(name: "Left 1/3",  cell: GridCell(col: 0, row: 0, colSpan: 4, rowSpan: 6)),
            WindowPosition(name: "Left 1/2",  cell: GridCell(col: 0, row: 0, colSpan: 6, rowSpan: 6)),
            WindowPosition(name: "Left 2/3",  cell: GridCell(col: 0, row: 0, colSpan: 8, rowSpan: 6)),
            WindowPosition(name: "Full Width", cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6)),
            WindowPosition(name: "Right 2/3", cell: GridCell(col: 4, row: 0, colSpan: 8, rowSpan: 6)),
            WindowPosition(name: "Right 1/2", cell: GridCell(col: 6, row: 0, colSpan: 6, rowSpan: 6)),
            WindowPosition(name: "Right 1/3", cell: GridCell(col: 8, row: 0, colSpan: 4, rowSpan: 6)),
            WindowPosition(name: "Right 1/4", cell: GridCell(col: 9, row: 0, colSpan: 3, rowSpan: 6)),
        ],
    ]
)

// Vertical zones — cycled with ⌃⌥↑ / ⌃⌥↓
// Only row/rowSpan matter; col/colSpan is preserved from the current horizontal state.
let verticalZoneRegistry = ZoneRegistry(
    defaultZones: [
        WindowPosition(name: "Top 1/3",      cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 2)),
        WindowPosition(name: "Top 1/2",      cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 3)),
        WindowPosition(name: "Top 2/3",      cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 4)),
        WindowPosition(name: "Full Height",  cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6)),
        WindowPosition(name: "Bottom 2/3",   cell: GridCell(col: 0, row: 2, colSpan: 12, rowSpan: 4)),
        WindowPosition(name: "Bottom 1/2",   cell: GridCell(col: 0, row: 3, colSpan: 12, rowSpan: 3)),
        WindowPosition(name: "Bottom 1/3",   cell: GridCell(col: 0, row: 4, colSpan: 12, rowSpan: 2)),
    ],
    resolutionOverrides: [:]
)

// Combined: used for the overlay preview and shift+drag nearest-zone matching.
let zoneRegistry = ZoneRegistry(
    defaultZones: horizontalZoneRegistry.defaultZones + verticalZoneRegistry.defaultZones,
    resolutionOverrides: {
        var merged: [ScreenResolution: [WindowPosition]] = [:]
        for (res, zones) in horizontalZoneRegistry.resolutionOverrides {
            merged[res] = zones + verticalZoneRegistry.defaultZones
        }
        return merged
    }()
)
