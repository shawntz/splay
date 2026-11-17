import Foundation

// Finding the default keys a config still has from an older release, and the text that moves them.
//
// The app writes the default config once, with every binding spelled out, and a mode's bindings are exactly what
// the file says. So a release that moves a default key reaches nobody who already has a file. This compares a
// file with the default it came from (ShippedDefaults.swift) and works out what the defaults changed since. The
// app then asks before it writes anything.
//
// - How old a file is, is read off its lines: the newest release that first wrote any comment or other line the
//   file still has, bindings aside. A file with such a line of the current default has seen it, and is left
//   alone: its older keys were put back on purpose. Binding lines prove nothing of the kind, since anyone may
//   type one.
// - An older key is one the file binds exactly as that release, or a later one before the current, did, and
//   that the current default has since moved. It moves only when its new key is free. A line the user removed
//   stays removed, and a key the user gave another command stays theirs.
// - A file that binds one of the keys involved its own way gets no change at all, so a pair such as focus left
//   and focus right is never split between old and new keys. The app says so instead.
// - Only binding lines change, and the comment blocks a default rewrote when the file still has them whole. A
//   file nobody edited comes out as the current default that way. No setting is added or changed.
// - Before any text is offered it must parse to exactly the config that was meant: the user's, with those
//   bindings moved and nothing else different.

/// What the defaults changed for one command since a config was written.
public struct KeyMove: Equatable {
    public var mode: String
    /// The command as the config spells it, `focus left`. Several commands on one key are joined with `; `.
    public var command: String
    /// The keys it has in the current default, the ones that replace old keys first.
    public var now: [KeyCombo]
    /// The keys the older default gave it.
    public var was: [KeyCombo]
}

public struct KeyUpdate: Equatable {
    /// Names this exact set of changes, whatever release finds it, so an answer to it can be remembered.
    public var id: String
    /// The commands whose older keys the file has, each with those keys and the keys the default gives it now.
    public var moves: [KeyMove]
    /// Older keys the file binds its own way, to the same command with apps excluded: `alt-left`, or
    /// `service mode, esc` outside the main mode. With any of these, or any of `taken`, nothing can be changed.
    public var own: [String]
    /// New keys the file already uses while it still has the older key.
    public var taken: [String]
}

public enum KeyUpdateCheck: Equatable {
    /// The file has no keys an older default wrote, or it was never a copy of a default.
    case none
    /// The file has older default keys, and `text` is the file with them moved.
    case offer(KeyUpdate, text: String)
    /// The file has older default keys and binds some of the keys involved its own way.
    case manual(KeyUpdate)
    /// The file does not parse, so there is nothing to compare.
    case unreadable(ConfigError)
}

extension Config {
    /// What the defaults changed since the config in `text` was written.
    public static func keyUpdate(for text: String) -> KeyUpdateCheck {
        keyUpdate(for: text, defaults: shippedDefaults)
    }

    /// `defaults` is every shipped default, oldest first, the last being the current one.
    static func keyUpdate(for text: String, defaults: [ShippedDefault]) -> KeyUpdateCheck {
        let shipped = defaults.compactMap(DefaultText.init)
        guard shipped.count == defaults.count, let current = shipped.last else { return .none }
        let user: Config
        do {
            user = try parse(text)
        } catch {
            return .unreadable(error)
        }
        let lines = text.components(separatedBy: "\n")
        let past = Array(shipped.dropLast())
        guard let seen = seenIndex(of: lines, in: shipped), seen < past.count else { return .none }
        // The defaults the file may still have keys from: the one it has seen and those between it and now.
        let plan = KeyPlan(older: Array(past[seen...]), past: past, current: current, user: user)
        guard !plan.edits.isEmpty || !plan.own.isEmpty || !plan.taken.isEmpty else { return .none }
        guard plan.own.isEmpty, plan.taken.isEmpty else {
            let id = "own \(plan.own.joined(separator: ",")) taken \(plan.taken.joined(separator: ","))"
            return .manual(KeyUpdate(id: id, moves: plan.heldMoves, own: plan.own, taken: plan.taken))
        }
        let wanted = plan.wanted
        let moves = keyMoves(from: user, to: wanted, order: current)
        let update = KeyUpdate(id: moves.map { "\($0.mode):\(names($0.was))>\(names($0.now))" }.joined(separator: " "),
                               moves: moves, own: [], taken: [])
        // With the comments brought up to date if that leaves the config what was meant, else without. A
        // comment block the file holds inside a string, say, is not a comment there.
        for comments in [true, false] {
            if let edited = plan.apply(to: lines, comments: comments), (try? parse(edited)) == wanted {
                return .offer(update, text: edited)
            }
        }
        // The lines could not be changed safely, as with a mode written as an inline table.
        return .manual(KeyUpdate(id: "unplaced " + update.id, moves: plan.heldMoves, own: [], taken: []))
    }

