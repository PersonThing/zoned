import AppKit

// Manages one floating NSPanel per screen that together form the zone overlay.
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

    /// Show the overlay on all screens, displaying each screen's zones from the registry.
    func show() {
        guard !isVisible else { return }
        isVisible = true

        for screen in NSScreen.screens {
            let panel = makePanel(for: screen)
            let gridView = panel.contentView as! GridView
            gridView.zones = zoneRegistry.zones(for: screen)
            panels.append(ScreenPanel(screen: screen, panel: panel, gridView: gridView))
            panel.alphaValue = 0
            panel.orderFront(nil)
        }

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for sp in panels {
                sp.panel.animator().alphaValue = 1.0
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        let panelsToRemove = panels
        panels.removeAll()

        // Fade out
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            for sp in panelsToRemove {
                sp.panel.animator().alphaValue = 0
            }
        }, completionHandler: {
            for sp in panelsToRemove { sp.panel.orderOut(nil) }
        })
    }

    // MARK: - Highlight

    /// Highlight a zone by index on the given screen. Pass nil to clear.
    func highlightZone(index: Int?, on activeScreen: NSScreen) {
        for sp in panels {
            if sp.screen == activeScreen {
                sp.gridView.highlightedIndex = index
            } else {
                sp.gridView.highlightedIndex = nil
            }
            sp.gridView.needsDisplay = true
        }
    }

    /// Highlight a zone by matching a WindowPosition on the given screen.
    func highlightZone(_ position: WindowPosition?, on activeScreen: NSScreen) {
        for sp in panels {
            if sp.screen == activeScreen, let pos = position {
                sp.gridView.highlightedIndex = sp.gridView.zones.firstIndex(of: pos)
            } else {
                sp.gridView.highlightedIndex = nil
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
