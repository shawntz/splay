import DinkyConfig
import Foundation
import Testing

/// The manual under docs/ and the README are Splay's, written by hand. These keep the default config they quote
/// in step with the shipped one, and keep upstream's command, paths, site, Homebrew tap and hook variables out of
/// them. The pages name Dinky, the project, with a capital; in lower case it is something to type or open, which
/// in Splay is spelled splay. A merged upstream sentence such as "`dinky doctor` warns about it" is caught so.
struct ManualTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// The text files of the manual's site, by path from the repository root, and the README.
    private static func pages() throws -> [String] {
        let docs = root.appending(path: "docs")
        let text: Set<String> = ["md", "html", "yml", "json", "svg", "css"]
        let files = try FileManager.default.subpathsOfDirectory(atPath: docs.path).sorted()
            .filter { text.contains(($0 as NSString).pathExtension) }
            .map { "docs/" + $0 }
        return files + ["README.md"]
    }

    @Test func `The manual's default config is the shipped one`() throws {
        let manual = try Self.read("docs/configuration.md")
        let heading = try #require(manual.range(of: "\n## Default config\n"), "no Default config section")
        let after = manual[heading.upperBound...]
        let open = try #require(after.range(of: "```toml\n"), "no toml block after the heading")
        let close = try #require(after[open.upperBound...].range(of: "\n```"), "the toml block does not end")
        let block = String(after[open.upperBound..<close.lowerBound])
        guard block != Config.defaultTOML else { return }
        // Name the first line that differs, as a whole-file diff would be unreadable here.
        let quoted = block.split(separator: "\n", omittingEmptySubsequences: false)
        let shipped = Config.defaultTOML.split(separator: "\n", omittingEmptySubsequences: false)
        let line = zip(quoted, shipped).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(quoted.count, shipped.count)
        Issue.record("""
            docs/configuration.md's Default config differs from Config.defaultTOML at line \(line + 1) of the block:
              manual:  \(line < quoted.count ? String(quoted[line]) : "(ends)")
              shipped: \(line < shipped.count ? String(shipped[line]) : "(ends)")
            """)
    }

    /// What no page may say, each with what it is.
    private static func banned() throws -> [(what: String, pattern: Regex<AnyRegexOutput>)] {
        [
            ("upstream's command, a path of its own or its site", try Regex(#"dinky"#)),
            // `brew tap`, or `brew install` of an owner/tap/name: Splay is built from source.
            ("a Homebrew tap install", try Regex(#"brew\s+(tap\b|(re)?install\b.*\b[\w.-]+/[\w.-]+/[\w.-]+)"#)),
            ("a DINKY_ hook variable", try Regex(#"DINKY_"#)),
        ]
    }

    @Test func `The checks catch upstream's lines and pass Splay's`() throws {
        let banned = try Self.banned()
        func caught(_ line: String) -> [String] { banned.filter { line.contains($0.pattern) }.map(\.what) }
        let lowerCase = "upstream's command, a path of its own or its site"
        #expect(caught("brew install --cask mikker/tap/dinky") == [lowerCase, "a Homebrew tap install"])
        #expect(caught("brew tap mikker/tap") == ["a Homebrew tap install"])
        #expect(caught("#:schema https://dinky.rodeo/schemas/dinky.json") == [lowerCase])
        #expect(caught("turn it off, or `dinky doctor` warns about it") == [lowerCase])
        #expect(caught("copy ~/.config/dinky/dinky.toml") == [lowerCase])
        #expect(caught("MODE=$DINKY_MODE") == ["a DINKY_ hook variable"])
        #expect(caught("startup = ['exec-and-forget brew services restart sketchybar']").isEmpty)
        #expect(caught("MODE=$SPLAY_MODE, and its commands to `splay`").isEmpty)
        #expect(caught("Splay is a fork of [Dinky](https://github.com/mikker/Dinky), in Sources/DinkyPrivate").isEmpty)
    }

    @Test func `No page sends people to upstream's command, paths, site, tap or hook variables`() throws {
        let banned = try Self.banned()
        let pages = try Self.pages()
        #expect(pages.filter { $0.hasPrefix("docs/") && $0.hasSuffix(".md") }.count >= 5, "found too few pages under docs/")
        var found: [String] = []
        for page in pages {
            let lines = try Self.read(page).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                for (what, pattern) in banned where line.contains(pattern) {
                    found.append("  \(page):\(index + 1): \(what): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, """
            Splay's command and paths are spelled \(Brand.name), its site is https://shawntz.github.io/splay/, it has \
            no Homebrew tap, and its hook variables start with \(Brand.envPrefix):
            \(found.joined(separator: "\n"))
            """)
    }
}
