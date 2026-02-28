import AppKit
import Carbon.HIToolbox

// MARK: - ModifierSet

struct ModifierSet: Equatable {
    var control: Bool
    var option: Bool
    var command: Bool
    var shift: Bool

    func toCGEventFlags() -> CGEventFlags {
        var flags = CGEventFlags()
        if control { flags.insert(.maskControl) }
        if option  { flags.insert(.maskAlternate) }
        if command { flags.insert(.maskCommand) }
        if shift   { flags.insert(.maskShift) }
        return flags
    }

    private static let relevantMask: CGEventFlags = [
        .maskControl, .maskAlternate, .maskCommand, .maskShift
    ]

    /// True when exactly these modifiers are held (no extras among the four).
    func matchesExactly(_ flags: CGEventFlags) -> Bool {
        flags.intersection(Self.relevantMask) == toCGEventFlags()
    }

    /// True when at least these modifiers are held.
    func isSubset(of flags: CGEventFlags) -> Bool {
        let required = toCGEventFlags()
        return flags.intersection(required) == required
    }

    var displayString: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if command { s += "⌘" }
        if shift   { s += "⇧" }
        return s.isEmpty ? "None" : s
    }

    var hasAnyModifier: Bool {
        control || option || command || shift
    }
}

// MARK: - KeyBindingSettings

class KeyBindingSettings {
    static let shared = KeyBindingSettings()
    static let didChangeNotification = Notification.Name("KeyBindingSettingsDidChange")

    var cyclingModifier: ModifierSet
    var nextHorizontalKey: Int
    var prevHorizontalKey: Int
    var nextVerticalKey: Int
    var prevVerticalKey: Int
    var dragModifier: ModifierSet
    var fullScreenOverlay: Bool

    // MARK: Defaults

    static let defaultFullScreenOverlay = true
    static let defaultCyclingModifier = ModifierSet(control: true, option: true, command: false, shift: false)
    static let defaultNextHorizontal  = kVK_RightArrow
    static let defaultPrevHorizontal  = kVK_LeftArrow
    static let defaultNextVertical    = kVK_DownArrow
    static let defaultPrevVertical    = kVK_UpArrow
    static let defaultDragModifier    = ModifierSet(control: false, option: false, command: false, shift: true)

    // MARK: Init

    private init() {
        let d = UserDefaults.standard

        cyclingModifier = ModifierSet(
            control: d.object(forKey: "kb.cycling.ctrl")   as? Bool ?? Self.defaultCyclingModifier.control,
            option:  d.object(forKey: "kb.cycling.opt")    as? Bool ?? Self.defaultCyclingModifier.option,
            command: d.object(forKey: "kb.cycling.cmd")    as? Bool ?? Self.defaultCyclingModifier.command,
            shift:   d.object(forKey: "kb.cycling.shift")  as? Bool ?? Self.defaultCyclingModifier.shift
        )

        nextHorizontalKey = d.object(forKey: "kb.nextH") as? Int ?? Self.defaultNextHorizontal
        prevHorizontalKey = d.object(forKey: "kb.prevH") as? Int ?? Self.defaultPrevHorizontal
        nextVerticalKey   = d.object(forKey: "kb.nextV") as? Int ?? Self.defaultNextVertical
        prevVerticalKey   = d.object(forKey: "kb.prevV") as? Int ?? Self.defaultPrevVertical

        dragModifier = ModifierSet(
            control: d.object(forKey: "kb.drag.ctrl")  as? Bool ?? Self.defaultDragModifier.control,
            option:  d.object(forKey: "kb.drag.opt")   as? Bool ?? Self.defaultDragModifier.option,
            command: d.object(forKey: "kb.drag.cmd")   as? Bool ?? Self.defaultDragModifier.command,
            shift:   d.object(forKey: "kb.drag.shift") as? Bool ?? Self.defaultDragModifier.shift
        )

        fullScreenOverlay = d.object(forKey: "kb.fullScreenOverlay") as? Bool ?? Self.defaultFullScreenOverlay
    }

    // MARK: Persistence

    func save() {
        let d = UserDefaults.standard

        d.set(cyclingModifier.control, forKey: "kb.cycling.ctrl")
        d.set(cyclingModifier.option,  forKey: "kb.cycling.opt")
        d.set(cyclingModifier.command, forKey: "kb.cycling.cmd")
        d.set(cyclingModifier.shift,   forKey: "kb.cycling.shift")

        d.set(nextHorizontalKey, forKey: "kb.nextH")
        d.set(prevHorizontalKey, forKey: "kb.prevH")
        d.set(nextVerticalKey,   forKey: "kb.nextV")
        d.set(prevVerticalKey,   forKey: "kb.prevV")

        d.set(dragModifier.control, forKey: "kb.drag.ctrl")
        d.set(dragModifier.option,  forKey: "kb.drag.opt")
        d.set(dragModifier.command, forKey: "kb.drag.cmd")
        d.set(dragModifier.shift,   forKey: "kb.drag.shift")

        d.set(fullScreenOverlay, forKey: "kb.fullScreenOverlay")

        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func resetToDefaults() {
        cyclingModifier   = Self.defaultCyclingModifier
        nextHorizontalKey = Self.defaultNextHorizontal
        prevHorizontalKey = Self.defaultPrevHorizontal
        nextVerticalKey   = Self.defaultNextVertical
        prevVerticalKey   = Self.defaultPrevVertical
        dragModifier      = Self.defaultDragModifier
        fullScreenOverlay = Self.defaultFullScreenOverlay
        save()
    }

    // MARK: Display Helpers

    var nextHorizontalKeyName: String { displayNameForKeyCode(nextHorizontalKey) }
    var prevHorizontalKeyName: String { displayNameForKeyCode(prevHorizontalKey) }
    var nextVerticalKeyName: String   { displayNameForKeyCode(nextVerticalKey) }
    var prevVerticalKeyName: String   { displayNameForKeyCode(prevVerticalKey) }
}
