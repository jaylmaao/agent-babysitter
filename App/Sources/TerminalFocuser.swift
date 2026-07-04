import AppKit
import AgentBabysitterCore

/// Brings the terminal window owning a session to the front. Walks the
/// session process's ancestors until one of them is a real application
/// (claude → zsh → login → iTerm2); unknown owners fall back to the first
/// running terminal in preference order.
@MainActor
enum TerminalFocuser {

    /// Preference order for the fallback when no ancestor is an app.
    static let terminalBundleIDs = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "io.alacritty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
    ]

    static func focusSession(_ row: SessionRow) {
        if let pid = row.pid {
            for ancestor in ProcessAncestry.ancestorPIDs(of: pid) {
                if let app = NSRunningApplication(processIdentifier: ancestor),
                   app.activationPolicy == .regular {
                    app.activate()
                    return
                }
            }
        }
        focusAnyTerminal()
    }

    private static func focusAnyTerminal() {
        let running = NSWorkspace.shared.runningApplications
        for bundleID in terminalBundleIDs {
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
                app.activate()
                return
            }
        }
    }
}
