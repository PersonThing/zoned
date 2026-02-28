import Foundation
import CoreGraphics

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

// Predefined snap positions, also used for the cycle hotkey (⌃⌥Space)
let predefinedPositions: [WindowPosition] = [
    WindowPosition(name: "Left Half",       cell: GridCell(col: 0,  row: 0, colSpan: 6,  rowSpan: 6)),
    WindowPosition(name: "Right Half",      cell: GridCell(col: 6,  row: 0, colSpan: 6,  rowSpan: 6)),
    WindowPosition(name: "Full Screen",     cell: GridCell(col: 0,  row: 0, colSpan: 12, rowSpan: 6)),
    WindowPosition(name: "Top Left",        cell: GridCell(col: 0,  row: 0, colSpan: 6,  rowSpan: 3)),
    WindowPosition(name: "Top Right",       cell: GridCell(col: 6,  row: 0, colSpan: 6,  rowSpan: 3)),
    WindowPosition(name: "Bottom Left",     cell: GridCell(col: 0,  row: 3, colSpan: 6,  rowSpan: 3)),
    WindowPosition(name: "Bottom Right",    cell: GridCell(col: 6,  row: 3, colSpan: 6,  rowSpan: 3)),
    WindowPosition(name: "Left Third",      cell: GridCell(col: 0,  row: 0, colSpan: 4,  rowSpan: 6)),
    WindowPosition(name: "Center Third",    cell: GridCell(col: 4,  row: 0, colSpan: 4,  rowSpan: 6)),
    WindowPosition(name: "Right Third",     cell: GridCell(col: 8,  row: 0, colSpan: 4,  rowSpan: 6)),
    WindowPosition(name: "Left ⅔",         cell: GridCell(col: 0,  row: 0, colSpan: 8,  rowSpan: 6)),
    WindowPosition(name: "Right ⅔",        cell: GridCell(col: 4,  row: 0, colSpan: 8,  rowSpan: 6)),
    WindowPosition(name: "Top Half",        cell: GridCell(col: 0,  row: 0, colSpan: 12, rowSpan: 3)),
    WindowPosition(name: "Bottom Half",     cell: GridCell(col: 0,  row: 3, colSpan: 12, rowSpan: 3)),
    WindowPosition(name: "Center",          cell: GridCell(col: 2,  row: 1, colSpan: 8,  rowSpan: 4)),
]
