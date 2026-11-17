import AppKit
import Foundation
import Testing
@testable import DinkyConfig
@testable import dinky

/// The ask about keys an older default wrote: what it says, what it remembers and what it writes. No window is
/// put on screen; the content is built and read.
@MainActor
struct KeyUpdatePromptTests {
    /// Whether this process can make a window at all. A test run over ssh, with nobody logged in, cannot, and
    /// AppKit raises when asked to.
    private static let hasWindowServer = CGSessionCopyCurrentDictionary() != nil

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "splay-prompt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Answers kept in memory, so no test writes a preferences file.
    private final class Memory: AnswerStore {
        var values: [String: Any] = [:]
        func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private func shipped(_ version: String) throws -> String {
        try #require(Config.shippedDefaults.first { $0.version == version }).toml + "\n"
    }

    private func update(_ text: String) throws -> (KeyUpdateCheck, KeyUpdate) {
        let check = Config.keyUpdate(for: text)
        switch check {
        case .offer(let update, _), .manual(let update): return (check, update)
        default: throw ConfigFile.Failure(description: "nothing to update: \(check)")
        }
    }

    private func labels(in view: NSView) -> [String] {
        view.subviews.flatMap { sub -> [String] in
            if let button = sub as? NSButton { return [button.title] }
            if let field = sub as? NSTextField { return [field.stringValue] }
            return labels(in: sub)
        }
    }

    @Test func `Combos read as macOS menus write shortcuts`() throws {
        let expected = [
            "alt-cmd-left": "⌥⌘←", "alt-h": "⌥H", "alt-cmd-home": "⌥⌘Home", "ctrl-alt-shift-cmd-right": "⌃⌥⇧⌘→",
            "alt-shift-semicolon": "⌥⇧;", "cmd-page-up": "⌘Page Up", "esc": "Esc", "alt-f5": "⌥F5", "alt-1": "⌥1", "alt-minus": "⌥-",
        ]
        for (combo, symbols) in expected {
            #expect(try KeyCombo(combo).symbols == symbols, "\(combo)")
        }
    }

    @Test func `The rows name each command with its keys now and before`() throws {
        let rows = KeyUpdateText.rows(try update(try shipped("0.4")).1)
        #expect(rows.map(\.command) == ["focus left", "focus right", "focus-column first", "focus-column last"])
        #expect(rows.map(\.now) == ["⌥⌘← and ⌥H", "⌥⌘→ and ⌥L", "⌥⌘Home", "⌥⌘End"])
        #expect(rows.map(\.was) == ["was ⌥←", "was ⌥→", "was ⌥Home", "was ⌥End"])
        #expect(KeyUpdateText.rows(try update(try shipped("0.2")).1).map(\.was) == ["was ⌘←", "was ⌘→", "was ⌘Home", "was ⌘End"])
    }

    @Test func `The window offers both answers and says where the old file goes`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prompt = KeyUpdatePrompt(url: dir.appending(path: "splay.toml"), store: defaults, version: "0.6")
        let (check, update) = try update(try shipped("0.4"))
        let content = prompt.content(for: check, update, asked: false)
        let texts = labels(in: content)
        #expect(texts.first == "Some of Splay's keys have moved")
        #expect(texts.contains("Your config still has the keys an earlier version came with."))
        #expect(texts.contains("Use the New Keys changes these keys in splay.toml. The file as it is now stays in the same folder, as splay.toml.before-0.6."))
        #expect(texts.contains("Apps no longer get the new keys while Splay runs. Chrome and Firefox switch tabs with ⌥⌘← and ⌥⌘→, and iTerm2 and Ghostty move between panes with them. To leave a key to an app, add exclude-apps to its line in splay.toml."))
        #expect(texts.contains("⌥H and ⌥L will no longer type characters in apps. To keep typing with them, delete the alt-h and alt-l lines from splay.toml afterwards."))
        #expect(Array(texts.suffix(3)) == ["Use the New Keys", "Keep My Keys", "What Changed"])
        for row in ["focus left", "⌥⌘← and ⌥H", "was ⌥←"] { #expect(texts.contains(row), "\(row)") }
        // The whole of it fits the window's width.
        content.layoutSubtreeIfNeeded()
        #expect(content.fittingSize.width <= 480)
        #expect(content.fittingSize.height > 150)
    }

