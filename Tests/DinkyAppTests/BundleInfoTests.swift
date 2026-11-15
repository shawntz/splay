import Foundation
import Testing
@testable import dinky

/// `splay version` through the link `just install` makes: the process has no bundle of its own there.
struct BundleInfoTests {
    /// A stand-in app in a fresh temporary folder, with an executable in it and a link to that outside it.
    private func app(named name: String = "Stand In.app") throws -> (executable: URL, link: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-bundle-\(UUID())")
        let macOS = folder.appendingPathComponent("\(name)/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.stand-in", "CFBundleShortVersionString": "9.8", "CFBundleVersion": "76"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: macOS.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let executable = macOS.appendingPathComponent("tool")
        try Data().write(to: executable)
        let bin = folder.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("tool")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        return (executable, link, folder)
    }

    @Test func `The version is the app's, run directly or through a link`() throws {
        let (executable, link, folder) = try app()
        defer { try? FileManager.default.removeItem(at: folder) }
        for url in [executable, link] {
            let info = try #require(bundleInfo(ofExecutable: url), "\(url.path)")
            #expect(info["CFBundleShortVersionString"] as? String == "9.8")
            #expect(info["CFBundleVersion"] as? String == "76")
        }
    }

    @Test func `The version line is the app's through a link, and dev outside an app`() throws {
        let (_, link, folder) = try app()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(versionLine(executable: link, fallback: nil) == "splay 9.8 (76)")
        #expect(versionLine(executable: link, fallback: ["CFBundleShortVersionString": "0", "CFBundleVersion": "0"]) == "splay 9.8 (76)")
        let bare = URL(fileURLWithPath: "/usr/bin/true")
        #expect(versionLine(executable: bare, fallback: nil) == "splay dev (0)")
        #expect(versionLine(executable: nil, fallback: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "3"]) == "splay 1.2 (3)")
    }

    @Test func `An executable outside an app has no Info.plist to read`() throws {
        let (_, _, folder) = try app(named: "Not An App")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(bundleInfo(ofExecutable: folder.appendingPathComponent("Not An App/Contents/MacOS/tool")) == nil)
        #expect(bundleInfo(ofExecutable: URL(fileURLWithPath: "/usr/bin/true")) == nil)
    }
}
