import Carbon.HIToolbox
import CoreGraphics
import DinkyConfig
import Testing
@testable import dinky

/// Cmd-Left and Cmd-Right as the keyboard reports them, against the shipped bindings. The events are only
/// built, never posted, so no tap or Accessibility grant is involved.
struct StripKeysTests {
    /// Command held by its left key, with that key's device bit as macOS sets it.
    private let leftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)

    /// A left arrow key-down. Arrow keys also carry the secondary-fn and numeric-pad flags.
    private func leftArrow(_ modifiers: CGEventFlags) throws -> KeyPress? {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true))
        event.flags = modifiers.union([.maskSecondaryFn, .maskNumericPad])
        return KeyPress(event, sides: ModifierSides())
    }

    private func shippedMain() throws -> [KeyPress: KeyBinding] {
        let main = try #require(Config.default.modes["main"]).bindings
        return Dictionary(uniqueKeysWithValues: main.map { (KeyPress($0.key), $0.value) })
    }

    @Test func `Cmd-Left from the keyboard matches cmd-left`() throws {
        let press = try #require(try leftArrow(leftCommand))
        #expect(press == KeyPress(try KeyCombo("cmd-left")))
        #expect(try shippedMain()[press]?.commands == ["focus left"])
    }

    @Test func `Cmd-Shift-Left still reaches the app`() throws {
        let shift = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02)
        let press = try #require(try leftArrow(leftCommand.union(shift)))
        #expect(press != KeyPress(try KeyCombo("cmd-left")))
        #expect(try shippedMain()[press] == nil, "selecting to the line start is left alone")
    }

    @Test func `The menu shows Cmd-Left and Cmd-Right beside Focus Left and Right`() throws {
        var bindings = MenuBindings(Config.default.modes["main"])
        #expect(bindings.combo(for: "focus left") == (try KeyCombo("cmd-left")))
        #expect(bindings.combo(for: "focus right") == (try KeyCombo("cmd-right")))
        #expect(bindings.combo(for: "focus-column first") == (try KeyCombo("cmd-home")))
        #expect(bindings.combo(for: "focus-column last") == (try KeyCombo("cmd-end")))
    }

    @Test func `The app's socket and journal are Splay's own`() {
        #expect(socketPath.hasSuffix("/splay.sock"))
        #expect(Recovery.url.path.hasSuffix("/Library/Application Support/splay/journal.json"))
        for path in [socketPath, Recovery.url.path] {
            #expect(!path.lowercased().contains("dinky"), "\(path)")
        }
    }
}
