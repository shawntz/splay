import Carbon.HIToolbox
import CoreGraphics
import DinkyConfig
import Testing
@testable import dinky

/// Option-Left and Option-Right as the keyboard reports them, against the shipped bindings. The events are only
/// built, never posted, so no tap or Accessibility grant is involved.
struct StripKeysTests {
    /// Option held by its left key, with that key's device bit as macOS sets it.
    private let leftOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    /// Option held by its right key.
    private let rightOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)

    /// A left arrow key-down. Arrow keys also carry the secondary-fn and numeric-pad flags.
    private func leftArrow(_ modifiers: CGEventFlags, sides: ModifierSides = ModifierSides()) throws -> KeyPress? {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true))
        event.flags = modifiers.union([.maskSecondaryFn, .maskNumericPad])
        return KeyPress(event, sides: sides)
    }

    private func shippedMain() throws -> [KeyPress: KeyBinding] {
        let main = try #require(Config.default.modes["main"]).bindings
        return Dictionary(uniqueKeysWithValues: main.map { (KeyPress($0.key), $0.value) })
    }

    @Test func `Option-Left from the keyboard matches alt-left`() throws {
        for option in [leftOption, rightOption] {
            let press = try #require(try leftArrow(option))
            #expect(press == KeyPress(try KeyCombo("alt-left")))
            #expect(try shippedMain()[press]?.commands == ["focus left"])
        }
    }

    @Test func `Option-Shift-Left still reaches the app`() throws {
        let shift = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02)
        let press = try #require(try leftArrow(leftOption.union(shift)))
        #expect(press != KeyPress(try KeyCombo("alt-left")))
        #expect(try shippedMain()[press] == nil, "selecting back by a word is left alone")
    }

    @Test func `Command-Left reaches the app again`() throws {
        let command = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
        let press = try #require(try leftArrow(command))
        #expect(try shippedMain()[press] == nil, "the start of the line in a text field, Back in a browser")
    }

    @Test func `With alt limited to its left key, right Option-Left reaches the app`() throws {
        var sides = ModifierSides()
        sides.alt = .left
        #expect(try leftArrow(rightOption, sides: sides) == nil, "no press for a binding to match, so the app moves by a word")
        let press = try #require(try leftArrow(leftOption, sides: sides))
        #expect(try shippedMain()[press]?.commands == ["focus left"])
    }

    @Test func `The menu shows Alt-Left and Alt-Right beside Focus Left and Right`() throws {
        var bindings = MenuBindings(Config.default.modes["main"])
        #expect(bindings.combo(for: "focus left") == (try KeyCombo("alt-left")))
        #expect(bindings.combo(for: "focus right") == (try KeyCombo("alt-right")))
        #expect(bindings.combo(for: "focus-column first") == (try KeyCombo("alt-home")))
        #expect(bindings.combo(for: "focus-column last") == (try KeyCombo("alt-end")))
    }

    @Test func `The app's socket and journal are Splay's own`() {
        #expect(socketPath.hasSuffix("/splay.sock"))
        #expect(Recovery.url.path.hasSuffix("/Library/Application Support/splay/journal.json"))
        for path in [socketPath, Recovery.url.path] {
            #expect(!path.lowercased().contains("dinky"), "\(path)")
        }
    }
}
