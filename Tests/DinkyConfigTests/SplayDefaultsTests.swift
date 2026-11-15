import Foundation
import Testing
@testable import DinkyConfig

/// Where Splay's defaults differ from upstream's: a scrolling strip, and no login item until asked for.
struct SplayDefaultsTests {
    @Test func `The default layout is scrolling`() throws {
        #expect(Config().defaultLayout == .scrolling)
        #expect(Config.default.defaultLayout == .scrolling, "the shipped file agrees with the built-in default")
        let omitted = try Config.parse("workspaces = 3\n[workspace.2]\ntiling = true\n")
        #expect(omitted.defaultLayout == .scrolling)
        #expect(omitted.settings(forWorkspace: 1).layout == .scrolling)
        #expect(omitted.settings(forWorkspace: 2).layout == .scrolling, "a workspace table without a layout inherits it")
        #expect(omitted.settings(forWorkspace: nil).layout == .scrolling)
    }

    @Test func `A first run registers no login item`() {
        #expect(!Config().startAtLogin)
        #expect(!Config.default.startAtLogin)
    }

    /// The schema is written by hand and SchemaTests checks only its keys, so check the defaults changed here.
    @Test func `The schema's defaults agree`() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/schemas/splay.json")
        let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(properties["default-layout"]?["default"] as? String == Config().defaultLayout.rawValue)
        #expect(properties["start-at-login"]?["default"] as? Bool == Config().startAtLogin)
    }
}
