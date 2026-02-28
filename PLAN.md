# Zoned — macOS Window Manager

Build a native macOS window manager (Swift/AppKit) that lets users snap windows to predefined grid zones via configurable keyboard shortcuts, with a visual overlay and multi-monitor support. Keyboard shortcuts in v0, drag-snapping deferred to v1.

## Phase 1: Xcode Project Setup & Menu Bar App Skeleton

### What to do
- Create a new Xcode project: macOS → App, Swift, AppKit (not SwiftUI app lifecycle)
- Set `LSUIElement = YES` in Info.plist (hides dock icon, menu bar agent only)
- **Disable App Sandbox** in Signing & Capabilities (required for Accessibility API)
- Set up a free Apple Developer account and configure code signing (so Accessibility permission persists across rebuilds)
- Implement `AppDelegate` with `NSStatusItem` (menu bar icon)
- Menu bar dropdown: "About", "Edit Config", "Reload Config", separator, "Quit"
- Verify it builds, runs, and shows a menu bar icon with working Quit

### Key files
- `WindowManager/AppDelegate.swift`
- `WindowManager/Info.plist`
- `WindowManager.entitlements` (remove sandbox entitlement)

### Notes for someone new to macOS dev
- The app lifecycle is `NSApplicationDelegate`-based, NOT SwiftUI `@main App`
- `LSUIElement` makes it a 'background' app — no dock icon, no main menu bar, only the status item
- If you see 'App Sandbox' in capabilities, remove it entirely

## Phase 2: Accessibility Permission Flow

