# WindowSnapper

A minimal macOS window manager — no configuration files, no subscription, no bloat.

Lives in your menu bar. Two interactions, that's it.

---

## Features

### ⇧ Shift + drag → snap to grid
Hold **Shift** while dragging any window title bar. A translucent grid overlay appears across all your screens. Move the cursor over the zone where you want the window to land, then release. The window snaps to that zone instantly.

Snap zones detected from cursor position:

| Cursor region | Zone |
|---|---|
| Far left or far right edge | Left Half / Right Half |
| Top-left / top-right corner | Top Left / Top Right quarter |
| Bottom-left / bottom-right corner | Bottom Left / Bottom Right quarter |
| Top or bottom strip (centre) | Top Half / Bottom Half |
| Centre rectangle | Full Screen |

### ⌃⌥Space → cycle positions
Press **Control + Option + Space** to move the focused window through a list of predefined layouts. Each press advances to the next position. After the last position on the current monitor it wraps to the first position on the next monitor, cycling through all attached screens.

Predefined positions (in cycle order):

1. Left Half
2. Right Half
3. Full Screen
4. Top Left
5. Top Right
6. Bottom Left
7. Bottom Right
8. Left Third
9. Center Third
10. Right Third
11. Left ⅔
12. Right ⅔
13. Top Half
14. Bottom Half
15. Centre (floating)

---

## Grid

The layout grid is **12 columns × 6 rows**. Column and row numbers are shown on the overlay edges so you always know exactly where a window will land. Every layout in the cycle list is expressed in grid coordinates, making it easy to add or customise positions by editing `Models.swift`.

```
 col:  1  2  3  4  5  6  7  8  9 10 11 12
row 1 ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
row 2 ├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤
row 3 ├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤
row 4 ├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤
row 5 ├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤
row 6 └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
```

To add a custom layout, append a `WindowPosition` to `predefinedPositions` in `Models.swift`:

```swift
WindowPosition(name: "My Layout", cell: GridCell(col: 2, row: 1, colSpan: 8, rowSpan: 4))
//                                                       ^col  ^row  ^width    ^height
//  (all values are 0-indexed; col 0 = leftmost, row 0 = topmost)
```

---

## Build & Install

### Requirements
- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)

### Build

```bash
chmod +x build.sh
./build.sh
```

This compiles the Swift sources and assembles `.build/WindowSnapper.app`.

### Run

```bash
open .build/WindowSnapper.app
```

On first launch macOS will prompt for **Accessibility** permission. Grant it in:
> System Settings → Privacy & Security → Accessibility

Restart the app after granting permission. It will appear as a **⊞** icon in your menu bar.

To auto-start at login, drag `WindowSnapper.app` to a permanent location (e.g. `/Applications`), then add it via:
> System Settings → General → Login Items

---

## Architecture

```
Sources/WindowSnapper/
├── main.swift          Entry point; sets activation policy to .accessory (no Dock icon)
├── AppDelegate.swift   Status-bar item, permissions prompt, wires everything together
├── Models.swift        GridCell, WindowPosition, predefinedPositions[]
├── WindowManager.swift AXUIElement API wrappers; coordinate conversion; zone detection
├── GridView.swift      NSView that draws the 12×6 grid + highlighted snap zone
├── GridOverlay.swift   Creates/destroys one NSPanel per screen; routes highlight updates
└── EventMonitor.swift  CGEventTap (mouse) + Carbon RegisterEventHotKey (⌃⌥Space)
```

### Key technical notes

**Coordinate systems** — macOS has two:
- *AppKit / NSScreen*: origin at bottom-left of main screen, y increases upward.
- *CG / AX API*: origin at top-left of main screen, y increases downward.

`WindowManager` converts between them. All AX calls use CG coordinates; all NSView drawing uses AppKit coordinates.

**Drag detection** — The `CGEventTap` runs in *listen-only* mode, so window dragging is never interrupted. On `leftMouseDown` with Shift held the AX element under the cursor is captured. On `leftMouseUp` the captured window is snapped to the grid zone the cursor is over.

**Overlay** — Each screen gets a transparent `NSPanel` at `CGWindowLevelForKey(.maximumWindow) - 1`, above all normal windows. `ignoresMouseEvents = true` means the cursor passes through to the window being dragged.

**Hotkey** — Carbon `RegisterEventHotKey` is used for reliability across all apps and system states.

---

## Known Limitations (v0)

- **No preference UI** — layouts are hardcoded in `Models.swift`.
- **No drag-to-define region** — the snap zone is determined by where the cursor is when you release, not by a drawn rectangle. Multi-cell drag selection is planned.
- **Shift must be held at mouse-down** — pressing Shift after dragging has started won't trigger snap mode.
- **No thirds-based zone detection** — the cursor-position zones only detect halves, quarters, and full-screen. Use the cycle hotkey for thirds layouts.
- **No sandboxing / code signing** — you'll need to right-click → Open on first launch, or sign the app yourself.

---

## Planned (v1)

- [ ] Preference window (add/remove/reorder positions, change hotkey)
- [ ] Drag-to-select multi-cell region on the overlay
- [ ] Thirds and custom zones in cursor-position detection
- [ ] Code signing / notarization
- [ ] Auto-updater
