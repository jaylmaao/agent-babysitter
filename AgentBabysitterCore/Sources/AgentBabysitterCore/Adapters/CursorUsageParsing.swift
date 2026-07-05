import Foundation

/// Pure parsing for the opt-in live Cursor usage fetch — in Core so it's
/// unit-tested; the app layer does the networking. Verified live 2026-07:
/// `GET cursor.com/api/usage?user=<id>` with the WorkosCursorSessionToken
/// cookie (`<userID>::<sessionJWT>`) returns request counts per model plus
/// the billing-cycle start. Legacy request-capped plans carry
/// `maxRequestUsage` (→ a real 0-100); current plans return null there and
/// the row stays plan-only.
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

    /// Parses `/api/usage`. Real shape (captured live):
    /// `{"gpt-4":{"numRequests":0,"numRequestsTotal":0,"numTokens":0,
    ///   "maxTokenUsage":null,"maxRequestUsage":null},
    ///  "startOfMonth":"2026-06-12T16:31:12.692Z"}`
    public static func snapshot(fromUsageJSON data: Data, plan: String?,
                                capturedAt: Date = Date()) -> UsageLimitSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let premium = root["gpt-4"] as? [String: Any] else { return nil }
        let requests = (premium["numRequests"] as? Double) ?? 0
        let cap = premium["maxRequestUsage"] as? Double

        var resets: Date?
        var windowMinutes = 30 * 24 * 60
        if let text = root["startOfMonth"] as? String,
           let start = parseISO(text),
           let end = Calendar.current.date(byAdding: .month, value: 1, to: start) {
            resets = end
            windowMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        }

        if let cap, cap > 0 {
            return UsageLimitSnapshot(
                usedPercent: min(max(requests / cap * 100, 0), 100),
                windowMinutes: windowMinutes, resetsAt: resets,
                capturedAt: capturedAt, plan: plan, isLive: true)
        }
        // No cap published (current plans): honest plan-only row, with the
        // live request count folded into the label when there is one.
        let label: String? = requests > 0
            ? [plan, "\(Int(requests)) requests"].compactMap { $0 }.joined(separator: " · ")
            : plan
        return UsageLimitSnapshot(usedPercent: nil, windowMinutes: windowMinutes,
                                  resetsAt: resets, capturedAt: capturedAt,
                                  plan: label, isLive: true)
    }

    private static func parseISO(_ text: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
