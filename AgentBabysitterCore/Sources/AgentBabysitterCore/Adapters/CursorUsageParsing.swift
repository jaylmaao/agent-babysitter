import Foundation

/// Pure parsing for the opt-in live Cursor usage fetch — in Core so it's
/// unit-tested; the app layer does the networking. Verified live 2026-07:
/// `POST cursor.com/api/usage-summary` (with the WorkosCursorSessionToken
/// cookie `<userID>::<sessionJWT>` and an `Origin: https://cursor.com`
/// header) returns the same "Included Usage NN%" and cycle reset the
/// Cursor app's own Plan & Usage page shows. This is the real percentage —
/// the older `/api/usage` request-count endpoint didn't carry it.
public enum CursorUsageParsing {

    /// The user id lives in the session JWT's `sub` claim after the auth
    /// provider prefix ("google-oauth2|user_…" → "user_…").
    public static func userID(fromSessionJWT token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sub = root["sub"] as? String,
              let id = sub.split(separator: "|").last, id.hasPrefix("user_") else {
            return nil
        }
        return String(id)
    }

    /// Parses `/api/usage-summary`. Real shape (captured live):
    /// `{"billingCycleStart":"…","billingCycleEnd":"…","membershipType":"free",
    ///   "individualUsage":{"plan":{"totalPercentUsed":5, …}}}`
    /// `totalPercentUsed` is the "Included Usage" number the app displays; the
    /// cycle end is the reset date.
    public static func snapshot(fromSummaryJSON data: Data,
                                capturedAt: Date = Date()) -> UsageLimitSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = root["individualUsage"] as? [String: Any],
              let plan = usage["plan"] as? [String: Any],
              let percent = (plan["totalPercentUsed"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let membership = (root["membershipType"] as? String).map { $0.capitalized }
        let end = (root["billingCycleEnd"] as? String).flatMap(parseISO)
        let start = (root["billingCycleStart"] as? String).flatMap(parseISO)
        var windowMinutes = 30 * 24 * 60
        if let start, let end, end > start {
            windowMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        }
        return UsageLimitSnapshot(usedPercent: min(max(percent, 0), 100),
                                  windowMinutes: windowMinutes, resetsAt: end,
                                  capturedAt: capturedAt, plan: membership, isLive: true)
    }

    private static func parseISO(_ text: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
