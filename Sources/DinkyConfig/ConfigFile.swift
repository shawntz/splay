import Foundation

/// Writing over the user's config. The app does it only when the user has asked for a change to the file, and
/// never without leaving the file as it was beside it.
public enum ConfigFile {
    /// Why the file was not changed, in sentences a window can show.
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let description: String

        public init(description: String) {
            self.description = description
        }
    }

    /// Replaces the config at `url` with `text`, and returns the copy of the old file it kept beside it,
    /// `<name>.before-<label>`.
    ///
    /// `expected` is what the file held when `text` was made from it. If it holds anything else now, such as an
    /// edit saved in the meantime, nothing is written. A config that is a link into a dotfiles checkout is written
    /// where the link leads, so the link stays. A file marked read-only is left alone.
    ///
    /// The new text reaches the disk in a file of its own before it takes the config's place by a rename, so a
    /// crash leaves the old file or the new one, never part of one. Only a config that has a second name on the
    /// same file is written in place, since a rename would part the two names. If that write fails the old text
    /// is put back.
    @discardableResult
    public static func replace(_ url: URL, with text: String, expecting expected: Data, label: String) throws(Failure) -> URL {
        let files = FileManager.default
        let name = url.lastPathComponent
        let target = url.resolvingSymlinksInPath()
        let folder = target.deletingLastPathComponent()
        func isUnchanged() -> Bool { files.contents(atPath: target.path) == expected }
        let changed = Failure(description: "\(name) was saved again in the meantime. Nothing was written.")
        guard isUnchanged() else { throw changed }
        guard access(target.path, W_OK) == 0 else {
            throw Failure(description: "\(name) is read-only. Nothing was written.")
        }
        let attributes = try? files.attributesOfItem(atPath: target.path)
        let mode = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        let hasOtherNames = ((attributes?[.referenceCount] as? NSNumber)?.intValue ?? 1) > 1
        let data = Data(text.utf8)

        // The new text first, so that nothing else is left behind when it cannot be written.
        var temporary: URL?
        if !hasOtherNames {
            let file = folder.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString)")
            do {
                try write(data, to: file, flags: O_WRONLY | O_CREAT | O_EXCL, mode: mode)
            } catch {
                try? files.removeItem(at: file)
                throw Failure(description: "\(Brand.displayName) can't write in \(folder.path): \(error.reason). Nothing was written.")
            }
            temporary = file
        }
        func giveUp(_ failure: Failure, removing copy: URL?) -> Failure {
            if let temporary { try? files.removeItem(at: temporary) }
            if let copy { try? files.removeItem(at: copy) }
            return failure
        }
        let kept: (copy: URL, isNew: Bool)
        do {
            kept = try keep(expected, beside: url, label: label, mode: mode)
        } catch {
            throw giveUp(Failure(description: "\(Brand.displayName) can't keep a copy of \(name) in \(url.deletingLastPathComponent().path): \(error.reason). Nothing was written."), removing: nil)
        }
        let newCopy = kept.isNew ? kept.copy : nil
        // Once more, now that the slow part is over: an editor may have saved while the files were written.
        guard isUnchanged() else { throw giveUp(changed, removing: newCopy) }

        guard let temporary else {
            do {
                try write(data, to: target, flags: O_WRONLY | O_TRUNC, mode: mode)
            } catch {
                let restored = (try? write(expected, to: target, flags: O_WRONLY | O_TRUNC, mode: mode)) != nil
                throw Failure(description: "Writing \(name) failed: \(error.reason). "
                    + (restored ? "The file is as it was." : "The file as it was is \(kept.copy.lastPathComponent), in the same folder."))
            }
            return kept.copy
        }
        // What the file carries besides its text, such as Finder tags. Without them the write still counts.
        copyfile(target.path, temporary.path, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
        guard rename(temporary.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            throw giveUp(Failure(description: "\(Brand.displayName) can't replace \(name): \(reason). Nothing was written."), removing: newCopy)
        }
        sync(folder)
        return kept.copy
    }

    /// A system call that failed, with the system's words for why.
    private struct WriteError: Error {
        let reason: String

        /// For a call that has just failed and set `errno`.
        init() {
            reason = String(cString: strerror(errno))
        }

        init(reason: String) {
            self.reason = reason
        }
    }

    /// Keeps `data` in a file beside `url` that did not exist before, or finds the copy already there. A name in
    /// use by other content gets `-2`, `-3` and so on, so no copy is ever written over.
    private static func keep(_ data: Data, beside url: URL, label: String, mode: UInt16) throws(WriteError) -> (copy: URL, isNew: Bool) {
        let name = "\(url.lastPathComponent).before-\(label)"
        for attempt in 1...99 {
            let copy = url.deletingLastPathComponent().appending(path: attempt == 1 ? name : "\(name)-\(attempt)")
            if let there = FileManager.default.contents(atPath: copy.path) {
                if there == data { return (copy, false) }
                continue
            }
            // Something that is there and can't be read, such as a folder or a dangling link, is not written to.
            guard (try? FileManager.default.attributesOfItem(atPath: copy.path)) == nil else { continue }
            do {
                try write(data, to: copy, flags: O_WRONLY | O_CREAT | O_EXCL, mode: mode)
            } catch {
                try? FileManager.default.removeItem(at: copy)
                throw error
            }
            return (copy, true)
        }
        throw WriteError(reason: "there are too many copies named \(name)")
    }

    /// Writes `data` and waits until it is on the disk.
    private static func write(_ data: Data, to url: URL, flags: Int32, mode: UInt16) throws(WriteError) {
        let descriptor = open(url.path, flags, mode_t(mode))
        guard descriptor >= 0 else { throw WriteError() }
        var failure: WriteError?
        // open applies the umask to a new file's mode.
        if flags & O_CREAT != 0, fchmod(descriptor, mode_t(mode)) != 0 { failure = WriteError() }
        if failure == nil {
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        failure = WriteError()
                        return
                    }
                    offset += written
                }
            }
        }
        // F_FULLFSYNC asks the drive itself to write; some volumes only know fsync.
        if failure == nil, fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 { failure = WriteError() }
        if close(descriptor) != 0, failure == nil { failure = WriteError() }
        if let failure { throw failure }
    }

    /// Asks for a folder's entries, such as a rename in it, to reach the disk.
    private static func sync(_ folder: URL) {
        let descriptor = open(folder.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        fsync(descriptor)
        close(descriptor)
    }
}