    /// The index of the newest default that first wrote a line the file still has; nil when the file holds no
    /// line of any default. Blank lines do not count, and neither do binding lines.
    private static func seenIndex(of lines: [String], in shipped: [DefaultText]) -> Int? {
        // Without the space around them, so a file that was indented or saved with trailing spaces still counts.
        func trimmed(_ lines: [String]) -> Set<String> {
            Set(lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        let mine = trimmed(lines)
        var earlier = Set<String>()
        var seen: Int?
        for (index, text) in shipped.enumerated() {
            let introduced = trimmed(text.lines.filter { isSignificant($0) && !text.bindingLines.contains($0) }).subtracting(earlier)
            if !introduced.isDisjoint(with: mine) { seen = index }
            earlier.formUnion(trimmed(text.lines))
        }
        return seen
    }

    /// One move per command whose keys differ between two configs, in the order the commands stand in `order`.
    private static func keyMoves(from old: Config, to new: Config, order: DefaultText) -> [KeyMove] {
        var moves: [KeyMove] = []
        // The main mode first, then the others by name.
        let modes = Set(old.modes.keys).union(new.modes.keys).sorted { ($0 == "main" ? 0 : 1, $0) < ($1 == "main" ? 0 : 1, $1) }
        for mode in modes {
            let before = old.modes[mode]?.bindings ?? [:], after = new.modes[mode]?.bindings ?? [:]
            func command(_ binding: KeyBinding) -> String { binding.commands.joined(separator: "; ") }
            // Commands in the order of their first key in the default, then the rest by name.
            let place = Dictionary(order.order(mode).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            func sorted(_ combos: [KeyCombo]) -> [KeyCombo] {
                combos.sorted { (place[$0] ?? Int.max, $0.description) < (place[$1] ?? Int.max, $1.description) }
            }
            func keys(_ bindings: [KeyCombo: KeyBinding], of name: String) -> [KeyCombo] {
                sorted(bindings.keys.filter { command(bindings[$0]!) == name })
            }
            var commands: [String] = []
            for name in sorted(Array(after.keys)).map({ command(after[$0]!) }) + sorted(Array(before.keys)).map({ command(before[$0]!) })
            where !commands.contains(name) {
                commands.append(name)
            }
            for name in commands {
                let was = keys(before, of: name), now = keys(after, of: name)
                guard Set(was) != Set(now) else { continue }
                // New keys read first, and among them one that takes over an old key's name, `left` for `left`.
                // Keys that go read first among the old ones.
                let gone = was.filter { !now.contains($0) }, arrived = now.filter { !was.contains($0) }
                let replacing = arrived.filter { combo in gone.contains { $0.key == combo.key } }
                moves.append(KeyMove(mode: mode, command: name,
                                     now: replacing + arrived.filter { !replacing.contains($0) } + now.filter(was.contains),
                                     was: gone + was.filter(now.contains)))
            }
        }
        return moves
    }

    fileprivate static func names(_ combos: [KeyCombo]) -> String {
        combos.map(\.description).joined(separator: ",")
    }
}

private func isSignificant(_ line: String) -> Bool {
    !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// A line without the carriage return a file with Windows line endings leaves on it.
private func withoutReturn(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
}

/// A line without what follows its last visible character: spaces, tabs and a carriage return.
private func withoutTrailingSpace(_ line: String) -> String {
    var end = line.endIndex
    while end > line.startIndex, [" ", "\t", "\r"].contains(line[line.index(before: end)]) { end = line.index(before: end) }
    return String(line[..<end])
}

/// The carriage return a line of a file with Windows line endings carries, for a line added next to it.
private func ending(of line: String?) -> String {
    line?.hasSuffix("\r") == true ? "\r" : ""
}

/// The lines of each `[mode.<name>]` section, from the line after its header to the next table's header. A mode
/// written another way, with dotted keys or as an inline table, has no section here.
private func modeSections(_ lines: [String]) -> [String: Range<Int>] {
    var sections: [String: Range<Int>] = [:]
    var open: (name: String, start: Int)?
    func close(at index: Int) {
        if let open, sections[open.name] == nil { sections[open.name] = open.start..<index }
    }
    for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
        close(at: index)
        open = modeName(inHeader: line).map { ($0, index + 1) }
    }
    close(at: lines.count)
    return sections
}

/// `main` for `[mode.main]`, with the spaces, quotes and comment TOML allows; nil for any other line.
private func modeName(inHeader line: String) -> String? {
    var rest = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
    func skipSpaces() { rest = rest.drop { $0 == " " || $0 == "\t" } }
    func eat(_ text: String) -> Bool {
        guard rest.hasPrefix(text) else { return false }
        rest = rest.dropFirst(text.count)
        skipSpaces()
        return true
    }
    guard eat("["), eat("mode"), eat(".") else { return nil }
    let name: Substring
    if let quote = rest.first, quote == "'" || quote == "\"" {
        let body = rest.dropFirst()
        guard let end = body.firstIndex(of: quote) else { return nil }
        name = body[..<end]
        rest = body[end...].dropFirst()
    } else {
        name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        rest = rest.dropFirst(name.count)
    }
    skipSpaces()
    guard !name.isEmpty, eat("]"), rest.isEmpty || rest.hasPrefix("#") else { return nil }
    return String(name)
}

/// The key a line binds as it is written, between any quotes, when the line starts a binding.
private func keyToken(of line: String) -> Range<String.Index>? {
    guard let first = line.firstIndex(where: { $0 != " " && $0 != "\t" }), let equals = line.firstIndex(of: "="), first < equals,
          line[first] != "#", line[first] != "[" else { return nil }
    var token = first..<equals
    while token.lowerBound < token.upperBound, let last = line[token].last, last == " " || last == "\t" {
        token = token.lowerBound..<line.index(before: token.upperBound)
    }
    if let quote = line[token].first, quote == "'" || quote == "\"", line[token].count >= 2, line[token].last == quote {
        token = line.index(after: token.lowerBound)..<line.index(before: token.upperBound)
    }
    return token.isEmpty ? nil : token
}

private func boundCombo(_ line: String) -> KeyCombo? {
    keyToken(of: line).flatMap { try? KeyCombo(String(line[$0])) }
}

/// The last line of the value that follows `=` on line `start`: that line, or the one that closes a list opened
/// on it. Nil when it cannot tell, as with a string that runs over several lines.
private func lastLine(ofValueAt start: Int, in lines: [String]) -> Int? {
    var depth = 0
    var index = start
    var rest = Substring(lines[start]).drop { $0 != "=" }.dropFirst()
    while true {
        var quote: Character?
        var escaped = false
        var position = rest.startIndex
        scan: while position < rest.endIndex {
            let character = rest[position]
            defer { position = rest.index(after: position) }
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\", open == "\"" {
                    escaped = true
                } else if character == open {
                    quote = nil
                }
                continue
            }
            switch character {
            case "'", "\"":
                let triple = String(repeating: character, count: 3)
                if rest[position...].hasPrefix(triple) {
                    // A string in three quotes may run over lines. One that also ends on this line does not.
                    let body = rest[position...].dropFirst(3)
                    guard let close = body.range(of: triple) else { return nil }
                    // Up to two more of the same quote may belong to the string before its closing three.
                    var end = close.upperBound
                    while end < body.endIndex, body[end] == character { end = body.index(after: end) }
                    position = rest.index(before: end)
                    continue
                }
                quote = character
            case "#": break scan
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        guard quote == nil, depth >= 0 else { return nil }
        if depth == 0 { return index }
        index += 1
        guard index < lines.count else { return nil }
        rest = Substring(lines[index])
    }
}

/// The bindings of a section: for each combo, the lines its binding takes.
private func boundLines(_ lines: [String], in section: Range<Int>) -> [KeyCombo: ClosedRange<Int>]? {
    var bound: [KeyCombo: ClosedRange<Int>] = [:]
    var index = section.lowerBound
    while index < section.upperBound {
        guard let combo = boundCombo(lines[index]) else {
            index += 1
            continue
        }
        guard let end = lastLine(ofValueAt: index, in: lines), end < section.upperBound, bound[combo] == nil else { return nil }
        bound[combo] = index...end
        index = end + 1
    }
    return bound
}

private func isComment(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
}

/// A shipped default, read once: its lines, its config and the line that binds each key.
private struct DefaultText {
    let version: String
    /// Without the final newline, as `Config.defaultTOML` is.
    let toml: String
    let lines: [String]
    let config: Config
    let sections: [String: Range<Int>]
    /// By mode and combo, the line that binds it.
    let bindings: [String: [KeyCombo: String]]
    /// Every line that binds a key.
    let bindingLines: Set<String>

    init?(_ shipped: ShippedDefault) {
        guard let config = try? Config.parse(shipped.toml) else { return nil }
        version = shipped.version
        toml = shipped.toml
        lines = shipped.toml.components(separatedBy: "\n")
        self.config = config
        sections = modeSections(lines)
        var bindings: [String: [KeyCombo: String]] = [:]
        for (mode, range) in sections {
            for line in lines[range] {
                if let combo = boundCombo(line) { bindings[mode, default: [:]][combo] = line }
            }
        }
        self.bindings = bindings
        bindingLines = Set(bindings.values.flatMap(\.values))
    }

    /// The combos of a mode in the order their lines stand.
    func order(_ mode: String) -> [KeyCombo] {
        sections[mode].map { lines[$0].compactMap(boundCombo) } ?? []
    }
}

private struct KeyEdit {
    enum Kind: Equatable {
        /// The line keeps its command and gets this key.
        case rename(to: KeyCombo)
        /// The current default's line for the combo is added.
        case add
        /// The line goes.
        case remove
        /// The line becomes the current default's line for the combo.
        case replace
    }

    let mode: String
    let combo: KeyCombo
    let kind: Kind
}

/// What the change of defaults from each of `older` to `current` means for one user's bindings.
private struct KeyPlan {
    /// The defaults the file may still have keys from, oldest first.
    let older: [DefaultText]
    /// Every default before the current one, oldest first. The file may hold a comment block of any of them.
    let past: [DefaultText]
    let current: DefaultText
    let user: Config
    private(set) var edits: [KeyEdit] = []
    /// Older keys the user binds their own way, to the same command with apps excluded.
    private(set) var own: [String] = []
    /// New keys the user already binds while still having the older key.
    private(set) var taken: [String] = []
    /// The older keys the file has, by mode: each with the binding the default gave it.
    private(set) var held: [String: [KeyCombo: KeyBinding]] = [:]

    init(older: [DefaultText], past: [DefaultText], current: DefaultText, user: Config) {
        self.older = older
        self.past = past
        self.current = current
        self.user = user
        var modes = Set(current.config.modes.keys)
        for text in older { modes.formUnion(text.config.modes.keys) }
        for mode in modes.sorted() { plan(mode) }
    }

    /// One move per command the file has an older key for: those keys, and the keys the current default gives
    /// the command.
    var heldMoves: [KeyMove] {
        var moves: [KeyMove] = []
        for mode in held.keys.sorted(by: { ($0 == "main" ? 0 : 1, $0) < ($1 == "main" ? 0 : 1, $1) }) {
            let new = current.config.modes[mode]?.bindings ?? [:]
            let order = current.order(mode)
            var commands: [[String]] = []
            let keys = (held[mode] ?? [:]).keys.sorted { $0.description < $1.description }
            for combo in keys {
                guard let commandList = held[mode]?[combo]?.commands, !commands.contains(commandList) else { continue }
                commands.append(commandList)
            }
            for commandList in commands {
                let was = keys.filter { held[mode]?[$0]?.commands == commandList }
                let all = order.filter { new[$0]?.commands == commandList }
                let replacing = all.filter { combo in was.contains { $0.key == combo.key } }
                moves.append(KeyMove(mode: mode, command: commandList.joined(separator: "; "),
                                     now: replacing + all.filter { !replacing.contains($0) }, was: was))
            }
        }
        // In the order the commands stand in the current default.
        func place(_ move: KeyMove) -> Int {
            move.now.compactMap { current.order(move.mode).firstIndex(of: $0) }.min() ?? Int.max
        }
        return moves.enumerated().sorted { a, b in
            (a.element.mode == "main" ? 0 : 1, a.element.mode, place(a.element), a.offset) < (b.element.mode == "main" ? 0 : 1, b.element.mode, place(b.element), b.offset)
        }.map(\.element)
    }

    private mutating func plan(_ mode: String) {
        let new = current.config.modes[mode]?.bindings ?? [:]
        let mine = user.modes[mode]?.bindings ?? [:]
        // Only lines that are bindings, so each has its binding below.
        let newOrder = current.order(mode).filter { new[$0] != nil }
        func label(_ combo: KeyCombo) -> String { mode == "main" ? "\(combo)" : "\(mode) mode, \(combo)" }

        var planned: [KeyEdit] = []
        var extras: [KeyCombo] = []
        var settled = Set<KeyCombo>(), given = Set<KeyCombo>()
        // The newest default first: a key is judged by the latest default that had it.
        for text in older.reversed() {
            let old = text.config.modes[mode]?.bindings ?? [:]
            let oldOrder = text.order(mode).filter { old[$0] != nil }
            let added = newOrder.filter { old[$0] == nil }
            // A key the current default dropped and a key it added for the same command are one move, by
            // preference the same key under other modifiers: alt-left to alt-cmd-left rather than to alt-h.
            var target: [KeyCombo: KeyCombo] = [:]
            for from in oldOrder where new[from] == nil {
                let free = added.filter { new[$0] == old[from] && !target.values.contains($0) }
                if let to = free.first(where: { $0.key == from.key }) ?? free.first { target[from] = to }
            }
            var moved: [KeyBinding] = []
            for combo in oldOrder where !settled.contains(combo) {
                guard let binding = old[combo], new[combo] != binding, let have = mine[combo] else { continue }
                guard have == binding else {
                    // Given to another command, it is the user's and nothing here concerns it. The same command
                    // with apps excluded is the user's own version of the old key.
                    if have.commands == binding.commands, have != new[combo] {
                        own.append(label(combo))
                        settled.insert(combo)
                        held[mode, default: [:]][combo] = binding
                    }
                    continue
                }
                settled.insert(combo)
                held[mode, default: [:]][combo] = binding
                if new[combo] != nil {
                    planned.append(KeyEdit(mode: mode, combo: combo, kind: .replace))
                } else if let to = target[combo], !given.contains(to) {
                    if mine[to] == nil {
                        planned.append(KeyEdit(mode: mode, combo: combo, kind: .rename(to: to)))
                        given.insert(to)
                        moved.append(binding)
                    } else {
                        // The new key is in use, even if for the same command: the user has been here.
                        taken.append(label(to))
                    }
                } else {
                    // Dropped with nothing in its place, or a still older key for a command that has moved.
                    planned.append(KeyEdit(mode: mode, combo: combo, kind: .remove))
                }
            }
            // A key the current default adds beside a moved one, such as alt-h for focus left.
            extras.append(contentsOf: added.filter { combo in
                !target.values.contains(combo) && !extras.contains(combo) && (new[combo].map(moved.contains) ?? false)
            })
        }
        // Such keys come along with the move. They never arrive on their own, and none arrive when the user
        // uses one of them already.
        extras.removeAll(where: given.contains)
        if extras.allSatisfy({ mine[$0] == nil }) {
            planned.append(contentsOf: newOrder.filter(extras.contains).map { KeyEdit(mode: mode, combo: $0, kind: .add) })
        }
        edits.append(contentsOf: planned)
    }

    /// The user's config with the edits made.
    var wanted: Config {
        var config = user
        for edit in edits {
            var bindings = config.modes[edit.mode]?.bindings ?? [:]
            let new = current.config.modes[edit.mode]?.bindings ?? [:]
            switch edit.kind {
            case .rename(let to): bindings[to] = bindings.removeValue(forKey: edit.combo)
            case .add, .replace: bindings[edit.combo] = new[edit.combo]
            case .remove: bindings[edit.combo] = nil
            }
            config.modes[edit.mode, default: Mode()].bindings = bindings
        }
        return config
    }

    /// The file's lines with the edits made, joined again. Nil when a line to change cannot be found.
    func apply(to original: [String], comments: Bool) -> String? {
        var lines = original
        for edit in edits {
            guard let section = modeSections(lines)[edit.mode], let bound = boundLines(lines, in: section) else { return nil }
            let line = current.bindings[edit.mode]?[edit.combo]
            switch edit.kind {
            case .rename(let to):
                guard let at = bound[edit.combo]?.lowerBound, let token = keyToken(of: lines[at]) else { return nil }
                lines[at].replaceSubrange(token, with: to.description)
            case .replace:
                guard let range = bound[edit.combo], let line else { return nil }
                lines.replaceSubrange(range, with: [line + ending(of: lines[range.upperBound])])
            case .remove:
                guard let range = bound[edit.combo] else { return nil }
                lines.removeSubrange(range)
            case .add:
                guard let line else { return nil }
                let at = place(for: edit.combo, in: edit.mode, section: section, bound: bound, of: lines)
                // The line ending of the line it is put after, or of the one it is put before.
                let neighbour = at > 0 ? lines[at - 1] : at < lines.count ? lines[at] : nil
                lines.insert(line + ending(of: neighbour), at: at)
            }
        }
        if comments { swapComments(in: &lines) }
        return lines.joined(separator: "\n")
    }

    /// Where a key the default adds goes: after the nearest key above it in the default that the file binds,
    /// else before the nearest below, else at the end of the section's lines.
    private func place(for combo: KeyCombo, in mode: String, section: Range<Int>, bound: [KeyCombo: ClosedRange<Int>], of lines: [String]) -> Int {
        let order = current.order(mode)
        let at = order.firstIndex(of: combo) ?? order.count
        if let above = order[..<at].last(where: { bound[$0] != nil }) { return bound[above]!.upperBound + 1 }
        if let below = order[at...].dropFirst().first(where: { bound[$0] != nil }) { return bound[below]!.lowerBound }
        return (lines[section].lastIndex(where: isSignificant) ?? section.lowerBound - 1) + 1
    }

    /// Brings the comments the default rewrote: a block the file still has whole, once, becomes the new block,
    /// and a comment the default added goes above the line it was added above. Comments the user changed stay.
    ///
    /// A comment under a mode describes that mode's keys. It is brought only when the file ends up with every
    /// key that release's default has since moved, so no comment speaks of keys the file does not have.
    private func swapComments(in lines: inout [String]) {
        let result = wanted
        // The newest default first. A file may hold one default's block in one place and an older one's in
        // another, and each is found by its own text.
        for base in past.reversed() {
            // The modes in which the file now has the current default's binding for every key that changed.
            let complete = Set(base.sections.keys.filter { mode in
                let old = base.config.modes[mode]?.bindings ?? [:], new = current.config.modes[mode]?.bindings ?? [:]
                let mine = result.modes[mode]?.bindings ?? [:]
                return Set(old.keys).union(new.keys).allSatisfy { old[$0] == new[$0] || mine[$0] == new[$0] }
            })
            for hunk in lineHunks(from: base.lines, to: current.lines).reversed() {
                if let mode = base.sections.first(where: { $0.value.contains(hunk.range.lowerBound) || $0.value.upperBound == hunk.range.lowerBound })?.key,
                   !complete.contains(mode) { continue }
                let old = Array(base.lines[hunk.range])
                if old.isEmpty {
                    // Added lines. Only comments, and only when the line they were added above is there once.
                    guard hunk.lines.allSatisfy(isComment), hunk.range.lowerBound < base.lines.count,
                          !lines.map(withoutTrailingSpace).contains(hunk.lines[0]),
                          let at = onlyIndex(of: [base.lines[hunk.range.lowerBound]], in: lines) else { continue }
                    lines.insert(contentsOf: hunk.lines.map { $0 + ending(of: lines[at]) }, at: at)
                    continue
                }
                let was = runs(old), now = runs(hunk.lines)
                guard was.map(\.comment) == now.map(\.comment) else { continue }
                // Later runs first, so the earlier ones' places hold.
                for (before, after) in zip(was, now).reversed() where before.comment {
                    guard let at = onlyIndex(of: before.lines, in: lines) else { continue }
                    let end = ending(of: lines[at])
                    lines.replaceSubrange(at..<at + before.lines.count, with: after.lines.map { $0 + end })
                }
            }
        }
    }

    /// Lines split into runs of comment lines and runs of other lines.
    private func runs(_ lines: [String]) -> [(comment: Bool, lines: [String])] {
        var runs: [(comment: Bool, lines: [String])] = []
        for line in lines {
            if runs.last?.comment == isComment(line) {
                runs[runs.count - 1].lines.append(line)
            } else {
                runs.append((isComment(line), [line]))
            }
        }
        return runs
    }

    /// Where `block` stands in `lines` as consecutive lines, when it does so exactly once.
    private func onlyIndex(of block: [String], in lines: [String]) -> Int? {
        guard !block.isEmpty, lines.count >= block.count else { return nil }
        let plain = lines.map(withoutTrailingSpace)
        let found = (0...(plain.count - block.count)).filter { Array(plain[$0..<$0 + block.count]) == block }
        return found.count == 1 ? found[0] : nil
    }
}

/// A change to a text's lines: those at `range` are replaced by `lines`. An empty range adds `lines` before the
/// line at its lower bound.
struct LineHunk: Equatable {
    var range: Range<Int>
    var lines: [String]
}

/// The hunks that turn `base` into `other`, in order, with at least one unchanged line between two of them.
func lineHunks(from base: [String], to other: [String]) -> [LineHunk] {
    var removed = Set<Int>(), inserted = Set<Int>()
    for change in other.difference(from: base) {
        switch change {
        case .remove(let offset, _, _): removed.insert(offset)
        case .insert(let offset, _, _): inserted.insert(offset)
        }
    }
    var hunks: [LineHunk] = []
    var b = 0, o = 0
    while b < base.count || o < other.count {
        let start = b
        var lines: [String] = []
        while true {
            if b < base.count, removed.contains(b) {
                b += 1
            } else if o < other.count, inserted.contains(o) {
                lines.append(other[o])
                o += 1
            } else {
                break
            }
        }
        if b > start || !lines.isEmpty { hunks.append(LineHunk(range: start..<b, lines: lines)) }
        // The next line of each is the same line, kept. With none left on either side, both have ended.
        guard b < base.count, o < other.count else { break }
        b += 1
        o += 1
    }
    return hunks
}
