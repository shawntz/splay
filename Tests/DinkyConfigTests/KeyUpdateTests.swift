import Foundation
import Testing
@testable import DinkyConfig

/// A config written by an older release keeps that release's keys until someone moves them. These cover what
/// the app offers to move, the text it would write, and every case where it must leave a file alone.
struct KeyUpdateTests {
    private func shipped(_ version: String) throws -> String {
        try #require(Config.shippedDefaults.first { $0.version == version }).toml + "\n"
    }

    private var current: String { Config.defaultTOML + "\n" }

    private func combos(_ names: String...) throws -> [KeyCombo] {
        try names.map { try KeyCombo($0) }
    }

    /// The offer for `text`, or a recorded failure.
    private func offer(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> (update: KeyUpdate, text: String)? {
        guard case .offer(let update, let edited) = Config.keyUpdate(for: text) else {
            Issue.record("expected an offer, got \(Config.keyUpdate(for: text))", sourceLocation: sourceLocation)
            return nil
        }
        return (update, edited)
    }

    // MARK: A file nobody edited

    @Test func `A config as an older release wrote it becomes the current default`() throws {
        for version in ["0.1", "0.2", "0.4"] {
            let result = try #require(offer(try shipped(version)), "\(version)")
            #expect(result.text == current, "\(version)")
            #expect(result.update.own.isEmpty)
        }
    }

    @Test func `The offer for 0.4's config names each command with its new and old keys`() throws {
        let update = try #require(offer(try shipped("0.4"))).update
        #expect(update.moves == [
            KeyMove(mode: "main", command: "focus left", now: try combos("alt-cmd-left", "alt-h"), was: try combos("alt-left")),
            KeyMove(mode: "main", command: "focus right", now: try combos("alt-cmd-right", "alt-l"), was: try combos("alt-right")),
            KeyMove(mode: "main", command: "focus-column first", now: try combos("alt-cmd-home"), was: try combos("alt-home")),
            KeyMove(mode: "main", command: "focus-column last", now: try combos("alt-cmd-end"), was: try combos("alt-end")),
        ])
    }

    @Test func `The offer for 0.2's config moves the keys from Cmd`() throws {
        let update = try #require(offer(try shipped("0.2"))).update
        #expect(update.moves.map(\.was) == [try combos("cmd-left"), try combos("cmd-right"), try combos("cmd-home"), try combos("cmd-end")])
        #expect(update.moves.map(\.now.first) == (try combos("alt-cmd-left", "alt-cmd-right", "alt-cmd-home", "alt-cmd-end")))
    }

    @Test func `A config without its final newline still becomes the current default, without one`() throws {
        let result = try #require(offer(String(try shipped("0.4").dropLast())))
        #expect(result.text == Config.defaultTOML)
    }

    @Test func `The current default has nothing to update, and neither has a config once updated`() throws {
        #expect(Config.keyUpdate(for: current) == .none)
        for version in ["0.1", "0.2", "0.4"] {
            let text = try #require(offer(try shipped(version))).text
            #expect(Config.keyUpdate(for: text) == .none)
        }
    }

    // MARK: A file somebody edited

    @Test func `A changed setting stays, and the rest becomes the current default`() throws {
        for version in ["0.1", "0.2", "0.4"] {
            let mine = "workspaces = 2                  # two Desktops on this Mac"
            let old = "workspaces = 5                  # across all displays, one native Space each"
            let text = try shipped(version).replacingOccurrences(of: old, with: mine)
            #expect(text.contains(mine))
            let result = try #require(offer(text), "\(version)")
            #expect(result.text == current.replacingOccurrences(of: old, with: mine), "\(version)")
        }
    }

    @Test func `Lines the user added stay where they are`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\n# my own keys\nctrl-alt-t = 'exec-and-forget open -a Terminal'\n")
            + "\n# a note at the end\n"
        let result = try #require(offer(text))
        let expected = current
            .replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\n# my own keys\nctrl-alt-t = 'exec-and-forget open -a Terminal'\n")
            + "\n# a note at the end\n"
        #expect(result.text == expected)
    }

    /// The file on the author's own Mac before 0.5: 0.1's header, never updated, over keys and a comment moved
    /// to 0.4's by hand. Each comment Splay wrote is found by its own text, whichever release wrote it.
    @Test func `A config with 0.1's header over 0.4's keys gets the keys and every comment a release rewrote`() throws {
        let schema = "#:schema https://shawntz.github.io/splay/schemas/splay.json\n"
        let newHeader = "# Every command: `splay help`. Every key: https://shawntz.github.io/splay/configuration/"
        let oldHeader = "# Every command: `splay help`, or docs/commands.md in the source. Every key: docs/configuration.md."
        func older(_ text: String) -> String {
            text.replacingOccurrences(of: schema, with: "").replacingOccurrences(of: newHeader, with: oldHeader)
        }
        let text = older(try shipped("0.4"))
        #expect(!text.contains(schema) && text.contains(oldHeader))
        let result = try #require(offer(text))
        #expect(result.text == current)
        // A header line the user rewrote is theirs and stays.
        let mine = text.replacingOccurrences(of: oldHeader, with: "# My keys. See the manual for the rest.")
        let kept = try #require(offer(mine))
        #expect(kept.text == current.replacingOccurrences(of: newHeader, with: "# My keys. See the manual for the rest."))
    }

    /// 0.4's notes said to rename the four keys by hand and left the comment to the reader. The comment above
    /// them is still the one 0.2 wrote.
    @Test func `Keys renamed by hand under an older comment get the current comment with the current keys`() throws {
        var text = try shipped("0.2")
        for (old, new) in [("cmd-left", "alt-left"), ("cmd-right", "alt-right"), ("cmd-home", "alt-home"), ("cmd-end", "alt-end")] {
            text = text.replacingOccurrences(of: "\n\(old) = ", with: "\n\(new) = ")
        }
        #expect(text.contains("\nalt-left = 'focus left'\n") && text.contains("# Cmd-Left and Cmd-Right walk the strip"))
        let result = try #require(offer(text))
        #expect(result.text == current)
    }

    /// What 0.4's manual told people to add for Dinky's keys, in a file that is otherwise an older default.
    @Test func `An older config with Alt-H and Alt-L added by hand is still offered the arrows`() throws {
        var renamed = try shipped("0.2")
        for (old, new) in [("cmd-left", "alt-left"), ("cmd-right", "alt-right"), ("cmd-home", "alt-home"), ("cmd-end", "alt-end")] {
            renamed = renamed.replacingOccurrences(of: "\n\(old) = ", with: "\n\(new) = ")
        }
        for (name, text) in [("0.4", try shipped("0.4")), ("0.2 renamed", renamed), ("0.2", try shipped("0.2"))] {
            let added = text.replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-h = 'focus left'\nalt-l = 'focus right'\n")
            let result = try #require(offer(added), "\(name)")
            #expect(try Config.parse(result.text) == Config.default, "\(name)")
            #expect(result.update.moves.count == 4, "\(name)")
        }
    }

    @Test func `A key keeps the quotes, spacing and comment its line has`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "alt-left = 'focus left'", with: "alt-left    = \"focus left\"   # walks left")
            .replacingOccurrences(of: "alt-right = 'focus right'", with: "\"alt-right\" = [ 'focus right' ]")
        let result = try #require(offer(text))
        #expect(result.text.contains("\nalt-cmd-left    = \"focus left\"   # walks left\n"))
        #expect(result.text.contains("\n\"alt-cmd-right\" = [ 'focus right' ]\n"))
        #expect(try Config.parse(result.text) == Config.default)
    }

    @Test func `A key the user moved within the section is renamed where it stands`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "alt-left = 'focus left'\n", with: "")
            .replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-left = 'focus left'\n")
        let result = try #require(offer(text))
        #expect(result.text.contains("[mode.main]\nalt-cmd-left = 'focus left'\nctrl-left = 'workspace prev'\n"))
        #expect(try Config.parse(result.text) == Config.default)
    }

    @Test func `A moved key written with its modifiers in another order is found and renamed`() throws {
        let old = "[mode.main]\nalt-shift-a = 'retile'", new = "[mode.main]\nalt-shift-b = 'retile'"
        guard case .offer(_, let text) = Config.keyUpdate(for: "[mode.main]\nshift-alt-a = 'retile'\n", defaults: defaults(old, new)) else {
            Issue.record("expected an offer")
            return
        }
        #expect(text == "[mode.main]\nalt-shift-b = 'retile'\n")
        // In a real file, a key that stays, spelled the other way round, is left as it is spelled.
        let spelled = try shipped("0.2").replacingOccurrences(of: "alt-shift-r = 'column-width prev'", with: "shift-alt-r = 'column-width prev'")
        let result = try #require(offer(spelled))
        #expect(try Config.parse(result.text) == Config.default)
        #expect(result.text.contains("\nshift-alt-r = 'column-width prev'\n"))
    }

    @Test func `A mode's header is found with the spaces, quotes and comment TOML allows`() throws {
        for header in ["[mode.\"main\"]", "[ mode . 'main' ]", "[mode.main]   # my keys", "  [mode.main]"] {
            let text = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: header + "\n")
            let result = try #require(offer(text), "\(header)")
            #expect(result.text == current.replacingOccurrences(of: "[mode.main]\n", with: header + "\n"), "\(header)")
        }
    }

    @Test func `A binding in three quotes on one line is passed over like any other`() throws {
        // Four quotes at the end: the command's own closing quote, then the three that close the string.
        let mine = "alt-t = '''exec-and-forget osascript -e 'tell app \"Terminal\" to activate''''\n"
        let text = try shipped("0.4").replacingOccurrences(of: "alt-tab = 'workspace-back-and-forth'\n", with: "alt-tab = 'workspace-back-and-forth'\n" + mine)
        #expect(throws: Never.self) { try Config.parse(text) }
        let result = try #require(offer(text))
        // The key the default adds goes right under the default's line above it, and the user's line follows.
        #expect(result.text.contains("alt-tab = 'workspace-back-and-forth'\nalt-h = 'focus left'\n" + mine))
        #expect(try Config.parse(result.text).modes["main"]?.bindings.count == Config.default.modes["main"]!.bindings.count + 1)
    }

    // MARK: Keys the user removed

    @Test func `A key the user removed is not brought back under its new name`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "alt-home = 'focus-column first'\n", with: "")
            .replacingOccurrences(of: "alt-end = 'focus-column last'\n", with: "")
        let result = try #require(offer(text))
        #expect(result.update.moves.map(\.command) == ["focus left", "focus right"])
        let config = try Config.parse(result.text)
        let main = try #require(config.modes["main"]).bindings
        #expect(main[try KeyCombo("alt-cmd-left")]?.commands == ["focus left"])
        #expect(main[try KeyCombo("alt-h")]?.commands == ["focus left"])
        for gone in ["alt-home", "alt-end", "alt-cmd-home", "alt-cmd-end", "alt-left", "alt-right"] {
            #expect(main[try KeyCombo(gone)] == nil, "\(gone)")
        }
    }

    /// Someone who took the strip off Option-Left and Option-Right must not get it back on other keys.
    @Test func `With the walking keys removed, Alt-H and Alt-L are not added`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "alt-left = 'focus left'\n", with: "")
            .replacingOccurrences(of: "alt-right = 'focus right'\n", with: "")
        let result = try #require(offer(text))
        #expect(result.update.moves.map(\.command) == ["focus-column first", "focus-column last"])
        let main = try #require(try Config.parse(result.text).modes["main"]).bindings
        for absent in ["alt-h", "alt-l", "alt-cmd-left", "alt-cmd-right", "alt-left", "alt-right"] {
            #expect(main[try KeyCombo(absent)] == nil, "\(absent)")
        }
        #expect(main[try KeyCombo("alt-cmd-home")]?.commands == ["focus-column first"])
    }

    @Test func `With every moved key removed there is nothing to offer`() throws {
        var text = try shipped("0.4")
        for line in ["alt-left = 'focus left'", "alt-right = 'focus right'", "alt-home = 'focus-column first'", "alt-end = 'focus-column last'"] {
            text = text.replacingOccurrences(of: line + "\n", with: "")
        }
        #expect(Config.keyUpdate(for: text) == .none)
        #expect(Config.keyUpdate(for: try shipped("0.4").replacingOccurrences(of: "[mode.main]", with: "[mode.mine]")) == .none)
    }

    // MARK: Keys the user bound their own way

    /// The form 0.4's own comment suggests. Moving the other three keys would split left from right.
    @Test func `A moved key the user gave exclude-apps stops the whole update`() throws {
        let text = try shipped("0.4").replacingOccurrences(
            of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
        guard case .manual(let update) = Config.keyUpdate(for: text) else {
            Issue.record("expected no offer, got \(Config.keyUpdate(for: text))")
            return
        }
        #expect(update.own == ["alt-left"])
        #expect(update.taken.isEmpty)
        #expect(update.moves.map(\.command) == ["focus left", "focus right", "focus-column first", "focus-column last"])
        #expect(update.moves.first == KeyMove(mode: "main", command: "focus left", now: try combos("alt-cmd-left", "alt-h"), was: try combos("alt-left")))
    }

    /// What is shown for a file that cannot be changed is what that file has, not everything the defaults moved.
    @Test func `A config left alone is shown only the older keys it has`() throws {
        let text = try shipped("0.4")
            .replacingOccurrences(of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
            .replacingOccurrences(of: "alt-home = 'focus-column first'\n", with: "")
        guard case .manual(let update) = Config.keyUpdate(for: text) else {
            Issue.record("expected no offer, got \(Config.keyUpdate(for: text))")
            return
        }
        #expect(update.moves.map(\.command) == ["focus left", "focus right", "focus-column last"])
        #expect(update.moves.flatMap(\.was) == (try combos("alt-left", "alt-right", "alt-end")))
    }

    @Test func `A new key the user already uses stops the whole update, however it is spelled`() throws {
        let text = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\ncmd-alt-left = 'workspace prev'\n")
        guard case .manual(let update) = Config.keyUpdate(for: text) else {
            Issue.record("expected no offer, got \(Config.keyUpdate(for: text))")
            return
        }
        #expect(update.taken == ["alt-cmd-left"])
        #expect(update.own.isEmpty)
        #expect(update.moves.first == KeyMove(mode: "main", command: "focus left", now: try combos("alt-cmd-left", "alt-h"), was: try combos("alt-left")))
    }

    @Test func `Alt-H in use for something else keeps both Alt-H and Alt-L out, and the arrows still move`() throws {
        let text = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-h = 'layout horizontal'\n")
        let result = try #require(offer(text))
        let main = try #require(try Config.parse(result.text).modes["main"]).bindings
        #expect(main[try KeyCombo("alt-h")]?.commands == ["layout horizontal"])
        #expect(main[try KeyCombo("alt-l")] == nil)
        #expect(main[try KeyCombo("alt-cmd-left")]?.commands == ["focus left"])
        #expect(main[try KeyCombo("alt-cmd-right")]?.commands == ["focus right"])
    }

    @Test func `An old key the user gave to another command is theirs, and nothing is offered for it`() throws {
        var text = try shipped("0.4").replacingOccurrences(of: "alt-left = 'focus left'", with: "alt-left = 'workspace prev'")
        let result = try #require(offer(text))
        let main = try #require(try Config.parse(result.text).modes["main"]).bindings
        #expect(main[try KeyCombo("alt-left")]?.commands == ["workspace prev"])
        #expect(main[try KeyCombo("alt-cmd-left")] == nil)
        #expect(main[try KeyCombo("alt-h")] == nil)
        #expect(main[try KeyCombo("alt-cmd-right")]?.commands == ["focus right"])
        #expect(main[try KeyCombo("alt-l")]?.commands == ["focus right"])
        // With all four given away, the file has no older default key left.
        for (key, command) in [("alt-right", "focus right"), ("alt-home", "focus-column first"), ("alt-end", "focus-column last")] {
            text = text.replacingOccurrences(of: "\(key) = '\(command)'", with: "\(key) = 'retile'")
        }
        #expect(Config.keyUpdate(for: text) == .none)
    }

    // MARK: Files that have seen the current default

    /// Someone who read 0.5's notes and went back to Option-Left. The file still holds lines only 0.5 wrote.
    @Test func `A current config with older keys put back is left alone`() throws {
        let text = current
            .replacingOccurrences(of: "alt-cmd-left = 'focus left'", with: "alt-left = 'focus left'")
            .replacingOccurrences(of: "alt-cmd-right = 'focus right'", with: "alt-right = 'focus right'")
        #expect(Config.keyUpdate(for: text) == .none)
        let stripped = text.replacingOccurrences(of: "alt-h = 'focus left'\n", with: "").replacingOccurrences(of: "alt-l = 'focus right'\n", with: "")
        #expect(Config.keyUpdate(for: stripped) == .none)
    }

    @Test func `A config written by hand with none of a default's lines is left alone`() {
        let text = """
            workspaces = 3
            [mode.main]
            ctrl-h = "focus left"
            ctrl-l = "focus right"

            """
        #expect(Config.keyUpdate(for: text) == .none)
        #expect(Config.keyUpdate(for: "") == .none)
    }

    @Test func `A short config with an older default's key lines is offered the move for the keys it has`() throws {
        let text = """
            [mode.main]
            cmd-left = 'focus left'
            cmd-right = 'focus right'

            """
        let result = try #require(offer(text))
        // The added keys stand before the arrows, as they do in the default.
        #expect(result.text == """
            [mode.main]
            alt-h = 'focus left'
            alt-l = 'focus right'
            alt-cmd-left = 'focus left'
            alt-cmd-right = 'focus right'

            """)
    }

    // MARK: Files it cannot edit

    @Test func `A config that does not parse is reported, not edited`() throws {
        guard case .unreadable(let error) = Config.keyUpdate(for: try shipped("0.4") + "\nnot toml") else {
            Issue.record("expected the parse error")
            return
        }
        #expect(!error.description.isEmpty)
    }

    @Test func `A mode written with dotted keys is not edited`() throws {
        let text = """
            # Alt-Left and Alt-Right walk the strip, so apps no longer get them. Text fields use them to move by a word.
            mode.main.alt-left = 'focus left'
            mode.main.alt-right = 'focus right'

            """
        guard case .manual(let update) = Config.keyUpdate(for: text) else {
            Issue.record("expected no offer, got \(Config.keyUpdate(for: text))")
            return
        }
        #expect(update.own.isEmpty)
        #expect(update.moves.first?.command == "focus left")
    }

    @Test func `A binding whose list runs over several lines is kept whole when a key is added after it`() throws {
        let text = try shipped("0.4").replacingOccurrences(
            of: "alt-tab = 'workspace-back-and-forth'\n", with: "alt-tab = [\n  'workspace-back-and-forth',   # ] in a comment\n]\n")
        let result = try #require(offer(text))
        #expect(result.text.contains("alt-tab = [\n  'workspace-back-and-forth',   # ] in a comment\n]\nalt-h = 'focus left'\nalt-j = 'focus down'\n"))
        #expect(try Config.parse(result.text) == Config.default)
    }

    @Test func `A config with Windows line endings keeps them on every line`() throws {
        let text = try shipped("0.4").replacingOccurrences(of: "workspaces = 5 ", with: "workspaces = 4 ").replacingOccurrences(of: "\n", with: "\r\n")
        let result = try #require(offer(text))
        #expect(!result.text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(!result.text.replacingOccurrences(of: "\r\n", with: "").contains("\r"))
        #expect(result.text.replacingOccurrences(of: "\r\n", with: "\n") == current.replacingOccurrences(of: "workspaces = 5 ", with: "workspaces = 4 "))
    }

    // MARK: Comments

    /// The new comment speaks of Alt-Cmd-Left, Alt-H and Alt-L. A file that ends up without one of them keeps
    /// the comment it has.
    @Test func `The comment above the keys is brought only when the file ends up with all of them`() throws {
        let newComment = "# Alt-Cmd-Left and Alt-Cmd-Right walk the strip, as Alt-H and Alt-L do, so apps no longer get these keys."
        let oldComment = "# Alt-Left and Alt-Right walk the strip, so apps no longer get them. Text fields use them to move by a word."
        let partial = [
            try shipped("0.4").replacingOccurrences(of: "alt-left = 'focus left'\n", with: "").replacingOccurrences(of: "alt-right = 'focus right'\n", with: ""),
            try shipped("0.4").replacingOccurrences(of: "alt-left = 'focus left'", with: "alt-left = 'workspace prev'"),
            try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-h = 'layout horizontal'\n"),
        ]
        for text in partial {
            let result = try #require(offer(text))
            #expect(result.text.contains(oldComment) && !result.text.contains(newComment))
        }
        let whole = try #require(offer(try shipped("0.4").replacingOccurrences(of: "workspaces = 5 ", with: "workspaces = 3 ")))
        #expect(whole.text.contains(newComment) && !whole.text.contains(oldComment))
    }

    @Test func `A comment block the file has twice is left as it is`() throws {
        let lines = try shipped("0.4").components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("# Alt-Left and Alt-Right walk the strip") })
        let block = Array(lines[start..<start + 6])
        // A second copy of the whole block, kept as a note at the end. Which one is the comment cannot be told.
        let text = try shipped("0.4") + "\n" + block.joined(separator: "\n") + "\n"
        let result = try #require(offer(text))
        #expect(result.text.components(separatedBy: "\n").filter { $0 == block[0] }.count == 2)
        #expect(try Config.parse(result.text) == Config.default)
    }

    /// The old comment block sits once in the file, inside a string. Rewriting it there would change a hook, so
    /// the keys move and the comments stay.
    @Test func `An offered text never changes a setting, even when an old comment block sits inside a string`() throws {
        let lines = try shipped("0.4").components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("# Alt-Left and Alt-Right walk the strip") })
        let block = Array(lines[start..<start + 6])
        #expect(block.allSatisfy { $0.hasPrefix("#") })
        var edited = lines
        edited.removeSubrange(start..<start + 6)
        let hook = ["[hooks]", "startup = [\"\"\"exec-and-forget echo '"] + block + ["' \"\"\"]", ""]
        let at = try #require(edited.firstIndex(of: "# Every rule whose conditions all match a new window runs, in order."))
        edited.insert(contentsOf: hook, at: at)
        let text = edited.joined(separator: "\n")
        let before = try Config.parse(text)
        #expect(before.hooks.startup.first?.contains("Alt-Left and Alt-Right walk the strip") == true)
        let result = try #require(offer(text))
        let after = try Config.parse(result.text)
        #expect(after.hooks == before.hooks)
        #expect(after.modes == Config.default.modes)
    }

    @Test func `Lines added to a file take the line ending of the line beside them`() throws {
        // Only the first line ends the Windows way, as after pasting a header from elsewhere.
        let text = try shipped("0.4").replacingOccurrences(of: "splay.json\n", with: "splay.json\r\n")
        let result = try #require(offer(text))
        #expect(result.text.components(separatedBy: "\n").filter { $0.hasSuffix("\r") }.count == 1)
    }

    @Test func `A config indented or saved with trailing spaces is still known for what it is`() throws {
        let trailing = try shipped("0.4").components(separatedBy: "\n").map { $0.isEmpty ? $0 : $0 + "  " }.joined(separator: "\n")
        let first = try #require(offer(trailing))
        #expect(try Config.parse(first.text) == Config.default)
        var inTable = false
        let indented = try shipped("0.4").components(separatedBy: "\n").map { line -> String in
            if line.hasPrefix("[") { inTable = true; return line }
            return inTable && !line.isEmpty ? "    " + line : line
        }.joined(separator: "\n")
        let second = try #require(offer(indented))
        #expect(try Config.parse(second.text) == Config.default)
        #expect(second.text.contains("\n    alt-cmd-left = 'focus left'\n"))
    }

    // MARK: Other shapes of change, with made-up defaults

    private func defaults(_ texts: String...) -> [ShippedDefault] {
        texts.enumerated().map { ShippedDefault(version: "9.\($0.offset)", toml: $0.element) }
    }

    @Test func `A key the default dropped goes, and one it gave another command changes`() throws {
        let old = "[mode.main]\nalt-a = 'retile'\nalt-b = 'fullscreen'\nalt-c = 'center-column'"
        let new = "[mode.main]\nalt-b = 'balance-sizes'\nalt-c = 'center-column'"
        let archive = defaults(old, new)
        guard case .offer(let update, let text) = Config.keyUpdate(for: old + "\n# mine\n", defaults: archive) else {
            Issue.record("expected an offer")
            return
        }
        #expect(text == new + "\n# mine\n")
        #expect(update.moves.map(\.command) == ["balance-sizes", "fullscreen", "retile"])
        // The same file with the dropped key already gone and the changed one the user's own: nothing to do.
        let mine = "[mode.main]\nalt-b = 'layout tiles'\nalt-c = 'center-column'\n"
        #expect(Config.keyUpdate(for: mine, defaults: archive) == .none)
    }

    /// A default that gives a key another command, in a file where the user kept the old command and excluded
    /// an app. Moving the other keys would split the change.
    @Test func `A key the default gave another command, kept by the user with exclude-apps, stops the update`() throws {
        let old = "[mode.main]\nalt-a = 'retile'\nalt-b = 'fullscreen'"
        let new = "[mode.main]\nalt-b = 'balance-sizes'"
        let user = "[mode.main]\nalt-a = 'retile'\nalt-b = { command = 'fullscreen', exclude-apps = ['a.b'] }\n"
        guard case .manual(let update) = Config.keyUpdate(for: user, defaults: defaults(old, new)) else {
            Issue.record("expected no offer, got \(Config.keyUpdate(for: user, defaults: defaults(old, new)))")
            return
        }
        #expect(update.own == ["alt-b"])
    }

    @Test func `Different changes have different names, and so have different reasons to leave a file alone`() throws {
        guard case .offer(let all, _) = Config.keyUpdate(for: try shipped("0.4")),
              case .offer(let some, _) = Config.keyUpdate(for: try shipped("0.4").replacingOccurrences(of: "alt-end = 'focus-column last'\n", with: "")) else {
            Issue.record("expected offers")
            return
        }
        #expect(all.id != some.id)
        func left(_ key: String, _ command: String) throws -> KeyUpdate {
            let text = try shipped("0.4").replacingOccurrences(of: "\(key) = '\(command)'", with: "\(key) = { command = '\(command)', exclude-apps = ['a.b'] }")
            guard case .manual(let update) = Config.keyUpdate(for: text) else { throw ConfigError("expected no offer") }
            return update
        }
        #expect(try left("alt-left", "focus left").id != left("alt-right", "focus right").id)
        #expect(try left("alt-left", "focus left").id == left("alt-left", "focus left").id)
    }

    @Test func `An archive with a default that does not parse offers nothing`() {
        let old = "[mode.main]\nalt-a = 'retile'", new = "[mode.main]\nalt-b = 'retile'"
        #expect(Config.keyUpdate(for: old + "\n", defaults: defaults(old, "not toml", new)) == .none)
        #expect(Config.keyUpdate(for: old + "\n", defaults: []) == .none)
    }

    /// No line of a default but blank ones, which every file has.
    @Test func `Blank lines do not make a file a copy of a default`() {
        let text = "\n[mode.\"main\"]\ncmd-left = 'focus left'\ncmd-right = 'focus right'\n\n"
        #expect(Config.keyUpdate(for: text) == .none)
    }

    @Test func `A key the default only adds never arrives by itself`() throws {
        let old = "[mode.main]\nalt-a = 'retile'"
        let new = "[mode.main]\nalt-a = 'retile'\nalt-b = 'fullscreen'"
        #expect(Config.keyUpdate(for: old + "\n", defaults: defaults(old, new)) == .none)
    }

    @Test func `A move in another mode is found and named with its mode`() throws {
        let old = "[mode.main]\nalt-a = 'mode service'\n\n[mode.service]\nesc = 'mode main'"
        let new = "[mode.main]\nalt-a = 'mode service'\n\n[mode.service]\nenter = 'mode main'"
        let user = old.replacingOccurrences(of: "esc = 'mode main'", with: "esc = { command = 'mode main', exclude-apps = ['a.b'] }")
        guard case .offer(let update, let text) = Config.keyUpdate(for: old + "\n", defaults: defaults(old, new)) else {
            Issue.record("expected an offer")
            return
        }
        #expect(text == new + "\n")
        #expect(update.moves == [KeyMove(mode: "service", command: "mode main", now: try combos("enter"), was: try combos("esc"))])
        guard case .manual(let manual) = Config.keyUpdate(for: user + "\n", defaults: defaults(old, new)) else {
            Issue.record("expected no offer")
            return
        }
        #expect(manual.own == ["service mode, esc"])
    }

    @Test func `A key from any older default is found, and each change has a name of its own`() throws {
        let first = "[mode.main]\nalt-a = 'retile'"
        let second = "[mode.main]\nalt-b = 'retile'"
        let third = "[mode.main]\nalt-c = 'retile'"
        let archive = defaults(first, second, third)
        guard case .offer(let fromFirst, let textFromFirst) = Config.keyUpdate(for: first + "\n", defaults: archive),
              case .offer(let fromSecond, let textFromSecond) = Config.keyUpdate(for: second + "\n", defaults: archive) else {
            Issue.record("expected offers")
            return
        }
        #expect(textFromFirst == third + "\n" && textFromSecond == third + "\n")
        #expect(fromFirst.moves == [KeyMove(mode: "main", command: "retile", now: try combos("alt-c"), was: try combos("alt-a"))])
        #expect(fromSecond.moves == [KeyMove(mode: "main", command: "retile", now: try combos("alt-c"), was: try combos("alt-b"))])
        #expect(fromFirst.id != fromSecond.id)
    }

    /// Keys of two older defaults in one file, as when 0.4's keys were typed in beside 0.2's. One pass settles
    /// both, so the file is asked about once.
    @Test func `Keys from two older defaults for one command leave one key, the current one`() throws {
        let text = try shipped("0.2").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-left = 'focus left'\nalt-right = 'focus right'\n")
        let result = try #require(offer(text))
        #expect(result.update.moves.first == KeyMove(mode: "main", command: "focus left", now: try combos("alt-cmd-left", "alt-h"), was: try combos("alt-left", "cmd-left")))
        #expect(try Config.parse(result.text) == Config.default)
        #expect(result.text.contains("[mode.main]\nalt-cmd-left = 'focus left'\nalt-cmd-right = 'focus right'\nctrl-left"))
        #expect(Config.keyUpdate(for: result.text) == .none)
    }

    /// A comment only the current default has shows the file has seen it. A binding line shows nothing of the
    /// kind: anyone may have typed it.
    @Test func `A comment of the current default means the file has seen it, and a binding of it does not`() throws {
        let old = "[mode.main]\n# walks left\nalt-a = 'focus left'"
        let new = "[mode.main]\n# walks left, on another key\nalt-b = 'focus left'"
        let archive = defaults(old, new)
        // The old key put back under the new comment: a choice.
        #expect(Config.keyUpdate(for: "[mode.main]\n# walks left, on another key\nalt-a = 'focus left'\n", defaults: archive) == .none)
        // The new key typed in beside the old one, under the old comment: the old one is still to move, and the
        // new one is in its way.
        guard case .manual(let update) = Config.keyUpdate(for: old + "\nalt-b = 'focus left'\n", defaults: archive) else {
            Issue.record("expected no offer")
            return
        }
        #expect(update.taken == ["alt-b"])
    }

    /// A later release that changes nothing about these keys must not ask again someone who chose to keep them.
    @Test func `The name of a change does not depend on which release finds it`() throws {
        let old = "[mode.main]\n# walks left\nalt-a = 'focus left'"
        let new = "[mode.main]\n# walks left, on another key\nalt-b = 'focus left'"
        let later = new + "\n# a comment a later release added"
        guard case .offer(let first, _) = Config.keyUpdate(for: old + "\n", defaults: defaults(old, new)),
              case .offer(let second, _) = Config.keyUpdate(for: old + "\n", defaults: defaults(old, new, later)) else {
            Issue.record("expected offers")
            return
        }
        #expect(first.id == second.id)
        #expect(first.id == "main:alt-a>alt-b")
    }

    @Test func `A config with its comments removed still shows its age by its keys`() throws {
        func withoutComments(_ text: String) -> String {
            text.components(separatedBy: "\n").filter { !$0.hasPrefix("#") }.joined(separator: "\n")
        }
        for version in ["0.2", "0.4"] {
            let result = try #require(offer(withoutComments(try shipped(version))), "\(version)")
            #expect(result.text == withoutComments(current), "\(version)")
        }
        #expect(Config.keyUpdate(for: withoutComments(current)) == .none)
    }

    /// Alt-H and Alt-L typed in by hand, as Dinky has them, in a file that is otherwise 0.4's.
    @Test func `Alt-H and Alt-L already in the file do not hide that the arrows are still to move`() throws {
        let text = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-h = 'focus left'\nalt-l = 'focus right'\n")
        let result = try #require(offer(text))
        #expect(result.update.moves.map(\.now) == [try combos("alt-cmd-left", "alt-h"), try combos("alt-cmd-right", "alt-l"), try combos("alt-cmd-home"), try combos("alt-cmd-end")])
        #expect(result.update.moves.map(\.was) == [try combos("alt-left", "alt-h"), try combos("alt-right", "alt-l"), try combos("alt-home"), try combos("alt-end")])
        #expect(try Config.parse(result.text) == Config.default)
        #expect(result.text.contains("[mode.main]\nalt-h = 'focus left'\nalt-l = 'focus right'\nctrl-left"))
    }

    // MARK: Whatever the file, the text offered is safe

    /// A small repeatable generator, so a failure names a seed that fails again.
    private struct Random {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    @Test func `Whatever edits a config has, an offered text parses, keeps the user's own lines in order and needs no second update`() throws {
        let replacements = [
            "alt-left = { command = 'focus left', exclude-apps = ['a.b'] }", "alt-h = 'retile'", "cmd-alt-left = 'retile'",
            "# a comment of mine", "alt-x = 'retile'", "alt-cmd-home = 'focus-column first'", "", "alt-left = \"focus left\"",
            "cmd-left = 'focus left'", "alt-l = 'focus right'", "ctrl-left = 'workspace next'",
        ]
        var offers = 0
        for version in ["0.1", "0.2", "0.4"] {
            let base = try shipped(version).components(separatedBy: "\n")
            let shippedLines = Set(base)
            for seed in 0..<150 {
                var random = Random(state: UInt64(seed) &* 7919 &+ 17)
                var lines = base
                for _ in 0..<(1 + random.next(6)) {
                    // Mostly in the bindings, where the update works.
                    let at = random.next(4) == 0 ? random.next(lines.count) : lines.count - 1 - random.next(min(70, lines.count))
                    switch random.next(4) {
                    case 0: lines.remove(at: at)
                    case 1: lines.insert(replacements[random.next(replacements.count)], at: at)
                    case 2: lines[at] = replacements[random.next(replacements.count)]
                    default: lines.swapAt(at, max(0, at - 1 - random.next(5)))
                    }
                }
                let text = lines.joined(separator: "\n")
                guard case .offer(let update, let edited) = Config.keyUpdate(for: text) else { continue }
                offers += 1
                let label = "\(version) seed \(seed)"
                let before = try Config.parse(text)
                let after = try #require(try? Config.parse(edited), "\(label) does not parse")
                #expect(!update.moves.isEmpty, "\(label)")
                // Nothing but the main mode's bindings differs.
                var sameElsewhere = after
                sameElsewhere.modes["main"] = before.modes["main"]
                #expect(sameElsewhere == before, "\(label)")
                // Every binding is the user's or the current default's.
                let mine = before.modes["main"]?.bindings ?? [:], new = Config.default.modes["main"]!.bindings
                // A key the user had keeps its binding. Any other key is one the update names, and has the
                // current default's binding or the binding of the key it replaces.
                for (combo, binding) in after.modes["main"]?.bindings ?? [:] where binding != mine[combo] {
                    let move = update.moves.first { $0.now.contains(combo) }
                    #expect(move != nil, "\(label) \(combo) appeared from nowhere")
                    #expect(binding == new[combo] || (move?.was ?? []).contains { mine[$0] == binding }, "\(label) \(combo)")
                }
                // Every line that was the user's own is still there, in order. A moved key's line is renamed,
                // so it is left out here; the config comparison above covers it.
                let moved = Set(update.moves.flatMap(\.was))
                func binds(_ line: String) -> KeyCombo? {
                    let key = line.prefix { $0 != "=" }.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    return line.contains("=") ? try? KeyCombo(key) : nil
                }
                var own = lines.filter { line in !shippedLines.contains(line) && !(binds(line).map(moved.contains) ?? false) }[...]
                for line in edited.components(separatedBy: "\n") where line == own.first { own = own.dropFirst() }
                #expect(own.isEmpty, "\(label) lost \(own.first ?? "")")
                #expect(Config.keyUpdate(for: edited) == .none, "\(label) wants a second update")
            }
        }
        #expect(offers > 45, "the edits should leave many configs with something to offer, got \(offers)")
    }

    @Test func `Hunks turn one text into the other`() {
        let cases: [([String], [String])] = [
            ([], []), (["a"], []), ([], ["a"]), (["a", "b", "c"], ["a", "x", "c"]), (["a", "b", "c"], ["x", "a", "b", "c", "y"]),
            (["a", "b", "c", "d"], ["b", "d"]), (["a", "a", "b"], ["a", "b", "a"]),
        ]
        for (base, other) in cases {
            var lines = base
            for hunk in lineHunks(from: base, to: other).reversed() {
                lines.replaceSubrange(hunk.range, with: hunk.lines)
            }
            #expect(lines == other, "\(base) to \(other)")
        }
    }
}
