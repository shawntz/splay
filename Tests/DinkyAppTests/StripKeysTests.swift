import Carbon.HIToolbox
import CoreGraphics
import DinkyConfig
import Testing
@testable import dinky

/// The strip's keys as the keyboard reports them, against the shipped bindings. The events are only built, never
/// posted, so no tap or Accessibility grant is involved.
struct StripKeysTests {
    /// Option held by its left key, with that key's device bit as macOS sets it.
    private let leftOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    /// Option held by its right key.
    private let rightOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
    /// Command held by its left key, and by its right key.
    private let leftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
    private let rightCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)

    private func keyDown(_ code: Int, _ flags: CGEventFlags, sides: ModifierSides) throws -> KeyPress? {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true))
        event.flags = flags
        return KeyPress(event, sides: sides)
    }

    /// A left arrow key-down. Arrow keys also carry the secondary-fn and numeric-pad flags.
    private func leftArrow(_ modifiers: CGEventFlags, sides: ModifierSides = ModifierSides()) throws -> KeyPress? {
        try keyDown(kVK_LeftArrow, modifiers.union([.maskSecondaryFn, .maskNumericPad]), sides: sides)
    }

    private func shippedMain() throws -> [KeyPress: KeyBinding] {
        let main = try #require(Config.default.modes["main"]).bindings
        return Dictionary(uniqueKeysWithValues: main.map { (KeyPress($0.key), $0.value) })
    }

    @Test func `Option-Command-Left from the keyboard matches alt-cmd-left`() throws {
        for option in [leftOption, rightOption] {
            for command in [leftCommand, rightCommand] {
                let press = try #require(try leftArrow(option.union(command)))
                #expect(press == KeyPress(try KeyCombo("alt-cmd-left")))
                #expect(try shippedMain()[press]?.commands == ["focus left"])
            }
        }
    }

    @Test func `Option-H and Option-L from the keyboard match alt-h and alt-l`() throws {
        for (code, combo, command) in [(kVK_ANSI_H, "alt-h", "focus left"), (kVK_ANSI_L, "alt-l", "focus right")] {
            let press = try #require(try keyDown(code, leftOption, sides: ModifierSides()))
            #expect(press == KeyPress(try KeyCombo(combo)))
            #expect(try shippedMain()[press]?.commands == [command])
        }
    }

    @Test func `Option-Left alone reaches the app again`() throws {
        let press = try #require(try leftArrow(leftOption))
        #expect(try shippedMain()[press] == nil, "moving back by a word in a text field")
    }

    @Test func `Command-Left alone reaches the app`() throws {
        let press = try #require(try leftArrow(leftCommand))
        #expect(try shippedMain()[press] == nil, "the start of the line in a text field, Back in a browser")
    }

    @Test func `Option-Command-Shift-Left is not a strip key`() throws {
        let shift = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02)
        let press = try #require(try leftArrow(leftOption.union(leftCommand).union(shift)))
        #expect(press != KeyPress(try KeyCombo("alt-cmd-left")))
        #expect(try shippedMain()[press] == nil)
    }

    @Test func `With alt limited to its left key, right Option with Command-Left reaches the app`() throws {
        var sides = ModifierSides()
        sides.alt = .left
        #expect(try leftArrow(rightOption.union(leftCommand), sides: sides) == nil, "no press for a binding to match, so the app gets the key")
        let press = try #require(try leftArrow(leftOption.union(leftCommand), sides: sides))
        #expect(try shippedMain()[press]?.commands == ["focus left"])
        #expect(try keyDown(kVK_ANSI_L, rightOption, sides: sides) == nil, "the right Option key still types its character")
    }

    @Test func `The menu shows the arrow keys beside Focus Left and Right, and lists Alt-H and Alt-L with the other bindings`() throws {
        var bindings = MenuBindings(Config.default.modes["main"])
        #expect(bindings.combo(for: "focus left") == (try KeyCombo("alt-cmd-left")))
        #expect(bindings.combo(for: "focus right") == (try KeyCombo("alt-cmd-right")))
        #expect(bindings.combo(for: "focus-column first") == (try KeyCombo("alt-cmd-home")))
        #expect(bindings.combo(for: "focus-column last") == (try KeyCombo("alt-cmd-end")))
        let others = Dictionary(uniqueKeysWithValues: bindings.unshown.map { ($0.combo.description, $0.commands) })
        #expect(others["alt-h"] == ["focus left"])
        #expect(others["alt-l"] == ["focus right"])
        // Which key an item shows must not depend on dictionary order.
        let order = bindings.unshown.map(\.combo.description)
        #expect(order == order.sorted())
    }

    @Test func `The app's socket and journal are Splay's own`() {
        #expect(socketPath.hasSuffix("/splay.sock"))
        #expect(Recovery.url.path.hasSuffix("/Library/Application Support/splay/journal.json"))
        for path in [socketPath, Recovery.url.path] {
            #expect(!path.lowercased().contains("dinky"), "\(path)")
        }
    }
}
