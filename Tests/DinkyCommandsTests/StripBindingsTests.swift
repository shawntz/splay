import DinkyConfig
import DinkyLayout
import Testing
@testable import DinkyCommands

/// Splay's shipped main mode walks the scrolling strip with Cmd-Left and Cmd-Right.
struct StripBindingsTests {
    @Test func `Cmd-Left and Cmd-Right focus along the strip`() throws {
        let main = try #require(Config.default.modes["main"]).bindings
        for (combo, command, direction) in [("cmd-left", "focus left", Direction.left), ("cmd-right", "focus right", .right)] {
            let binding = try #require(main[KeyCombo(combo)], "\(combo)")
            #expect(binding.commands == [command])
            #expect(binding.excludeApps.isEmpty)
            #expect(try binding.commands.map(Command.parse) == [.focus(direction)])
        }
        // Dinky's alt-h and alt-l would do the same again, and take Option-H and Option-L from every app and tool.
        #expect(try main[KeyCombo("alt-h")]?.commands == nil)
        #expect(try main[KeyCombo("alt-l")]?.commands == nil)
        #expect(try main[KeyCombo("alt-j")]?.commands == ["focus down"], "up and down in a column stay")
        #expect(try main[KeyCombo("alt-k")]?.commands == ["focus up"])
    }

    @Test func `The strip commands have keys of their own`() throws {
        let main = try #require(Config.default.modes["main"]).bindings
        let expected: [(combo: String, command: String, parsed: Command)] = [
            ("cmd-home", "focus-column first", .focusColumn(.first)),
            ("cmd-end", "focus-column last", .focusColumn(.last)),
            ("alt-r", "column-width next", .columnWidth(.next)),
            ("alt-shift-r", "column-width prev", .columnWidth(.prev)),
            ("alt-c", "center-column", .centerColumn),
            ("alt-m", "maximize-column", .maximizeColumn),
        ]
        for (combo, command, parsed) in expected {
            let binding = try #require(main[KeyCombo(combo)], "\(combo)")
            #expect(binding.commands == [command])
            #expect(binding.excludeApps.isEmpty)
            #expect(try binding.commands.map(Command.parse) == [parsed])
        }
    }
}
