import AppKit
import DinkyConfig

// A release that moves default keys reaches nobody who already has a config: the file is written once, with
// every binding in it. So after an update the keys in the notes do nothing, and the old ones still work.
//
// At launch the app compares the config with the defaults Splay has shipped (KeyUpdate.swift in DinkyConfig). When
// the file still has keys an older default wrote, a window lists what moved and asks. Use the New Keys rewrites
// those lines and keeps the file as it was beside it. Keep My Keys is remembered, so the window does not come
// back for the same keys, and the menu keeps an item that brings it back. Nothing is written without the ask:
// people chose their keys, and a new key takes a shortcut away from the apps that used it.
//
// The window comes up by itself, so at launch it takes no focus and Return presses nothing in it. Someone typing
// in another app when it appears must not answer it by accident.

extension KeyCombo {
    /// The combo as macOS menus write a shortcut: `⌥⌘←`, `⌥H`, `⌥⌘Home`.
    var symbols: String {
        var text = ""
        if modifiers.contains(.ctrl) { text += "⌃" }
        if modifiers.contains(.alt) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.cmd) { text += "⌘" }
        if let name = KeyCombo.symbolNames[key] { return text + name }
        // `h` is H, `page-up` is Page Up, `f5` is F5.
        return text + (key.count == 1 ? key.uppercased() : key.split(separator: "-").map(\.capitalized).joined(separator: " "))
    }

    private static let symbolNames = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "Return", "esc": "Esc", "backspace": "Delete",
        "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'",
        "backslash": "\\", "left-bracket": "[", "right-bracket": "]", "backtick": "`", "section": "§",
    ]

    /// Whether Option with this key types a character in apps: Option, with or without Shift, and a letter, a
    /// digit or a punctuation key.
    var typesWithOption: Bool {
        modifiers.contains(.alt) && modifiers.subtracting([.alt, .shift]).isEmpty
            && (key.count == 1 || (KeyCombo.symbolNames[key]?.count == 1 && !["left", "right", "up", "down"].contains(key)))
    }
}

/// What the key update says, kept apart from the window so tests can read it.
enum KeyUpdateText {
    static let heading = "Some of \(Brand.displayName)'s keys have moved"
    static let intro = "Your config still has the keys an earlier version came with."
    static let use = "Use the New Keys"
    static let keep = "Keep My Keys"
    static let changes = "What Changed"
    static let menuItem = "Use \(Brand.displayName)'s New Keys…"

    /// One row per command: the command, its keys now and the keys it had.
    static func rows(_ update: KeyUpdate) -> [(command: String, now: String, was: String)] {
        update.moves.map { move in
            (move.mode == "main" ? move.command : "\(move.command), \(move.mode) mode",
             move.now.isEmpty ? "no key" : list(move.now.map(\.symbols)),
             move.was.isEmpty ? "new" : "was \(list(move.was.map(\.symbols)))")
        }
    }

    /// The sentences under the rows. `file` is the config's name and `copy` the name the old file is kept under.
    static func closing(_ check: KeyUpdateCheck, file: String, copy: String) -> [String] {
        switch check {
        case .offer(let update, _):
            var paragraphs = ["\(use) changes these keys in \(file). The file as it is now stays in the same folder, as \(copy)."]
            let arrived = update.moves.flatMap { move in move.now.filter { !move.was.contains($0) } }
            // What the new keys take from apps. A key Splay binds never reaches the app in front.
            var taking = "Apps no longer get the new keys while \(Brand.displayName) runs."
            for (keys, use) in knownUses {
                let found = arrived.filter { keys.contains($0.description) }
                if !found.isEmpty { taking += " " + use(list(found.map(\.symbols))) }
            }
            paragraphs.append(taking + " To leave a key to an app, add exclude-apps to its line in \(file).")
            // Keys that come new and that Option types a character with, such as @ on a German layout.
            let typed = arrived.filter(\.typesWithOption)
            if !typed.isEmpty {
                let one = typed.count == 1
                paragraphs.append("\(list(typed.map(\.symbols))) will no longer type \(one ? "a character" : "characters") in apps. "
                    + "To keep typing with \(one ? "it" : "them"), delete the \(list(typed.map(\.description))) \(one ? "line" : "lines") from \(file) afterwards.")
            }
            return paragraphs
        case .manual(let update):
            return ["\(reason(update, file: file)), so \(Brand.displayName) changed nothing. To move the keys, edit the file."]
        case .none, .unreadable:
            return []
        }
    }

