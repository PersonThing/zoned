import AppKit

// Manages a small floating preview panel that shows zones.
// The panel is centered on the active screen and ignores mouse events.
class GridOverlayController {

    private struct ScreenPanel {
        let screen: NSScreen
        let panel: NSPanel
        let gridView: GridView
    }

    private var panels: [ScreenPanel] = []
    private(set) var isVisible = false

    private static let previewScale: CGFloat = 0.15

    // MARK: - Show / Hide

    func show(on screen: NSScreen, layout: ZoneLayout, activeZoneIndex: Int? = nil) {
        guard !isVisible else { return }
        isVisible = true

        let fullScreen = KeyBindingSettings.shared.fullScreenOverlay
        let vf = screen.visibleFrame
        let panelFrame: NSRect

        if fullScreen {
            panelFrame = vf
        } else {
            let previewW = round(vf.width * Self.previewScale)
            let previewH = round(vf.height * Self.previewScale) + GridView.instructionHeight
            let panelX = vf.midX - previewW / 2
            let panelY = vf.midY - previewH / 2
            panelFrame = NSRect(x: panelX, y: panelY, width: previewW, height: previewH)
        }

        let panel = makePanel(frame: panelFrame, fullScreen: fullScreen)
        let gridView = panel.contentView as! GridView
        gridView.layout = layout
        gridView.activeZoneIndex = activeZoneIndex
        gridView.isFullScreen = fullScreen
        panels.append(ScreenPanel(screen: screen, panel: panel, gridView: gridView))
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        let panelsToRemove = panels
        panels.removeAll()

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

    func updateHighlight(zoneIndex: Int?) {
        for sp in panels {
            sp.gridView.activeZoneIndex = zoneIndex
            sp.gridView.needsDisplay = true
        }
    }

    // MARK: - Panel Construction

    private func makePanel(frame: NSRect, fullScreen: Bool = false) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
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
        panel.setFrame(frame, display: false)

        let gridView = GridView(frame: NSRect(origin: .zero, size: frame.size))
        gridView.wantsLayer = true
        gridView.layer?.cornerRadius = fullScreen ? 0 : 10
        gridView.layer?.masksToBounds = true
        panel.contentView = gridView

        return panel
    }
}