    @Test func `A config with a line of its own for a moved key is told why it was left alone`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prompt = KeyUpdatePrompt(url: dir.appending(path: "splay.toml"), store: defaults, version: "0.6")
        let text = try shipped("0.4").replacingOccurrences(
            of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
        let (check, update) = try update(text)
        let texts = labels(in: prompt.content(for: check, update, asked: false))
        #expect(texts.contains("splay.toml lists exclude-apps for alt-left, so Splay changed nothing. To move the keys, edit the file."))
        #expect(Array(texts.suffix(2)) == ["OK", "What Changed"])
        #expect(!texts.contains("Use the New Keys"))
    }

    @Test func `Each reason a config was left alone has its own words`() throws {
        let file = "splay.toml", copy = "splay.toml.before-0.6"
        func closing(_ text: String) throws -> [String] {
            KeyUpdateText.closing(try update(text).0, file: file, copy: copy)
        }
        let taken = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-cmd-left = 'workspace prev'\n")
        #expect(try closing(taken) == ["splay.toml already binds alt-cmd-left, so Splay changed nothing. To move the keys, edit the file."])
        let both = taken.replacingOccurrences(of: "alt-right = 'focus right'", with: "alt-right = { command = 'focus right', exclude-apps = ['a.b'] }")
            .replacingOccurrences(of: "alt-end = 'focus-column last'", with: "alt-end = { command = 'focus-column last', exclude-apps = ['a.b'] }")
        #expect(try closing(both) == ["splay.toml lists exclude-apps for alt-right and alt-end and already binds alt-cmd-left, so Splay changed nothing. To move the keys, edit the file."])
        let dotted = "# Alt-Left and Alt-Right walk the strip, so apps no longer get them. Text fields use them to move by a word.\nmode.main.alt-left = 'focus left'\n"
        #expect(try closing(dotted) == ["splay.toml binds these keys in a form that can't be edited for you, so Splay changed nothing. To move the keys, edit the file."])
    }