    /// Apps known to use a key themselves, so the window can say what moving to it costs. The keys are given
    /// as the config spells them, and the sentence takes them as symbols.
    private static let knownUses: [(keys: [String], use: (String) -> String)] = [
        (["alt-cmd-left", "alt-cmd-right"],
         { "Chrome and Firefox switch tabs with \($0), and iTerm2 and Ghostty move between panes with them." }),
    ]

    /// Why a file was left alone, as the start of a sentence: `splay.toml lists exclude-apps for alt-left`.
    private static func reason(_ update: KeyUpdate, file: String) -> String {
        var parts: [String] = []
        if !update.own.isEmpty { parts.append("lists exclude-apps for \(list(update.own))") }
        if !update.taken.isEmpty { parts.append("already binds \(list(update.taken))") }
        return parts.isEmpty ? "\(file) binds these keys in a form that can't be edited for you" : "\(file) \(parts.joined(separator: " and "))"
    }

    /// What `doctor` says about a config that still has an older default's keys; nil for any other config.
    /// `inMenu` is whether the app reads this file, so that its menu can move the keys.
    static func doctorNote(_ check: KeyUpdateCheck, file: String, inMenu: Bool) -> String? {
        switch check {
        case .offer(let update, _):
            "\(file) has keys from an older default: \(old(update))."
                + (inMenu ? " To move them, choose \(menuItem.dropLast()) in \(Brand.displayName)'s menu." : "")
        case .manual(let update):
            "\(file) has keys from an older default: \(old(update)). The app does not move them, because \(reason(update, file: file))."
        case .none, .unreadable:
            nil
        }
    }

    private static func old(_ update: KeyUpdate) -> String {
        update.moves.flatMap(\.was).map(\.description).joined(separator: ", ")
    }

    /// `a`, `a and b`, `a, b and c`.
    private static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}

/// Where answers are kept: the app's preferences, or a dictionary in tests.
protocol AnswerStore: AnyObject {
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: AnswerStore {}

/// The key updates the user has answered on this Mac, so each is asked about once.
struct KeyUpdateAnswers {
    static let key = "key-update-answered"
    let store: AnswerStore

    func has(_ id: String) -> Bool {
        (store.stringArray(forKey: Self.key) ?? []).contains(id)
    }

    func add(_ id: String) {
        guard !has(id) else { return }
        store.set((store.stringArray(forKey: Self.key) ?? []) + [id], forKey: Self.key)
    }

    /// Whether every part of an update has been answered.
    func cover(_ update: KeyUpdate) -> Bool {
        update.parts.allSatisfy(has)
    }

    func add(_ update: KeyUpdate) {
        update.parts.forEach(add)
    }
}

final class KeyUpdatePrompt: NSObject, NSWindowDelegate {
    static let shared = KeyUpdatePrompt()

    private let url: URL
    private let answers: KeyUpdateAnswers
    /// The app's version, which names the copy of the old file.
    private let version: String
    private var window: NSWindow?
    /// Shows the window's content in place of a window, so tests can read it and press its buttons.
    private let presenter: ((NSStackView) -> Void)?
    /// What the window on screen asks about.
    private var asking: KeyUpdate?
    /// The last reading of the file, kept until the file changes.
    private var read: (stamp: Stamp, data: Data, check: KeyUpdateCheck)?

    /// What tells one saved state of the file from the next.
    private struct Stamp: Equatable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modified: [Int]
        let changed: [Int]
    }

    /// Started through the command line's link, the process has no bundle of its own. Its answers still belong
    /// with the app's, and the copy of the old file is still named for the app's version.
    static var appDefaults: UserDefaults {
        Bundle.main.bundleIdentifier == Brand.bundleID ? .standard : UserDefaults(suiteName: Brand.bundleID) ?? .standard
    }