### What to do
- On launch, check `AXIsProcessTrusted()` to see if Accessibility access is granted
- If not granted, call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` to show the system prompt
- Show a user-friendly `NSAlert` explaining why the permission is needed and how to grant it
- Gate ALL window management functionality behind this check
- Add a menu bar item showing permission status (e.g., '⚠️ Accessibility Required' when not granted)
- Re-check permission on a timer (every 5s) since user grants it in System Settings asynchronously

### Key files
- `WindowManager/Accessibility/AccessibilityManager.swift`

### Why this is its own phase
- Without this, nothing else works. Get it right first.
- The permission UX is the first thing users experience — it needs to be clear.
- During development, forgetting to re-grant after a rebuild is a common frustration.

## Phase 3: Window Management Core (AXUIElement Wrapper)

### What to do
Build a clean Swift wrapper around the C-style AXUIElement API:
- `getFrontmostApplication() -> AXUIElement?` — via `NSWorkspace.shared.frontmostApplication` → pid → `AXUIElementCreateApplication(pid)`
- `getFrontmostWindow(of app: AXUIElement) -> AXUIElement?` — get `kAXFocusedWindowAttribute`
- `getWindowFrame(window: AXUIElement) -> CGRect?` — read `kAXPositionAttribute` + `kAXSizeAttribute`
- `setWindowFrame(window: AXUIElement, frame: CGRect)` — set position then size via `AXUIElementSetAttributeValue`
- Error handling: apps that don't support Accessibility, windows that can't be resized (check `kAXGrowAreaAttribute`), etc.

### Validate with a manual test
Hard-code a hotkey (e.g., Cmd+Shift+T) that moves the frontmost window to the top-left 50% of the screen. Verify it works with Terminal, Safari, and a non-standard app like Electron.

### Key files
- `WindowManager/Windows/WindowController.swift`

### Gotchas
- AXUIElement API is C-based, uses `CFTypeRef` and manual memory management. Wrap it in Swift-friendly types.
- `AXValueCreate` / `AXValueGetValue` for CGPoint/CGSize is verbose — helper functions are essential.
- Position must be set BEFORE size (some apps clamp position based on current size).

## Phase 4: Multi-Monitor Screen Manager

### What to do
- Enumerate screens via `NSScreen.screens`
- For each screen, compute the **usable frame** (`visibleFrame`) which excludes menu bar and dock
- Sort screens left-to-right by `frame.origin.x` for consistent directional navigation
- Convert grid coordinates (e.g., x:0, y:0, w:6, h:6 on a 12×6 grid) to pixel `CGRect` on a specific screen
- Handle Retina scaling (use points, not pixels — `NSScreen` already works in points)
- Provide `screenForWindow(frame: CGRect) -> NSScreen` to determine which screen a window is currently on

### Key files
- `WindowManager/Windows/ScreenManager.swift`

### Coordinate system notes
- NSScreen origin is bottom-left. Accessibility API origin is top-left. You MUST convert between them.
- `NSScreen.screens[0]` is always the primary display (the one with the menu bar).
- The grid's row 0 should be the TOP of the screen (user expectation), so y-axis flipping is needed.

## Phase 5: Zone Configuration & Presets

### What to do

#### Data model
```swift
struct AppConfig: Codable {
    var grid: GridSize           // { columns: 12, rows: 6 }
    var modifier: String         // "ctrl+option" (default)
    var zones: [Zone]
}
struct GridSize: Codable { var columns: Int; var rows: Int }
struct Zone: Codable {
    var name: String             // "Left Half"
    var key: String              // "1"
    var grid: ZoneRect           // { x: 0, y: 0, w: 6, h: 6 }
}
struct ZoneRect: Codable { var x: Int; var y: Int; var w: Int; var h: Int }
```

#### Config file location
`~/.config/windowmanager/config.json`

#### Built-in presets (default config)
- 1: Left Half (0,0,6,6)
- 2: Right Half (6,0,6,6)
- 3: Left Third (0,0,4,6)
- 4: Center Third (4,0,4,6)
- 5: Right Third (8,0,4,6)
- 6: Top-Left Quarter (0,0,6,3)
- 7: Top-Right Quarter (6,0,6,3)
- 8: Bottom-Left Quarter (0,3,6,3)
- 9: Bottom-Right Quarter (6,3,6,3)
- 0: Full Screen (0,0,12,6)

#### Behavior
- On first launch, if no config file exists, create it with defaults
- Parse the `modifier` string into the corresponding `NSEvent.ModifierFlags`
- Validate zones: no overlapping keys, grid rects within bounds
- "Edit Config" menu item opens the JSON file in the default editor ($EDITOR or TextEdit)
- "Reload Config" re-reads the file and applies changes without restart

### Key files
- `WindowManager/Config/AppConfig.swift` (data models)
- `WindowManager/Config/ConfigManager.swift` (load/save/watch)
- `WindowManager/Config/DefaultPresets.swift` (built-in defaults)

### Modifier string parsing
Parse strings like `ctrl+option`, `shift+cmd`, `ctrl+option+cmd` into `NSEvent.ModifierFlags`. Supported tokens: `ctrl`/`control`, `option`/`alt`, `shift`, `cmd`/`command`.

## Phase 6: Global Hotkey System

### What to do

#### Event tap setup
- Create a `CGEvent` tap via `CGEvent.tapCreate` listening for `.keyDown` and `.flagsChanged` events
- This requires Accessibility permissions (already handled in Phase 2)
- Run the tap on a dedicated `RunLoop` or the main run loop

#### Modifier state tracking
- On `flagsChanged` events, track whether the configured modifier combo is currently held
- When modifier is pressed (and no other key within ~150ms): trigger overlay show
- When modifier is released: trigger overlay hide

#### Key handling (while modifier is held)
- **Arrow Left/Right**: Call ZoneNavigator for directional movement
- **Number/letter key matching a zone's `key`**: Move frontmost window to that zone
- **Escape**: Hide overlay, cancel

#### Important details
- The event tap callback must return quickly — do window management async on main queue
- Don't intercept events that aren't for us (return the event unchanged for non-matching key combos)
- Handle the case where the modifier combo conflicts with the key being pressed (e.g., if modifier is ctrl+option and user presses ctrl+option+3, don't also type '3' in the focused app) — return `nil` from the tap to swallow the event

### Key files
- `WindowManager/Hotkeys/HotkeyManager.swift`
- `WindowManager/Hotkeys/ModifierParser.swift`

### Gotchas
- `CGEvent.tapCreate` can return nil if permissions aren't granted or another tap is interfering
- The tap can be disabled by the system if the callback takes too long — keep it fast
- Key codes are hardware-dependent (not characters). Use `kVK_` constants from Carbon (`Carbon.HIToolbox`)

## Phase 7: Overlay Window UI

### What to do

#### Overlay window (one per monitor)
- Create a borderless `NSWindow` (`.borderless` style mask)
- Set `window.level = .floating` (or `.screenSaver` to be above everything)
- Set `window.backgroundColor = .clear`
- Set `window.isOpaque = false`
- Set `window.ignoresMouseEvents = true` (click-through)
- Set `window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- Size and position to match each screen's `visibleFrame`

