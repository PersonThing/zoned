# Zoned

macOS window manager. Lives in the menu bar.

## Install

```bash
brew tap PersonThing/zoned
brew install --cask zoned
```

Or build from source:

```bash
./build.sh
```

On first launch, grant **Accessibility** permission:
System Settings → Privacy & Security → Accessibility → enable Zoned.

## Usage

### Zone cycling (keyboard)

Press the cycling modifier (default **⌃⌥**) + arrow keys to snap the focused window:

- **← / →** — cycle horizontal zones (left third, left half, left 2/3, full width, middle 1/3, right 2/3, right half, right third)
- **↑ / ↓** — cycle vertical zones (top 1/3, top 1/2, top 2/3, full height, bottom 2/3, bottom 1/2, bottom 1/3)

Horizontal and vertical axes are independent — you can combine them (e.g. left half + top 1/2 = top-left quarter).

### Drag snapping

Hold the drag modifier (default **⇧ Shift**) while dragging a window. An overlay appears showing available zones. Release to snap to the nearest zone.

If multiple zones share the same center (e.g. middle 1/3, middle 1/2, full width on ultrawide), press **F** during the drag to cycle through them. Defaults to the smallest zone.

### Ultrawide support

On 5120×1440 displays, additional zones are available: 1/4 splits and middle 1/2.

### Preferences

Click the menu bar icon → Preferences to customize:
- Cycling modifier (any combo of ⌃⌥⌘⇧)
- Action keys for each direction
- Drag modifier
- Full-screen overlay vs small centered preview

All settings persist across restarts.

## Build from source

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

Compiles, signs, and installs to `/Applications/Zoned.app`.

## Project structure

```
Sources/WindowSnapper/
├── main.swift                    Entry point
├── AppDelegate.swift             Menu bar, preferences, permissions
├── EventMonitor.swift            CGEventTap for keys + mouse
├── WindowManager.swift           AX API wrappers, coordinate conversion, zone detection
├── Models.swift                  Grid cells, zone definitions, per-resolution overrides
├── GridView.swift                Draws the 12×6 grid overlay
├── GridOverlay.swift             NSPanel management (one per screen)
├── KeyBindingSettings.swift      UserDefaults-backed settings singleton
├── KeyCodeMapping.swift          Carbon key code → display name
├── KeyRecorderView.swift         Custom key capture view for preferences
└── PreferencesWindowController.swift  Preferences window
```
