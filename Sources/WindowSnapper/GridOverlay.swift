import AppKit

// Manages a small floating preview panel that shows the zone layout in miniature.
// The panel is centered on the active screen and ignores mouse events.
class GridOverlayController {

    private struct ScreenPanel {
        let screen: NSScreen
        let panel: NSPanel
        let gridView: GridView
    }

    private var panels: [ScreenPanel] = []
    private(set) var isVisible = false

    /// Preview panel is ~15% of screen width, aspect-matched to the screen.
    private static let previewScale: CGFloat = 0.15

    // MARK: - Show / Hide

    /// Show the overlay. If `onScreen` is provided, show only on that screen;
    /// otherwise show on all screens.
    func show(on onScreen: NSScreen? = nil) {
        guard !isVisible else { return }
        isVisible = true

        let screens = onScreen.map { [$0] } ?? NSScreen.screens
        debugLog("overlay show: \(screens.count) screen(s)")

        for screen in screens {
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
        let vf = screen.visibleFrame
        let previewW = round(vf.width * Self.previewScale)
        let previewH = round(vf.height * Self.previewScale)

        // Center on the screen's visible frame (AppKit coordinates)
        let panelX = vf.midX - previewW / 2
        let panelY = vf.midY - previewH / 2
        let panelFrame = NSRect(x: panelX, y: panelY, width: previewW, height: previewH)

        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setFrame(panelFrame, display: false)

        let gridView = GridView(frame: NSRect(origin: .zero, size: panelFrame.size))
        gridView.wantsLayer = true
        gridView.layer?.cornerRadius = 10
        gridView.layer?.masksToBounds = true
        panel.contentView = gridView

        return panel
    }
}
