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

let fullScreenZone = WindowPosition(
    name: "Full Screen",
    cell: GridCell(col: 0, row: 0, colSpan: 12, rowSpan: 6)
)

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

let zoneRegistry = ZoneRegistry(
    defaultZones: [
        WindowPosition(name: "Left Third",   cell: GridCell(col: 0, row: 0, colSpan: 4, rowSpan: 6)),
        WindowPosition(name: "Left Half",    cell: GridCell(col: 0, row: 0, colSpan: 6, rowSpan: 6)),
        WindowPosition(name: "Left 2/3",     cell: GridCell(col: 0, row: 0, colSpan: 8, rowSpan: 6)),
        WindowPosition(name: "Middle Third", cell: GridCell(col: 4, row: 0, colSpan: 4, rowSpan: 6)),
        WindowPosition(name: "Right 2/3",    cell: GridCell(col: 4, row: 0, colSpan: 8, rowSpan: 6)),
        WindowPosition(name: "Right Half",   cell: GridCell(col: 6, row: 0, colSpan: 6, rowSpan: 6)),
        WindowPosition(name: "Right Third",  cell: GridCell(col: 8, row: 0, colSpan: 4, rowSpan: 6)),
    ],
    resolutionOverrides: [
        ScreenResolution(width: 5120, height: 1440): [
            WindowPosition(name: "Left 1/4",   cell: GridCell(col: 0, row: 0, colSpan: 3, rowSpan: 6)),
            WindowPosition(name: "Left 1/3",   cell: GridCell(col: 0, row: 0, colSpan: 4, rowSpan: 6)),
            WindowPosition(name: "Left 1/2",   cell: GridCell(col: 0, row: 0, colSpan: 6, rowSpan: 6)),
            WindowPosition(name: "Left 2/3",   cell: GridCell(col: 0, row: 0, colSpan: 8, rowSpan: 6)),
            WindowPosition(name: "Middle 1/3", cell: GridCell(col: 4, row: 0, colSpan: 4, rowSpan: 6)),
            WindowPosition(name: "Middle 1/2", cell: GridCell(col: 3, row: 0, colSpan: 6, rowSpan: 6)),
            WindowPosition(name: "Right 2/3",  cell: GridCell(col: 4, row: 0, colSpan: 8, rowSpan: 6)),
            WindowPosition(name: "Right 1/2",  cell: GridCell(col: 6, row: 0, colSpan: 6, rowSpan: 6)),
            WindowPosition(name: "Right 1/3",  cell: GridCell(col: 8, row: 0, colSpan: 4, rowSpan: 6)),
            WindowPosition(name: "Right 1/4",  cell: GridCell(col: 9, row: 0, colSpan: 3, rowSpan: 6)),
        ],
    ]
)
