import Foundation

/// Every OS-specific location the app reads, in one place.
///
/// The adapters used to hardcode `~/Library/Application Support/…`, which is a
/// macOS-only convention — a Windows build would have had to touch thirteen
/// files. Routing through here means a port changes THIS file and nothing else.
///
/// Two shapes matter:
///   * **Dot directories** (`~/.claude`, `~/.codex`, `~/.hermes`) — agents that
///     use these put them in the user's home on every platform, so the only
///     difference is what "home" means.
///   * **Application support** — genuinely different per OS:
///     macOS `~/Library/Application Support`, Windows `%APPDATA%`,
///     Linux `$XDG_DATA_HOME` (or `~/.local/share`).
public enum PlatformPaths {

    /// The current user's home. `homeDirectoryForCurrentUser` already resolves
    /// to `%USERPROFILE%` on Windows, so this is portable as-is.
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// A dot-directory in the user's home — `homeDirectory(".codex/sessions")`.
    /// Same layout on every platform; only the root differs.
    public static func homeDirectory(_ relativePath: String) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// Where desktop apps keep per-user state (Cursor's `state.vscdb`,
    /// Antigravity's storage, our own event log).
    public static var applicationSupport: URL {
        #if os(Windows)
        // %APPDATA% (roaming) is where Electron apps — Cursor, Antigravity —
        // put User/globalStorage on Windows.
        if let appData = ProcessInfo.processInfo.environment["APPDATA"] {
            return URL(fileURLWithPath: appData, isDirectory: true)
        }
        return home.appendingPathComponent("AppData/Roaming")
        #elseif os(Linux)
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
        }
        return home.appendingPathComponent(".local/share")
        #else
        return home.appendingPathComponent("Library/Application Support")
        #endif
    }

    /// A path under the per-user application-support root —
    /// `applicationSupport("Cursor/User/globalStorage/state.vscdb")`.
    public static func applicationSupport(_ relativePath: String) -> URL {
        applicationSupport.appendingPathComponent(relativePath)
    }

    /// The local iCloud Drive container, used to sync stats between the user's
    /// Macs. Optional on purpose: there is no equivalent off Apple platforms,
    /// and even on macOS the folder is absent when iCloud Drive is off — so
    /// callers already treat "no folder" as "syncing unavailable".
    public static var iCloudDrive: URL? {
        #if os(macOS) || os(iOS)
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        #else
        return nil
        #endif
    }
}
