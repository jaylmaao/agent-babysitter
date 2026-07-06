import Foundation

/// The Sunday-evening "your week with AI agents" summary: one notification
/// per ISO week, computed from the stats ledger the window already shows.
public enum WeeklyDigest {

    public struct Digest: Equatable, Sendable {
        public let dollars: Double
        public let sessions: Int
        public let busiestProject: String?
    }

    /// Totals for the 7 local days ending today (inclusive).
    public static func compute(ledger: StatsLedger.Ledger, now: Date = Date(),
                               timeZone: TimeZone? = nil) -> Digest {
        let tz = timeZone ?? .current
        var calendar = Calendar.current
        calendar.timeZone = tz
        // Calendar day-walk, not fixed 86400s steps — DST days are 23/25h.
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .map { LocalDay.key(of: $0, timeZone: tz) }
        var dollars = 0.0
        var sessions = 0
        var byProject: [String: Double] = [:]
        for day in days {
            dollars += (ledger.costByAgent[day] ?? [:]).values.reduce(0, +)
            sessions += ledger.sessionCounts[day] ?? 0
            for (project, value) in ledger.costByProject[day] ?? [:] {
                byProject[project, default: 0] += value
            }
        }
        // Ties broken by name so the digest is deterministic.
        let busiest = byProject.filter { $0.value > 0 }
            .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        return Digest(dollars: dollars, sessions: sessions, busiestProject: busiest)
    }

    /// Due on Sunday from 6 PM local, once per week. `lastFired` is the
    /// week key of the last delivered digest (persisted by the app); firing
    /// any time before midnight keeps one late-evening check sufficient.
    public static func isDue(now: Date, lastFired: String?,
                             calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour], from: now)
        guard parts.weekday == 1, (parts.hour ?? 0) >= 18 else { return false }
        return lastFired != weekKey(for: now, calendar: calendar)
    }

    /// "2026-W27" — ISO week identity, matching once-per-week delivery.
    public static func weekKey(for now: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}