    /// Option-Command with an arrow types nothing, so only the letter keys are named. One key reads in the singular.
    @Test func `The offer says what the new keys take from apps, and which of them stop typing characters`() throws {
        let file = "splay.toml", copy = "splay.toml.before-0.6"
        let apps = "Apps no longer get the new keys while Splay runs."
        let leave = "To leave a key to an app, add exclude-apps to its line in splay.toml."
        // Alt-H and Alt-L are in the file already, so only the arrows arrive, and those type nothing.
        let hasBoth = try shipped("0.4").replacingOccurrences(of: "[mode.main]\n", with: "[mode.main]\nalt-h = 'focus left'\nalt-l = 'focus right'\n")
        #expect(KeyUpdateText.closing(try update(hasBoth).0, file: file, copy: copy).dropFirst()
            == ["\(apps) Chrome and Firefox switch tabs with ⌥⌘← and ⌥⌘→, and iTerm2 and Ghostty move between panes with them. \(leave)"])
        // Only Home and End move: no app is known to use those, and nothing new types a character.
        let endsOnly = try shipped("0.4").replacingOccurrences(of: "alt-left = 'focus left'\n", with: "").replacingOccurrences(of: "alt-right = 'focus right'\n", with: "")
        #expect(KeyUpdateText.closing(try update(endsOnly).0, file: file, copy: copy).dropFirst() == ["\(apps) \(leave)"])
        // One key that types, and one arrow, read in the singular.
        let one = KeyUpdate(id: "x", parts: ["x"], moves: [
            KeyMove(mode: "main", command: "focus left", now: [try KeyCombo("alt-cmd-left"), try KeyCombo("alt-h")], was: [try KeyCombo("alt-left")]),
        ], own: [], taken: [])
        #expect(KeyUpdateText.closing(.offer(one, text: ""), file: file, copy: copy).dropFirst() == [
            "\(apps) Chrome and Firefox switch tabs with ⌥⌘←, and iTerm2 and Ghostty move between panes with them. \(leave)",
            "⌥H will no longer type a character in apps. To keep typing with it, delete the alt-h line from splay.toml afterwards.",
        ])
        #expect(try KeyCombo("alt-shift-semicolon").typesWithOption)
        for combo in ["alt-left", "alt-cmd-h", "ctrl-alt-l", "alt-home", "alt-f5", "h"] {
            #expect(try !KeyCombo(combo).typesWithOption, "\(combo)")
        }
    }

    /// The window comes up by itself at launch. Whatever is being typed then must not answer it.
    @Test func `Return presses nothing in a window nobody asked for, and Use the New Keys in one opened from the menu`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        #expect(buttons(in: try #require(screen.shown.last)).map(\.keyEquivalent) == ["", "", ""])
        prompt.ask()
        #expect(buttons(in: try #require(screen.shown.last)).map(\.keyEquivalent) == ["\r", "", ""])
        #expect(buttons(in: try #require(screen.shown.last)).first?.title == "Use the New Keys")
    }

    @Test(.enabled(if: hasWindowServer)) func `The window fits its content, and closing it forgets what it asked`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { _ in }
        let (check, update) = try update(try shipped("0.4"))
        let content = prompt.content(for: check, update, asked: true)
        // Made and sized, never put on screen.
        let window = prompt.window(with: content)
        #expect(window.contentView === content)
        #expect(window.title == "Splay")
        #expect(abs(window.contentRect(forFrameRect: window.frame).width - 480) < 1)
        #expect(window.contentRect(forFrameRect: window.frame).height >= content.fittingSize.height - 1)
        #expect(!window.isVisible)
        #expect(prompt.window(with: content) === window)
        window.close()
        #expect(prompt.window(with: content) !== window)
    }

    @Test func `Using the new keys rewrites the file and keeps the old one`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6")
        #expect(prompt.menuItem()?.title == "Use Splay's New Keys…")
        let copy = try prompt.apply()
        #expect(try String(contentsOf: url, encoding: .utf8) == Config.defaultTOML + "\n")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6")
        #expect(try String(contentsOf: copy, encoding: .utf8) == (try shipped("0.4")))
        // Nothing is left to offer, in the menu or by asking again.
        #expect(prompt.menuItem() == nil)
        #expect(throws: ConfigFile.Failure.self) { try prompt.apply() }
    }

    @Test func `A current config has no menu item, and a missing one neither`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6")
        #expect(prompt.menuItem() == nil)
        try (Config.defaultTOML + "\n").write(to: url, atomically: false, encoding: .utf8)
        #expect(prompt.menuItem() == nil)
    }

    @Test func `The menu item follows the file as it is saved`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try (Config.defaultTOML + "\n").write(to: url, atomically: true, encoding: .utf8)
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6")
        #expect(prompt.menuItem() == nil)
        // A dotfiles checkout puts an older file in place while the app runs.
        try shipped("0.2").write(to: url, atomically: true, encoding: .utf8)
        #expect(prompt.menuItem() != nil)
    }

    /// A prompt on a config of its own, with what it would have put in its window collected in `shown`.
    private final class Screen {
        var shown: [NSStackView] = []
    }

    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons(in: $0) }
    }

    /// Presses the button with this title in what was shown last, as a click on it would.
    private func press(_ title: String, on screen: Screen) throws {
        let content = try #require(screen.shown.last)
        let button = try #require(buttons(in: content).first { $0.title == title }, "no \(title) button")
        let target = try #require(button.target as? NSObject)
        let action = try #require(button.action)
        _ = target.perform(action, with: button)
    }

    @Test func `At launch an older config is asked about, and Keep My Keys is remembered`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        #expect(screen.shown.count == 1)
        try press("Keep My Keys", on: screen)
        #expect(try String(contentsOf: url, encoding: .utf8) == (try shipped("0.4")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["splay.toml"])
        // The next launches say nothing, on this prompt or on a new one as after a restart.
        prompt.askIfNew()
        KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }.askIfNew()
        #expect(screen.shown.count == 1)
        // The menu still offers it, and asking there shows the window again.
        #expect(prompt.menuItem() != nil)
        prompt.ask()
        #expect(screen.shown.count == 2)
    }

    @Test func `A window closed without an answer comes back at the next launch`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.2").write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }.askIfNew()
        KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }.askIfNew()
        #expect(screen.shown.count == 2)
    }

    @Test func `Use the New Keys in the window writes the file, and nothing is asked afterwards`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        try press("Use the New Keys", on: screen)
        #expect(try String(contentsOf: url, encoding: .utf8) == Config.defaultTOML + "\n")
        #expect(try String(contentsOf: dir.appending(path: "splay.toml.before-0.6"), encoding: .utf8) == (try shipped("0.4")))
        prompt.askIfNew()
        #expect(screen.shown.count == 1)
        #expect(prompt.menuItem() == nil)
    }

    /// The file is saved with other keys while the window is open: the window shows what would move now, and
    /// writes nothing until that is answered.
    @Test func `A file that changed under the window is shown again before anything is written`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: true, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        let edited = try shipped("0.4").replacingOccurrences(of: "alt-home = 'focus-column first'\n", with: "")
        try edited.write(to: url, atomically: true, encoding: .utf8)
        try press("Use the New Keys", on: screen)
        #expect(screen.shown.count == 2)
        #expect(try String(contentsOf: url, encoding: .utf8) == edited)
        #expect(!labels(in: try #require(screen.shown.last)).contains("focus-column first"))
        try press("Use the New Keys", on: screen)
        let main = try #require(try Config.load(from: url).modes["main"]).bindings
        #expect(main[try KeyCombo("alt-cmd-left")]?.commands == ["focus left"])
        #expect(main[try KeyCombo("alt-cmd-home")] == nil)
    }

    /// The file is saved with exclude-apps on one of the keys while the window is open. Use the New Keys then
    /// says why nothing can be changed, and writes nothing.
    @Test func `A file that can no longer be changed says so when Use the New Keys is pressed`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: true, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        let own = try shipped("0.4").replacingOccurrences(
            of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
        try own.write(to: url, atomically: true, encoding: .utf8)
        try press("Use the New Keys", on: screen)
        #expect(screen.shown.count == 2)
        let texts = labels(in: try #require(screen.shown.last))
        #expect(texts.contains("splay.toml lists exclude-apps for alt-left, so Splay changed nothing. To move the keys, edit the file."))
        #expect(!texts.contains("Use the New Keys"))
        #expect(try String(contentsOf: url, encoding: .utf8) == own)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["splay.toml"])
        // It has been told now, so the next launch says nothing.
        KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }.askIfNew()
        #expect(screen.shown.count == 2)
    }

    /// The window names the copy that will really be made, which has a number when the plain name is in use.
    @Test func `The window names the copy the old file will get`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: true, encoding: .utf8)
        try "an older file of mine\n".write(to: dir.appending(path: "splay.toml.before-0.6"), atomically: true, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        #expect(labels(in: try #require(screen.shown.last)).contains { $0.hasSuffix("stays in the same folder, as splay.toml.before-0.6-2.") })
        try press("Use the New Keys", on: screen)
        #expect(try String(contentsOf: dir.appending(path: "splay.toml.before-0.6-2"), encoding: .utf8) == (try shipped("0.4")))
        #expect(try String(contentsOf: dir.appending(path: "splay.toml.before-0.6"), encoding: .utf8) == "an older file of mine\n")
    }

    @Test func `A config Splay cannot change is told so once`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        let own = try shipped("0.4").replacingOccurrences(
            of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
        try own.write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        prompt.askIfNew()
        #expect(screen.shown.count == 1)
        #expect(prompt.menuItem() == nil)
        try press("OK", on: screen)
        #expect(try String(contentsOf: url, encoding: .utf8) == own)
    }

    @Test func `A current config, a broken one and a missing one are not asked about`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        for text in [Config.defaultTOML + "\n", try shipped("0.4") + "not toml\n"] {
            try text.write(to: url, atomically: true, encoding: .utf8)
            prompt.askIfNew()
        }
        #expect(screen.shown.isEmpty)
    }

    @Test func `A file that cannot be written says why and stays as it was`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: false, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        try press("Use the New Keys", on: screen)
        #expect(screen.shown.count == 2)
        let failure = labels(in: try #require(screen.shown.last))
        #expect(failure.first == "Splay could not change splay.toml")
        #expect(failure.contains { $0.hasPrefix("Splay can't write in ") && $0.hasSuffix(". macOS says \"Permission denied\". Nothing was written.") })
        #expect(try String(contentsOf: url, encoding: .utf8) == (try shipped("0.4")))
    }

    /// A save that keeps the file's size and puts its date back, as `cp -p` and `rsync -t` do.
    @Test func `The menu item follows a save that keeps the file's size and date`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.2").write(to: url, atomically: false, encoding: .utf8)
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { _ in }
        #expect(prompt.menuItem() != nil)
        let date = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        // The same length, and no older keys under a mode Splay reads.
        try shipped("0.2").replacingOccurrences(of: "[mode.main]", with: "[mode.mine]").write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        #expect(prompt.menuItem() == nil)
    }

    @Test func `An answer is remembered for that change only`() throws {
        let defaults = Memory()
        let answers = KeyUpdateAnswers(store: defaults)
        let fromFour = try update(try shipped("0.4")).1, fromTwo = try update(try shipped("0.2")).1
        #expect(!answers.cover(fromFour))
        answers.add(fromFour)
        answers.add(fromFour)
        #expect(answers.cover(fromFour))
        #expect(!answers.cover(fromTwo))
        #expect(defaults.stringArray(forKey: KeyUpdateAnswers.key) == fromFour.parts)
        #expect(fromFour.parts.count == 4)
    }

    /// The answer was for each of the four keys. With one of them gone from the file, the other three are
    /// still answered for.
    @Test func `Keys kept are not asked about again when one of them is removed later`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try shipped("0.4").write(to: url, atomically: true, encoding: .utf8)
        let screen = Screen()
        let prompt = KeyUpdatePrompt(url: url, store: defaults, version: "0.6") { screen.shown.append($0) }
        prompt.askIfNew()
        try press("Keep My Keys", on: screen)
        // Later: an unrelated setting changes, and one of the kept keys goes.
        let edited = try shipped("0.4").replacingOccurrences(of: "workspaces = 5 ", with: "workspaces = 3 ")
            .replacingOccurrences(of: "alt-end = 'focus-column last'\n", with: "")
        try edited.write(to: url, atomically: true, encoding: .utf8)
        prompt.askIfNew()
        #expect(screen.shown.count == 1)
        #expect(prompt.menuItem() != nil)
    }

    @Test func `Doctor names the older keys and where to move them`() throws {
        let old = Config.keyUpdate(for: try shipped("0.4"))
        #expect(KeyUpdateText.doctorNote(old, file: "splay.toml", inMenu: true)
            == "splay.toml has keys from an older default: alt-left, alt-right, alt-home, alt-end. To move them, choose Use Splay's New Keys in Splay's menu.")
        // A file the app does not read has no menu item to point to.
        #expect(KeyUpdateText.doctorNote(old, file: "other.toml", inMenu: false)
            == "other.toml has keys from an older default: alt-left, alt-right, alt-home, alt-end.")
        let own = try shipped("0.4").replacingOccurrences(of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['a.b'] }")
        #expect(KeyUpdateText.doctorNote(Config.keyUpdate(for: own), file: "splay.toml", inMenu: true)
            == "splay.toml has keys from an older default: alt-left, alt-right, alt-home, alt-end. The app does not move them, because splay.toml lists exclude-apps for alt-left.")
        #expect(KeyUpdateText.doctorNote(Config.keyUpdate(for: Config.defaultTOML), file: "splay.toml", inMenu: true) == nil)
        #expect(KeyUpdateText.doctorNote(Config.keyUpdate(for: "not toml"), file: "splay.toml", inMenu: true) == nil)
    }

    /// Writes the window's content as pictures for a person to look at: `SPLAY_PROMPT_PICTURES=<folder> swift test`.
    @Test(.enabled(if: hasWindowServer)) func `The window's content can be drawn`() throws {
        let dir = try directory()
        let defaults = Memory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prompt = KeyUpdatePrompt(url: dir.appending(path: "splay.toml"), store: defaults, version: "0.6")
        let own = try shipped("0.4").replacingOccurrences(
            of: "alt-left = 'focus left'", with: "alt-left = { command = 'focus left', exclude-apps = ['com.google.Chrome'] }")
        for (file, text) in [("offer-0.4", try shipped("0.4")), ("offer-0.2", try shipped("0.2")), ("own-line", own)] {
            let (check, update) = try update(text)
            let content = prompt.content(for: check, update, asked: file == "offer-0.2")
            let size = NSSize(width: 480, height: content.fittingSize.height)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = content
            content.layoutSubtreeIfNeeded()
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            // Drawn at the window's width, with every row and both paragraphs on it.
            #expect(bitmap.size.width == 480)
            #expect(bitmap.size.height == content.fittingSize.height)
            if let folder = ProcessInfo.processInfo.environment["SPLAY_PROMPT_PICTURES"] {
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appending(path: "\(file).png"))
            }
        }
    }
}
