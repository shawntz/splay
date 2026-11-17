import CryptoKit
import Foundation
import Testing
@testable import DinkyConfig

/// The archive of shipped defaults is what an existing config is compared with, so each text must stay exactly
/// what its release wrote to disk.
struct ShippedDefaultsTests {
    /// The SHA-256 of each default as written, with its final newline. An entry here never changes. A release
    /// that changes `Config.defaultTOML` adds one, after freezing the text the release before it had.
    private static let pinned: [(version: String, sha256: String)] = [
        ("0.1", "6ce8a9d35d1a71c063fb1244ad9b25bdc8d586680052837c9bd6b5e0a934b20e"),
        ("0.2", "9bb4560a19969b94a4a15f2b75f2303a85095c54d3f9c5f98e1fdd721020996b"),
        ("0.4", "20a104a7d66cb2bc7780f58f0f26cdcf5e1ee65fc979e241cebf6efe4ff083d4"),
        ("0.5", "db5d5ba8130fc432a4b9deee5c1a4ce732e29190a75f7bf85acd910d060b9fba"),
    ]

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func `Every shipped default is the text its release wrote`() {
        #expect(Config.shippedDefaults.map(\.version) == Self.pinned.map(\.version))
        for (shipped, pin) in zip(Config.shippedDefaults, Self.pinned) {
            #expect(sha256(shipped.toml + "\n") == pin.sha256, """
                The default of \(shipped.version) is not what that release shipped. If Config.defaultTOML changed, \
                keep the old text as a constant in ShippedDefaults.swift for \(shipped.version) and add an entry, \
                and a pin here, for the release that ships the new text.
                """)
        }
    }

    @Test func `The newest shipped default is the current one`() {
        #expect(Config.shippedDefaults.last?.toml == Config.defaultTOML)
    }

    @Test func `Every shipped default parses, and no two are the same`() throws {
        for shipped in Config.shippedDefaults {
            #expect(throws: Never.self, "\(shipped.version)") { try Config.parse(shipped.toml) }
        }
        #expect(Set(Config.shippedDefaults.map(\.toml)).count == Config.shippedDefaults.count)
    }

    /// The update edits binding lines it finds by their key, so it must find every one a default has.
    @Test func `Every binding of every shipped default sits on a line of its own under its mode`() throws {
        for shipped in Config.shippedDefaults {
            let config = try Config.parse(shipped.toml)
            for (name, mode) in config.modes {
                let lines = shipped.toml.components(separatedBy: "\n")
                let start = try #require(lines.firstIndex(of: "[mode.\(name)]"), "\(shipped.version) \(name)")
                let section = lines[(start + 1)...].prefix { !$0.hasPrefix("[") }
                for combo in mode.bindings.keys {
                    #expect(section.filter { $0.hasPrefix("\(combo) = ") }.count == 1, "\(shipped.version) \(name) \(combo)")
                }
            }
        }
    }
}
