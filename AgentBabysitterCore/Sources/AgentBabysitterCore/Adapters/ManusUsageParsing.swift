import Foundation

/// Pure parsing for the opt-in live Manus usage fetch — in Core so it's
/// unit-tested; the app layer does the networking. Manus is credit-based,
/// not a rolling percentage: it grants a daily-refreshing allowance
/// (`refreshCredits` of `maxRefreshCredits`, resetting at `nextRefreshTime`)
/// on top of a one-time free pool. Verified live 2026-07 against
/// `POST api.manus.im/user.v1.UserService/GetAvailableCredits`:
/// `{"totalCredits":1276,"freeCredits":1000,"refreshCredits":276,
///   "maxRefreshCredits":300,"nextRefreshTime":"…Z","refreshInterval":"daily"}`.
///
/// The daily refresh is the recurring quota (the analogue of Claude's
/// 5-hour window), so it drives the bar; the full balance rides in the
/// label so the credit total the user cares about is still visible.
public enum ManusUsageParsing {

    public struct Credits: Equatable, Sendable {
        public let total: Int
        public let free: Int
        public let refresh: Int
        public let maxRefresh: Int
        public let nextRefresh: Date?
        public let interval: String?
    }

    public static func credits(fromJSON data: Data) -> Credits? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        func int(_ key: String) -> Int? { (root[key] as? NSNumber)?.intValue }
        guard let total = int("totalCredits") else { return nil }
        return Credits(
            total: total,
            free: int("freeCredits") ?? 0,
            refresh: int("refreshCredits") ?? 0,
            maxRefresh: int("maxRefreshCredits") ?? 0,
            nextRefresh: (root["nextRefreshTime"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            },
            interval: root["refreshInterval"] as? String)
    }

    /// Builds the limit snapshot. `plan` is the membership tier from
    /// UserInfo (e.g. "free"). The bar tracks daily-refresh consumption; the
    /// label carries the total balance so the number stays front and centre.
    public static func snapshot(fromJSON data: Data, plan: String?,
                                capturedAt: Date = Date()) -> UsageLimitSnapshot? {
        guard let credits = credits(fromJSON: data) else { return nil }
        let planLabel = [plan?.capitalized, "\(formatted(credits.total)) credits"]
            .compactMap { $0 }.joined(separator: " · ")

        // Daily refresh as the window, when the plan actually has one.
        if credits.maxRefresh > 0 {
            let used = Double(credits.maxRefresh - credits.refresh)
                / Double(credits.maxRefresh) * 100
            let window = windowMinutes(for: credits.interval)
            return UsageLimitSnapshot(usedPercent: min(max(used, 0), 100),
                                      windowMinutes: window,
                                      resetsAt: credits.nextRefresh,
                                      capturedAt: capturedAt, plan: planLabel, isLive: true)
        }
        // No refreshing quota (paid pools): show the balance as a plan row.
        return UsageLimitSnapshot(usedPercent: nil, windowMinutes: 24 * 60,
                                  resetsAt: credits.nextRefresh, capturedAt: capturedAt,
                                  plan: planLabel, isLive: true)
    }

    static func windowMinutes(for interval: String?) -> Int {
        switch interval?.lowercased() {
        case "daily": return 24 * 60
        case "weekly": return 7 * 24 * 60
        case "monthly": return 30 * 24 * 60
        default: return 24 * 60
        }
    }

    static func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}
