import Foundation

/// Merges Agent Babysitter's Notification/Stop hooks into Claude Code's
/// `~/.claude/settings.json` — Precision mode's exact waiting/done signals.
///
/// Non-destructive by contract: user hooks and settings are never touched,
/// our entries are identified by a marker in the command string, removal
/// strips only ours, and unparseable settings abort with an error before
/// anything is written.
public enum HooksInstaller {

    public struct SettingsError: Error, LocalizedError {
        public var errorDescription: String? {
            "~/.claude/settings.json could not be parsed. Nothing was changed — "
            + "fix or remove the file and try again."
        }
    }

    /// Identifies our hook entries inside settings.json.
    public static let marker = "agent-babysitter-hook-v1"

    public static let defaultEventLogURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AgentBabysitter/events.jsonl")

    private static let hookEvents = ["Notification", "Stop"]

    private static func hookCommand(eventLogPath: String) -> String {
        // Hook stdin carries one JSON event; append it as a line to the event
        // log (file-drop transport, no sockets). The trailing comment is the
        // removal marker.
        "mkdir -p \"$(dirname '\(eventLogPath)')\" && { cat; echo; } >> '\(eventLogPath)' #\(marker)"
    }

    // MARK: - Pure transforms (testable without touching the filesystem)

    /// Returns settings JSON with our hooks merged in. `nil`/empty input is a
    /// fresh settings file. Throws on unparseable input — callers must not
    /// write anything in that case.
    public static func settingsWithHooksInstalled(
        _ data: Data?,
        eventLogPath: String = defaultEventLogURL.path
    ) throws -> Data {
        var root = try parse(data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !entries.contains(where: isOurs) {
                entries.append([
                    "hooks": [["type": "command",
                               "command": hookCommand(eventLogPath: eventLogPath)]]
                ])
            }
            hooks[event] = entries
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// Returns settings JSON with only our hooks removed.
    public static func settingsWithHooksRemoved(_ data: Data?) throws -> Data {
        var root = try parse(data)
        guard var hooks = root["hooks"] as? [String: Any] else {
            return try serialize(root)
        }
        for event in hookEvents {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let kept = entries.compactMap { entry -> [String: Any]? in
                guard var inner = entry["hooks"] as? [[String: Any]] else { return entry }
                inner.removeAll { ($0["command"] as? String)?.contains(marker) == true }
                guard !inner.isEmpty else { return nil }
                var entry = entry
                entry["hooks"] = inner
                return entry
            }
            if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
            }
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    public static func isInstalled(in data: Data?) -> Bool {
        guard let data, let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    // MARK: - File wrappers

    public static let defaultSettingsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    public static func install(settingsURL: URL = defaultSettingsURL,
                               eventLogPath: String = defaultEventLogURL.path) throws {
        let current = try? Data(contentsOf: settingsURL)
        let updated = try settingsWithHooksInstalled(current, eventLogPath: eventLogPath)
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: settingsURL, options: .atomic)
    }

    public static func uninstall(settingsURL: URL = defaultSettingsURL) throws {
        guard let current = try? Data(contentsOf: settingsURL) else { return }
        let updated = try settingsWithHooksRemoved(current)
        try updated.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Internals

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? [])
            .contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SettingsError()
        }
        return root
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root,
                                   options: [.prettyPrinted, .sortedKeys])
    }
}

/// Parses one line of the Precision-mode event log (raw Claude Code hook
/// input JSON appended by our hook command).
public enum HookEventParser {

    public static func parse(line: Data) -> (sessionID: String, kind: HookSignal.Kind)? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let sessionID = object["session_id"] as? String,
              let eventName = object["hook_event_name"] as? String else {
            return nil
        }
        switch eventName {
        case "Notification": return (sessionID, .waitingForInput)
        case "Stop": return (sessionID, .turnCompleted)
        default: return nil
        }
    }
}