    static var appVersion: String {
        let info = Bundle.main.executableURL.flatMap(bundleInfo(ofExecutable:)) ?? Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    init(url: URL = Config.userConfigURL, store: AnswerStore = KeyUpdatePrompt.appDefaults, version: String = KeyUpdatePrompt.appVersion,
         presenter: ((NSStackView) -> Void)? = nil) {
        self.url = url
        answers = KeyUpdateAnswers(store: store)
        self.version = version
        self.presenter = presenter
    }

    /// The config's bytes and what could be updated in it. Nil when the file can't be read.
    func current() -> (data: Data, check: KeyUpdateCheck)? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let stamp = Stamp(device: info.st_dev, inode: UInt64(info.st_ino), size: Int64(info.st_size),
                          modified: [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec],
                          changed: [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec])
        if let read, read.stamp == stamp { return (read.data, read.check) }
        guard let data = FileManager.default.contents(atPath: url.path), let text = String(data: data, encoding: .utf8) else { return nil }
        let check = Config.keyUpdate(for: text)
        read = (stamp, data, check)
        return (data, check)
    }

    /// Asks once the app is up. While another window of the app's is open, such as the one that asks for
    /// Accessibility or Sparkle's, this one waits, so neither covers the other.
    func askAtLaunch(after seconds: Double = 1, waits: Int = 30) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            // A window among ordinary windows and dialogs. The menu bar item's own window is not one.
            let busy = NSApp.windows.contains {
                $0.isVisible && $0.styleMask.contains(.titled) && $0.level.rawValue <= NSWindow.Level.modalPanel.rawValue && $0 !== window
            }
            // For a minute at most, so a window that is there to stay cannot keep this one from ever showing.
            if busy, waits > 0 { askAtLaunch(after: 2, waits: waits - 1) } else { askIfNew() }
        }
    }

    /// Asks about an update nobody has answered yet. One that cannot be made is explained once.
    func askIfNew() {
        guard let check = current()?.check else { return }
        switch check {
        case .offer(let update, _) where !answers.cover(update):
            show(check, update, asked: false)
        case .manual(let update) where !answers.cover(update):
            answers.add(update)
            show(check, update, asked: false)
        default:
            break
        }
    }

    /// The menu's item while the config has older keys that can be moved, whatever was answered before.
    func menuItem() -> NSMenuItem? {
        guard case .offer = current()?.check else { return nil }
        let item = NSMenuItem(title: KeyUpdateText.menuItem, action: #selector(ask), keyEquivalent: "")
        item.target = self
        return item
    }

    /// The menu item's action: asks again, whatever was answered before.
    @objc func ask() {
        guard let check = current()?.check, case .offer(let update, _) = check else { return }
        show(check, update, asked: true)
    }

    /// Moves the keys in the file, as the update read from it now says. Returns the copy of the old file.
    /// Throws when the file has nothing to move any more, or cannot be written.
    @discardableResult
    func apply() throws(ConfigFile.Failure) -> URL {
        read = nil
        guard let (data, check) = current(), case .offer(_, let text) = check else {
            throw ConfigFile.Failure(description: "\(url.lastPathComponent) has no older keys to move any more. Nothing was written.")
        }
        defer { read = nil }
        return try ConfigFile.replace(url, with: text, expecting: data, label: version)
    }

    // MARK: Window

    @objc private func useNewKeys() {
        // The file may have been saved while the window was open. If what would move has changed, or the file
        // can no longer be changed, show that and write nothing yet.
        read = nil
        guard let check = current()?.check else { return close() }
        guard case .offer(let update, _) = check, update == asking else {
            switch check {
            case .offer(let now, _):
                show(check, now, asked: true)
            case .manual(let now):
                answers.add(now)
                show(check, now, asked: true)
            case .none, .unreadable:
                close()
            }
            return
        }
        do {
            let copy = try apply()
            let keys = update.moves.flatMap(\.was).count
            print("config: moved \(keys) older \(keys == 1 ? "key" : "keys") to the current defaults; the file as it was is \(copy.path)")
            close()
        } catch {
            fputs("config: could not move the keys: \(error)\n", stderr)
            present(Self.content(heading: "\(Brand.displayName) could not change \(url.lastPathComponent)", paragraphs: ["\(error)"],
                                 rows: [], buttons: [button("OK", #selector(done))], returnPressesFirst: true), asked: true)
        }
    }

    @objc private func keepKeys() {
        if let asking { answers.add(asking) }
        close()
    }

    @objc private func done() {
        close()
    }

    @objc private func showChanges() {
        if let page = URL(string: Brand.changelogURL) { NSWorkspace.shared.open(page) }
    }

    private func show(_ check: KeyUpdateCheck, _ update: KeyUpdate, asked: Bool) {
        asking = update
        present(content(for: check, update, asked: asked), asked: asked)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    /// What the window shows for a check: the offer with its two answers, or why the file was left alone.
    /// `asked` is whether the user opened it from the menu. Then Return presses its first button.
    func content(for check: KeyUpdateCheck, _ update: KeyUpdate, asked: Bool) -> NSStackView {
        let file = url.lastPathComponent
        var buttons = [button("OK", #selector(done))]
        if case .offer = check {
            buttons = [button(KeyUpdateText.use, #selector(useNewKeys)), button(KeyUpdateText.keep, #selector(keepKeys))]
        }
        // The name the old file will be kept under, which has a number on it when that name is in use.
        let copy = ConfigFile.copyName(for: url, holding: current()?.data ?? Data(), label: version)
        return Self.content(heading: KeyUpdateText.heading,
                            paragraphs: [KeyUpdateText.intro] + KeyUpdateText.closing(check, file: file, copy: copy),
                            rows: KeyUpdateText.rows(update), buttons: buttons + [button(KeyUpdateText.changes, #selector(showChanges))],
                            returnPressesFirst: asked)
    }

    /// A heading, the first paragraph, the rows as a table, the remaining paragraphs and a row of buttons.
    static func content(heading: String, paragraphs: [String], rows: [(command: String, now: String, was: String)],
                        buttons: [NSButton], returnPressesFirst: Bool) -> NSStackView {
        func paragraph(_ text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.preferredMaxLayoutWidth = textWidth
            label.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
            return label
        }
        let title = NSTextField(labelWithString: heading)
        title.font = .boldSystemFont(ofSize: 15)
        var views: [NSView] = [title]
        views.append(contentsOf: paragraphs.prefix(1).map(paragraph))
        if !rows.isEmpty {
            let grid = NSGridView(views: rows.map { row in
                let was = NSTextField(labelWithString: row.was)
                was.textColor = .secondaryLabelColor
                return [NSTextField(labelWithString: row.command), NSTextField(labelWithString: row.now), was]
            })
            grid.rowSpacing = 6
            grid.columnSpacing = 18
            // As wide as its text and no wider, or the last column drifts to the window's far edge.
            grid.setContentHuggingPriority(.required, for: .horizontal)
            views.append(grid)
        }
        views.append(contentsOf: paragraphs.dropFirst().map(paragraph))
        if returnPressesFirst { buttons.first?.keyEquivalent = "\r" }
        views.append(NSStackView(views: buttons))
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    private static let textWidth: CGFloat = 440

    /// The window with this content, made on first use and sized to the content.
    func window(with content: NSStackView) -> NSWindow {
        let window = self.window ?? {
            let made = PromptWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            made.title = Brand.displayName
            made.isReleasedWhenClosed = false
            made.delegate = self
            return made
        }()
        self.window = window
        window.contentView = content
        window.setContentSize(NSSize(width: Self.textWidth + 40, height: content.fittingSize.height))
        return window
    }

    private func present(_ content: NSStackView, asked: Bool) {
        if let presenter { return presenter(content) }
        let window = window(with: content)
        if !window.isVisible { window.center() }
        if asked {
            window.level = .normal
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // Nobody asked for this window. It stays above the windows being tiled and takes no keys, so what
            // is being typed elsewhere goes on going there.
            window.level = .floating
            window.orderFrontRegardless()
        }
    }

    private func close() {
        asking = nil
        window?.close()
    }

    /// Closing the window without an answer leaves the question for the next launch.
    func windowWillClose(_ notification: Notification) {
        window = nil
        asking = nil
    }
}

/// A window that Escape closes, as it closes a dialog.
private final class PromptWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
