import DinkyConfig
import DinkyLayout
import Testing
@testable import DinkyCommands

/// Splay's shipped main mode walks the scrolling strip with Alt-Cmd-Left and Alt-Cmd-Right, and with Dinky's Alt-H and Alt-L.
struct StripBindingsTests {
    @Test func `Alt-Cmd-Left and Alt-Cmd-Right focus along the strip, and so do Alt-H and Alt-L`() throws {
        let main = try #require(Config.default.modes["main"]).bindings
        let walks: [(String, String, Direction)] = [
            ("alt-cmd-left", "focus left", .left), ("alt-cmd-right", "focus right", .right),
            ("alt-h", "focus left", .left), ("alt-l", "focus right", .right),
        ]
        for (combo, command, direction) in walks {
            let binding = try #require(main[KeyCombo(combo)], "\(combo)")
            #expect(binding.commands == [command])
            #expect(binding.excludeApps.isEmpty)
            #expect(try binding.commands.map(Command.parse) == [.focus(direction)])
        }
        #expect(try main[KeyCombo("alt-j")]?.commands == ["focus down"], "up and down in a column stay")
        #expect(try main[KeyCombo("alt-k")]?.commands == ["focus up"])
    }

    @Test func `Command or Option with the arrows, Home and End, with or without Shift, is left to apps in every mode`() throws {
        // Cmd-Left and Cmd-Right are line start and end in text fields, and Back and Forward in browsers. Option-Left
        // and Option-Right move by a word, and Shift with either selects. Splay 0.3 and earlier took the Cmd keys,
        // and 0.4 took the Option keys.
        #expect(Config.default.modes.keys.sorted() == ["main", "service"])
        for (name, mode) in Config.default.modes {
            for modifier in ["cmd", "alt", "cmd-shift", "alt-shift"] {
                for key in ["left", "right", "home", "end"] {
                    let combo = "\(modifier)-\(key)"
                    #expect(try mode.bindings[KeyCombo(combo)]?.commands == nil, "\(combo) in \(name)")
                }
            }
        }
    }

    @Test func `The strip commands have keys of their own`() throws {
        let main = try #require(Config.default.modes["main"]).bindings
        let expected: [(combo: String, command: String, parsed: Command)] = [
            ("alt-cmd-home", "focus-column first", .focusColumn(.first)),
            ("alt-cmd-end", "focus-column last", .focusColumn(.last)),
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
