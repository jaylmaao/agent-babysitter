import Foundation

/// The one definition of "which day is it" used everywhere the app computes
/// "today" — the menu's today cost, the persisted cost history, and the
/// stats. It always follows the CURRENT local timezone, re-read per call
/// (never frozen at init), so today's cost resets at local midnight. The
/// `timeZone` parameter defaults to the live zone; tests pin an explicit one.
public enum LocalDay {

    /// Local midnight at the start of `date`'s day — the key cost buckets use.
    public static func start(of date: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    /// `date`'s local day as "yyyy-MM-dd" (the persisted history/stats key).
    public static func key(of date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
