import AppKit

// macOS decides Accessibility for the process it holds responsible for this one. An app opened from Finder, with
// `open` or as a login item is responsible for itself. One started from a terminal, a script or a launcher that
// does not disown it answers to that app's grant instead, and still does after its parent has exited.

/// The process macOS holds responsible for this one, or nil when it cannot be told.
func responsiblePID() -> pid_t? {
    typealias Lookup = @convention(c) (pid_t) -> pid_t
    // RTLD_DEFAULT. The function is libsystem's, and has no public header.
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
        return nil
    }
    let pid = unsafeBitCast(symbol, to: Lookup.self)(getpid())
    return pid > 0 ? pid : nil
}

/// Whether this process answers to its own Accessibility grant. When macOS does not say who is responsible,
/// having launchd for a parent is the next best sign.
func heldToOwnGrant(responsible: pid_t? = responsiblePID(), own: pid_t = getpid(), parent: pid_t = getppid()) -> Bool {
    responsible.map { $0 == own } ?? (parent == 1)
}

/// The name of the app whose grant counts instead of this process's own, when it is an app with a name.
func grantHolderName(responsible: pid_t? = responsiblePID(), own: pid_t = getpid()) -> String? {
    guard let responsible, responsible != own else { return nil }
    return NSRunningApplication(processIdentifier: responsible)?.localizedName
}
