import Foundation
import Testing
@testable import DinkyConfig

/// Writing over someone's config: the old file is always kept, and nothing is written when anything is off.
struct ConfigFileTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "splay-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func `The file gets the new text, and the old text is kept beside it`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(try read(url) == "new\n")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6")
        #expect(try read(copy) == "old\n")
        // Nothing else is left in the folder, such as the file the new text was first written to.
        #expect(try names(in: dir) == ["splay.toml", "splay.toml.before-0.6"])
    }

    @Test func `A file that changed in the meantime is not written over`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "saved by an editor just now\n".write(to: url, atomically: false, encoding: .utf8)
        let failure = #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        }
        #expect(failure?.description == "splay.toml was saved again in the meantime. Nothing was written.")
        #expect(try read(url) == "saved by an editor just now\n")
        #expect(try names(in: dir) == ["splay.toml"])
    }

    @Test func `A copy from an earlier time is never written over`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "second\n".write(to: url, atomically: false, encoding: .utf8)
        try "first\n".write(to: dir.appending(path: "splay.toml.before-0.6"), atomically: false, encoding: .utf8)
        let copy = try ConfigFile.replace(url, with: "third\n", expecting: Data("second\n".utf8), label: "0.6")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6-2")
        #expect(try read(dir.appending(path: "splay.toml.before-0.6")) == "first\n")
        #expect(try read(copy) == "second\n")
        #expect(try read(url) == "third\n")
    }

    @Test func `The same old text is kept once, not once per write`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        // The user puts the old file back and asks again.
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6")
        #expect(try names(in: dir) == ["splay.toml", "splay.toml.before-0.6"])
    }

    /// A config linked from a dotfiles checkout: the checkout's file changes and the link stays a link.
    @Test func `A linked config is written where the link leads`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dotfiles = dir.appending(path: "dotfiles"), config = dir.appending(path: "config")
        for folder in [dotfiles, config] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let target = dotfiles.appending(path: "splay.toml"), url = config.appending(path: "splay.toml")
        try "old\n".write(to: target, atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target.path)
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == target.path)
        #expect(try read(target) == "new\n")
        // The copy sits beside the link, where the user looks, and the checkout gets no extra file.
        #expect(copy.deletingLastPathComponent().lastPathComponent == "config")
        #expect(try names(in: dotfiles) == ["splay.toml"])
    }

    @Test func `A config with a second name on the same file keeps both names on it`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml"), other = dir.appending(path: "other-name.toml")
        // A shorter text than the file had, so what is left of the old one would show.
        try "a much longer old text\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.linkItem(at: url, to: other)
        try ConfigFile.replace(url, with: "new\n", expecting: Data("a much longer old text\n".utf8), label: "0.6")
        #expect(try read(url) == "new\n")
        #expect(try read(other) == "new\n")
        #expect(try read(dir.appending(path: "splay.toml.before-0.6")) == "a much longer old text\n")
    }

    /// The copy comes before the file is touched. With no name left for it, the file stays.
    @Test func `When no copy can be kept, the file is not written`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        var taken = ["splay.toml.before-0.6"]
        for attempt in 2...99 { taken.append("splay.toml.before-0.6-\(attempt)") }
        for name in taken { try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: true) }
        let failure = #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        }
        #expect(failure?.description.hasSuffix("Nothing was written.") == true)
        #expect(try read(url) == "old\n")
        #expect(try names(in: dir) == (taken + ["splay.toml"]).sorted())
    }

    /// The file cannot be replaced though its folder can be written to. Nothing the attempt made is left.
    @Test func `A file that cannot be replaced is left as it was, with no other file made`() throws {
        let dir = try directory()
        let url = dir.appending(path: "splay.toml")
        defer {
            chflags(url.path, 0)
            try? FileManager.default.removeItem(at: dir)
        }
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        #expect(chflags(url.path, UInt32(UF_IMMUTABLE)) == 0)
        #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        }
        #expect(try read(url) == "old\n")
        #expect(try names(in: dir) == ["splay.toml"])
    }

    @Test func `A name the copy would take that is a link to nothing is passed over`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: dir.appending(path: "splay.toml.before-0.6").path, withDestinationPath: "nowhere")
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6-2")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dir.appending(path: "splay.toml.before-0.6").path) == "nowhere")
    }

    /// GNU stow links the whole config folder into the checkout, by a path relative to the link.
    @Test func `A config in a linked folder, and one behind a chain of relative links, are written where they lead`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let checkout = dir.appending(path: "dotfiles/splay"), home = dir.appending(path: "home/.config")
        for folder in [checkout, home] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try "old\n".write(to: checkout.appending(path: "splay.toml"), atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: home.appending(path: "splay").path, withDestinationPath: "../../dotfiles/splay")
        let url = home.appending(path: "splay/splay.toml")
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(try read(checkout.appending(path: "splay.toml")) == "new\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.appending(path: "splay").path) == "../../dotfiles/splay")
        #expect(try read(copy) == "old\n")

        // A link to a link to the file, each relative to its own folder.
        let first = dir.appending(path: "home/first.toml"), second = dir.appending(path: "dotfiles/second.toml")
        try FileManager.default.createSymbolicLink(atPath: second.path, withDestinationPath: "splay/splay.toml")
        try FileManager.default.createSymbolicLink(atPath: first.path, withDestinationPath: "../dotfiles/second.toml")
        try ConfigFile.replace(first, with: "newer\n", expecting: Data("new\n".utf8), label: "0.6")
        #expect(try read(checkout.appending(path: "splay.toml")) == "newer\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: first.path) == "../dotfiles/second.toml")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: second.path) == "splay/splay.toml")
    }

    @Test func `A link that leads nowhere, and a link that leads to itself, are errors and nothing is written`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dangling = dir.appending(path: "splay.toml"), loop = dir.appending(path: "loop.toml")
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: dir.appending(path: "missing.toml").path)
        try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: "loop.toml")
        for url in [dangling, loop] {
            #expect(throws: ConfigFile.Failure.self) { try ConfigFile.replace(url, with: "new\n", expecting: Data(), label: "0.6") }
        }
        #expect(try names(in: dir) == ["loop.toml", "splay.toml"])
    }

    /// Someone who made the file read-only meant it, even though the folder would allow a new file in its place.
    @Test func `A read-only file is left alone`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        let failure = #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        }
        #expect(failure?.description == "splay.toml is read-only. Nothing was written.")
        #expect(try read(url) == "old\n")
        #expect(try names(in: dir) == ["splay.toml"])
    }

    @Test func `The file keeps its extended attributes`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        let value = Array("yes".utf8)
        #expect(setxattr(url.path, "com.example.mine", value, value.count, 0, 0) == 0)
        try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        var found = [UInt8](repeating: 0, count: 8)
        let length = getxattr(url.path, "com.example.mine", &found, found.count, 0, 0)
        #expect(length == 3 && Array(found.prefix(3)) == value)
    }

    @Test func `A name the copy would take that is a folder is passed over`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appending(path: "splay.toml.before-0.6"), withIntermediateDirectories: true)
        let copy = try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        #expect(copy.lastPathComponent == "splay.toml.before-0.6-2")
        #expect(try read(copy) == "old\n")
    }

    @Test func `The file and its copy keep the file's permissions`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        // One mode tighter than a new file gets and one looser, which the usual umask would cut down.
        for (mode, label) in [(0o600, "tight"), (0o664, "loose")] {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            let old = try Data(contentsOf: url)
            let copy = try ConfigFile.replace(url, with: "new \(label)\n", expecting: old, label: label)
            for file in [url, copy] {
                let found = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
                #expect(found.intValue == mode, "\(file.lastPathComponent)")
            }
        }
    }

    @Test func `A folder that cannot be written to leaves the file as it was`() throws {
        let dir = try directory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appending(path: "splay.toml")
        try "old\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(url, with: "new\n", expecting: Data("old\n".utf8), label: "0.6")
        }
        #expect(try read(url) == "old\n")
        #expect(try names(in: dir) == ["splay.toml"])
    }

    @Test func `A missing file is an error`() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.replace(dir.appending(path: "splay.toml"), with: "new\n", expecting: Data(), label: "0.6")
        }
        #expect(try names(in: dir) == [])
    }
}
