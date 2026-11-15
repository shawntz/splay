import DinkyConfig
import Foundation
import Testing

/// Splay merges upstream Dinky often and keeps its module and symbol names, but users and macOS must only
/// ever see Splay. This fails when a string literal anywhere in Sources says dinky, or the app's Info.plist
/// does, so a merge that brings in a new user-visible dinky string is caught here rather than in the menu bar.
/// It does not read scripts/ or the Justfile; ManualTests reads docs/ and the README.
struct BrandGuardTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Literals that keep upstream's name, by file and text (interpolated code left out), each with its reason.
    private static let allowed: [(file: String, literal: String)] = [
        // Dispatch queue labels show only in debuggers and crash reports; renaming them would only add conflicts.
        ("Sources/DinkyConfig/ConfigWatcher.swift", "dinky.config-watcher"),
        ("Sources/DinkyLayout/FrameScheduler.swift", "dinky.frames."),
        ("Sources/DinkySocket/Socket.swift", "dinky.socket"),
        ("Sources/dinky/FrameApplier.swift", "dinky.frames.raise"),
        // Upstream's own names, so the rival-tiler check can warn while upstream Dinky is running.
        ("Sources/DinkyConfig/Brand.swift", "dinky"),
        ("Sources/DinkyConfig/Brand.swift", "Dinky"),
        ("Sources/DinkyConfig/Brand.swift", "com.brnbw.dinky"),
    ]

    @Test func `No string literal in Sources says dinky`() throws {
        let sources = Self.root.appending(path: "Sources")
        var scanned = 0
        var headers = 0
        var found: [String] = []
        for sub in try FileManager.default.subpathsOfDirectory(atPath: sources.path).sorted()
        where [".swift", ".m", ".h", ".c"].contains(where: sub.hasSuffix) {
            scanned += 1
            if sub.hasSuffix(".h") { headers += 1 }
            let path = "Sources/" + sub
            let source = try String(contentsOf: sources.appending(path: sub), encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for literal in StringLiterals(source, objectiveC: !sub.hasSuffix(".swift")).all
            where literal.text.lowercased().contains("dinky")
                && !Self.allowed.contains(where: { $0.file == path && $0.literal == literal.text }) {
                found.append("  \(path):\(literal.line): \(lines[literal.line - 1].trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(scanned > 50, "found too few sources under \(sources.path)")
        #expect(headers > 5, "found too few headers under \(sources.path)")
        #expect(found.isEmpty, """
            These string literals say dinky, which users or macOS would see. Read the name from Brand instead: \
            Brand.name in commands, paths and command line messages, Brand.displayName in windows, menus and alerts, \
            Brand.envPrefix for hook variables. If one really must keep upstream's name, add it to \
            BrandGuardTests.allowed with the reason.
            \(found.joined(separator: "\n"))
            """)
    }

    /// macOS shows these to people: the name in Activity Monitor and the Accessibility list, and any usage
    /// string in a permission prompt. The update feed and its signing key must be Splay's own too: with
    /// upstream's, Sparkle would offer Dinky's releases as updates.
    @Test func `The app's Info.plist is Splay's, and so is its update feed`() throws {
        let data = try Data(contentsOf: Self.root.appending(path: "Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == Brand.bundleID)
        #expect(plist["CFBundleExecutable"] as? String == Brand.name)
        #expect(plist["CFBundleName"] as? String == Brand.displayName)
        #expect(plist["SUFeedURL"] as? String == "https://github.com/shawntz/splay/releases/latest/download/appcast.xml")
        let key = try #require(plist["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32, "an Ed25519 public key is 32 bytes")
        #expect(key != "jif/E57Xw8xCo7BwHnOeASD+nbQc462aQTYOuvoH/io=", "that is upstream's key")
        #expect(Set(plist.keys.filter { $0.hasPrefix("SU") }) == ["SUFeedURL", "SUPublicEDKey"])
        func strings(_ value: Any) -> [String] {
            switch value {
            case let text as String: [text]
            case let list as [Any]: list.flatMap(strings)
            case let table as [String: Any]: table.keys + table.values.flatMap(strings)
            default: []
            }
        }
        #expect(strings(plist).filter { $0.lowercased().contains("dinky") } == [])
    }

    @Test func `The guard reads headers as it reads Objective-C`() {
        let header = StringLiterals(#"""
            #include "dinky_private.h"
            #define DINKY_ALERT "dinky needs Accessibility"
            extern const char *dinky_name(void); // "dinky"
            """#, objectiveC: true).all
        #expect(header.map(\.text) == ["dinky needs Accessibility"])
    }

    @Test func `The guard reads literals, not comments or code`() {
        let swift = StringLiterals(##"""
            // "dinky in a comment"
            let a = dinky_info(1) /* "dinky" /* nested */ */ + "one \(dinky_x("two")) three"
            let b = """
                dinky in a multi-line literal
                """
            let c = #"raw \#(dinky) "quoted""#
            """##, objectiveC: false).all
        #expect(swift.map(\.line) == [2, 2, 4, 6])
        #expect(swift.map { $0.text.trimmingCharacters(in: .whitespaces) }
                == ["two", "one  three", "dinky in a multi-line literal", #"raw  "quoted""#])

        let objectiveC = StringLiterals(#"""
            #import "DinkyPrivate.h"
            NSString *s = @"dinky"; char q = '"'; // "dinky"
            """#, objectiveC: true).all
        #expect(objectiveC.map(\.line) == [2])
        #expect(objectiveC.map(\.text) == ["dinky"])
    }
}

/// The string literals in Swift or Objective-C source, a piece per source line, with comments, interpolated
/// code and Objective-C #import, #include and #pragma lines left out. Enough of each language for this guard,
/// not a parser.
private struct StringLiterals {
    struct Piece {
        let line: Int
        let text: String
    }

    private(set) var all: [Piece] = []
    private let chars: [Character]
    private let objectiveC: Bool
    private var i = 0
    private var line = 1

    init(_ source: String, objectiveC: Bool) {
        chars = Array(source)
        self.objectiveC = objectiveC
        code(inInterpolation: false)
    }

    private func at(_ offset: Int) -> Character? {
        i + offset < chars.count ? chars[i + offset] : nil
    }

    private func hashRun(at offset: Int) -> Int {
        var n = 0
        while at(offset + n) == "#" { n += 1 }
        return n
    }

    private mutating func record(_ text: String, line: Int) {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { all.append(Piece(line: line, text: text)) }
    }

    private mutating func skipLine() {
        while let c = at(0), c != "\n" { i += 1 }
    }

    /// Code up to the end of the source, or past the `)` that closes an interpolation.
    private mutating func code(inInterpolation: Bool) {
        var depth = 0
        while let c = at(0) {
            switch c {
            case "\n":
                line += 1
                i += 1
            case "/" where at(1) == "/":
                skipLine()
            case "/" where at(1) == "*":
                i += 2
                var nesting = 1
                while nesting > 0, let c = at(0) {
                    if c == "\n" { line += 1 }
                    if c == "/", at(1) == "*", !objectiveC {
                        nesting += 1
                        i += 2
                    } else if c == "*", at(1) == "/" {
                        nesting -= 1
                        i += 2
                    } else {
                        i += 1
                    }
                }
            case "#" where objectiveC:
                let directive = String(chars[(i + 1)...].prefix { $0.isLetter })
                if ["import", "include", "pragma"].contains(directive) { skipLine() } else { i += 1 }
            case "#":
                let n = hashRun(at: 0)
                i += n
                if at(0) == "\"" { string(hashes: n) }
            case "'" where objectiveC:
                i += 1
                while let c = at(0), c != "'", c != "\n" { i += c == "\\" ? 2 : 1 }
                if at(0) == "'" { i += 1 }
            case "\"":
                string(hashes: 0)
            case "(":
                depth += 1
                i += 1
            case ")":
                i += 1
                if inInterpolation, depth == 0 { return }
                depth -= 1
            default:
                i += 1
            }
        }
    }

    /// From the opening quote of a literal with `hashes` raw-string hashes before it, to past its end.
    private mutating func string(hashes: Int) {
        let multiline = !objectiveC && at(1) == "\"" && at(2) == "\""
        let quotes = multiline ? 3 : 1
        i += quotes
        var text = ""
        var start = line
        while let c = at(0) {
            if c == "\"", !multiline || (at(1) == "\"" && at(2) == "\""), hashRun(at: quotes) >= hashes {
                record(text, line: start)
                i += quotes + hashes
                return
            }
            if c == "\\", hashRun(at: 1) >= hashes {
                let next = 1 + hashes
                if !objectiveC, at(next) == "(" {
                    i += next + 1
                    code(inInterpolation: true)
                } else if at(next) == "\n" {
                    record(text, line: start)
                    text = ""
                    line += 1
                    start = line
                    i += next + 1
                } else {
                    if let escaped = at(next) { text.append(escaped) }
                    i += next + 1
                }
                continue
            }
            if c == "\n" {
                record(text, line: start)
                // A single-line literal cannot span lines; leave the newline to the code.
                guard multiline else { return }
                text = ""
                line += 1
                start = line
                i += 1
                continue
            }
            text.append(c)
            i += 1
        }
        record(text, line: start)
    }
}