#### Overlay rendering (custom NSView)
- Semi-transparent dark background (e.g., black at 30% opacity)
- Draw grid lines (subtle, thin)
- Draw zone rectangles with:
  - Semi-transparent colored fill
  - Zone name label (centered)
  - Zone key label (large, prominent — this is what the user needs to see)
- Highlight the zone the current window occupies (different border color)

#### Animation
- Fade in over ~150ms when modifier is held
- Fade out over ~100ms when modifier is released
- Use `NSAnimationContext` for smooth transitions

#### OverlayManager
- Creates/destroys overlay windows as monitors connect/disconnect
- Listens for `NSApplication.didChangeScreenParametersNotification`
- Shows/hides all overlays in response to HotkeyManager

### Key files
- `WindowManager/Overlay/OverlayManager.swift`
- `WindowManager/Overlay/OverlayView.swift` (custom `NSView` with `draw(_:)` override)

### Design notes
- Keep the overlay minimal and functional — this is a power-user tool, not a pretty UI
- Zone colors should be distinct but muted. Use a predefined palette.
- The key label (1, 2, 3...) should be the most prominent element — large, high contrast

## Phase 8: Directional Navigation & Zone Cycling

### What to do

#### Determine current zone
- Get the frontmost window's frame
- Determine which screen it's on
- Find which zone best matches its current position (by overlap percentage)
- If no zone matches well (window is in an arbitrary position), treat it as 'unzoned'

#### Directional movement (modifier+Left/Right)
- **Right**: Find the next zone to the right of current position
  - First, look for zones on the same screen with `grid.x > currentZone.grid.x`
  - If none, jump to the leftmost zone on the next screen to the right
  - If on the rightmost screen, wrap to the leftmost zone on the leftmost screen
- **Left**: Mirror of right
- If window is 'unzoned', snap to the nearest zone in the pressed direction

#### Direct zone jump (modifier+key)
- Look up the zone by its `key` property
- Move the frontmost window to that zone on the **current screen** (the screen the window is on)
- If the window is between screens, use the screen closest to the window center

#### Edge cases
- Zone ordering for cycling: sort by grid.x, then grid.y (left-to-right, top-to-bottom)
- Multiple zones could be 'to the right' — pick the nearest one (smallest grid.x difference)
- Cross-monitor jumps should maintain the same zone grid position if possible

### Key files
- `WindowManager/Navigation/ZoneNavigator.swift`

## Phase 9: Config File Watching & Hot Reload

### What to do
- Use `DispatchSource.makeFileSystemObjectSource` (or `FSEvents`) to watch `~/.config/windowmanager/config.json` for changes
- On file change, re-parse the config
- If parsing fails, keep the old config and show a notification (NSUserNotification or UNUserNotificationCenter) with the parse error
- If parsing succeeds, update all systems: zones, modifier keys, overlay layout
- The 'Reload Config' menu item does the same thing manually

### Key files
- `WindowManager/Config/ConfigManager.swift` (add file watching)

### Notes
- Debounce file change events (editors may write multiple times)
- Log config reload events for debugging

## Phase 10: Polish, Error Handling & First-Launch Experience

### What to do

#### Error handling
- Windows that can't be resized (some apps enforce min/max size): move to zone anyway, clamp to app's allowed size range
- Apps in native macOS fullscreen: skip (can't move fullscreen windows via AX API)
- Config file permissions errors: show alert with fix instructions

#### First-launch experience
- If no config file exists → create default config, show a welcome `NSAlert`:
  - Explain the modifier key (default: ⌃⌥)
  - Explain: hold modifier to see zones, press number to snap, arrows to cycle
  - Point to config file location
  - Link to Accessibility permissions if not yet granted

#### Menu bar enhancements
- Show current modifier combo in the menu bar dropdown
- Show zone count ('10 zones configured')
- Add 'Start at Login' toggle (use `SMAppService` on macOS 13+ or `LSSharedFileList` for older)

#### Logging
- Add `os_log` / `Logger` statements for debugging (zone moves, config reloads, errors)
- No log file — use Console.app for viewing

### Key files
- Various (cross-cutting concern)
- `WindowManager/AppDelegate.swift` (menu bar updates, first-launch)
- `WindowManager/LoginItemManager.swift` (start at login)

## Dependencies

- Xcode 15+ installed
- Free Apple Developer account (for code signing — Accessibility permissions require signed binaries to persist)
- macOS 13+ (Ventura) as minimum deployment target (for SMAppService, modern NSScreen APIs)
