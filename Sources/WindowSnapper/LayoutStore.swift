import AppKit
import Foundation

class LayoutStore {
    static let shared = LayoutStore()
    static let didChangeNotification = Notification.Name("LayoutStoreDidChange")

    private(set) var layouts: [ZoneLayout] = []

    // Tracks the active layout index per aspect ratio.
    // When multiple layouts share an aspect ratio, this tracks which one is active.
    private var activeLayoutIndex: [String: Int] = [:]

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Zoned", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layouts.json")
    }

    private init() {
        load()
    }

    // MARK: - Aspect Ratio Matching

    /// All layouts that match a screen's aspect ratio (or have nil = any).
    func layouts(for screen: NSScreen) -> [ZoneLayout] {
        let ar = AspectRatio.fromScreen(screen)
        let matching = layouts.filter { $0.aspectRatio == ar }
        let anyLayouts = layouts.filter { $0.aspectRatio == nil }
        let result = matching + anyLayouts
        return result.isEmpty ? makeDefaultLayouts() : result
    }

    /// The currently active layout for a screen.
    func activeLayout(for screen: NSScreen) -> ZoneLayout {
        let candidates = layouts(for: screen)
        let key = screenKey(screen)
        let idx = activeLayoutIndex[key] ?? 0
        let safeIdx = idx < candidates.count ? idx : 0
        return candidates[safeIdx]
    }

    /// Cycle to the next/previous layout for this screen. Returns the new active layout.
    @discardableResult
    func cycleLayout(for screen: NSScreen, direction: Int = 1) -> ZoneLayout {
        let candidates = layouts(for: screen)
        guard !candidates.isEmpty else { return makeDefaultLayouts()[0] }
        let key = screenKey(screen)
        let current = activeLayoutIndex[key] ?? 0
        let next = (current + direction + candidates.count) % candidates.count
        activeLayoutIndex[key] = next
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return candidates[next]
    }

    /// Name of the currently active layout for a screen.
    func activeLayoutName(for screen: NSScreen) -> String {
        activeLayout(for: screen).name
    }

    private func screenKey(_ screen: NSScreen) -> String {
        let ar = AspectRatio.fromScreen(screen)
        return "\(ar.width):\(ar.height)"
    }

    // MARK: - CRUD

    func addLayout(_ layout: ZoneLayout) {
        layouts.append(layout)
        save()
    }

    func updateLayout(_ layout: ZoneLayout) {
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
            save()
        }
    }

    func deleteLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        if layouts.isEmpty {
            layouts = makeDefaultLayouts()
        }
        save()
    }

    func moveLayout(from: Int, to: Int) {
        guard from != to, from >= 0, from < layouts.count, to >= 0, to < layouts.count else { return }
        let layout = layouts.remove(at: from)
        layouts.insert(layout, at: to)
        save()
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(layouts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("LayoutStore save failed: \(error)")
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            layouts = makeDefaultLayouts()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            layouts = try JSONDecoder().decode([ZoneLayout].self, from: data)
            if layouts.isEmpty {
                layouts = makeDefaultLayouts()
                save()
            }
        } catch {
            debugLog("LayoutStore load failed: \(error), using defaults")
            layouts = makeDefaultLayouts()
            save()
        }
    }
}
