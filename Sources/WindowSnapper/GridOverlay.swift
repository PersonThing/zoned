import AppKit

// Manages one floating NSPanel per screen that together form the grid overlay.
// The overlay is purely visual: it ignores mouse events so window dragging
// continues normally through it.
class GridOverlayController {

    private struct ScreenPanel {
        let screen: NSScreen
        let panel: NSPanel
        let gridView: GridView
    }

    private var panels: [ScreenPanel] = []
    private(set) var isVisible = false

    // MARK: - Show / Hide

    func show() {
        guard !isVisible else { return }
        isVisible = true

        for screen in NSScreen.screens {
            let panel = makePanel(for: screen)
            let gridView = panel.contentView as! GridView
            panels.append(ScreenPanel(screen: screen, panel: panel, gridView: gridView))
            panel.orderFront(nil)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        for sp in panels { sp.panel.orderOut(nil) }
        panels.removeAll()
    }

    // MARK: - Highlight

    func updateHighlight(_ position: WindowPosition?, on activeScreen: NSScreen) {
        for sp in panels {
            if sp.screen == activeScreen {
                sp.gridView.highlightedPosition = position
            } else {
                sp.gridView.highlightedPosition = nil
            }
            sp.gridView.needsDisplay = true
        }
    }

    // MARK: - Panel Construction

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Float above everything, including full-screen apps
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let gridView = GridView(frame: NSRect(origin: .zero, size: screen.frame.size))
        gridView.screen = screen
        panel.contentView = gridView

        return panel
    }
}
