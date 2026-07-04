import Foundation

/// Pure parsing for the opt-in live Claude usage fetch — kept in Core so it
/// is unit-tested; the app layer only does the networking around it.
public enum ClaudeLiveParsing {

    /// The API returns the subscription windows in response headers
    /// (verified live): `anthropic-ratelimit-unified-5h-utilization` is a
    /// 0–1 fraction, `…-5h-reset` epoch seconds; same pattern for `7d`.
    /// Headers ride only on successful /v1/messages responses.
    public static func snapshot(fromHeaders headers: [String: String],
                                plan: String?,
                                capturedAt: Date = Date()) -> UsageLimitSnapshot? {
        func value(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        guard let text = value("anthropic-ratelimit-unified-5h-utilization"),
              let fraction = Double(text) else { return nil }
        let resets = value("anthropic-ratelimit-unified-5h-reset")
            .flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let weekly = value("anthropic-ratelimit-unified-7d-utilization").flatMap(Double.init)
        let weeklyResets = value("anthropic-ratelimit-unified-7d-reset")
            .flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        return UsageLimitSnapshot(usedPercent: min(max(fraction * 100, 0), 100),
                                  windowMinutes: 300, resetsAt: resets,
                                  capturedAt: capturedAt, plan: plan ?? "subscription",
                                  isLive: true,
                                  weeklyUsedPercent: weekly.map { min(max($0 * 100, 0), 100) },
                                  weeklyResetsAt: weeklyResets)
    }

    /// Extracts `NAME=value` from `ps eww -o command=` output (command line
    /// followed by space-separated env pairs; the values we read are single
    /// tokens, so splitting on whitespace is safe).
    public static func envValue(_ name: String, inProcessEnv output: String) -> String? {
        for word in output.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            if word.hasPrefix("\(name)=") {
                let value = String(word.dropFirst(name.count + 1))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
