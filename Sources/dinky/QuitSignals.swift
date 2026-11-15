import Darwin

// The signals that quit through NSApplication, so windows are restored on the way out: `kill`, Ctrl-C, and the
// hangup a closing terminal sends a run attached to it. Not the hangup when it is already ignored at launch, as
// under nohup: that run was asked to outlive its terminal.

/// Whether SIGHUP was already ignored when this process started.
func hangupIsIgnored() -> Bool {
    var current = sigaction()
    guard sigaction(SIGHUP, nil, &current) == 0 else { return false }
    // SIG_IGN is the handler address 1.
    return unsafeBitCast(current.__sigaction_u.__sa_handler, to: Int.self) == 1
}

func quitSignals(hangupIgnored: Bool = hangupIsIgnored()) -> [Int32] {
    hangupIgnored ? [SIGTERM, SIGINT] : [SIGTERM, SIGINT, SIGHUP]
}
