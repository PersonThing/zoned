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

Press the cycling modifier (default **⌃⌥**) + arrow keys to snap the focused window to predefined zones:

- **← / →** — cycle through zones (left-to-right order)
- **[ / ]** — cycle through layouts

Zones are rectangles on a 12×6 grid. The default layout includes: Left 1/3, Left 1/2, Left 2/3, Full, Middle 1/3, Right 2/3, Right 1/2, Right 1/3.

On multi-monitor setups, cycling wraps across screens left-to-right.

### Drag snapping

Hold the drag modifier (default **⇧ Shift**) while dragging a window. An overlay appears showing available zones. Release to snap to the nearest zone.

If multiple zones overlap at the cursor position, press **F** during the drag to cycle through them (smallest first).

### Custom layouts

Click the menu bar icon → Preferences → Edit Layouts to open the zone editor.

- **Click + drag** on empty grid space to create a new zone
- **Click** a zone to select it, then **drag** to move it
- **Drag zone edges** to resize (cursor changes to resize arrows near edges)
- **Delete/Backspace** to remove the selected zone
- Create multiple layouts and assign them to specific aspect ratios (e.g. 16:9, 32:9 for ultrawide)

### Preferences

Click the menu bar icon → Preferences to customize:
- Cycling modifier (any combo of ⌃⌥⌘⇧)
- Drag modifier
- Full-screen overlay vs small centered preview

All settings persist across restarts.

## Build from source

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

Compiles, signs, and installs to `/Applications/Zoned.app`.

## Release

```bash
./release.sh
```

Builds a release ZIP, then follow the printed instructions to tag, upload to GitHub Releases, and update the Homebrew tap.

## Project structure

```
Sources/WindowSnapper/
├── main.swift                         Entry point
├── AppDelegate.swift                  Menu bar, preferences, permissions
├── EventMonitor.swift                 CGEventTap for keys + mouse
├── WindowManager.swift                AX API wrappers, coordinate conversion, zone detection
├── Models.swift                       Grid cells, zones, layouts, defaults
├── LayoutStore.swift                  JSON persistence for zone layouts
├── GridView.swift                     Draws the 12×6 grid overlay
├── GridOverlay.swift                  NSPanel management (one per screen)
├── ZoneEditorView.swift               Interactive zone editor (create, move, resize)
├── LayoutEditorWindowController.swift Layout editor window
├── KeyBindingSettings.swift           UserDefaults-backed settings singleton
├── KeyCodeMapping.swift               Carbon key code → display name
├── KeyRecorderView.swift              Custom key capture view for preferences
└── PreferencesWindowController.swift  Preferences window
```
