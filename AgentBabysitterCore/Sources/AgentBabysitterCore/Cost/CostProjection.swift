import Foundation

/// Straight-line "at this pace" month estimate from month-to-date spend.
public enum CostProjection {

    /// nil when it would mislead: fewer than 3 days into the month (one big
    /// day would extrapolate wildly) or nothing spent yet.
    public static func monthEstimate(spentSoFar: Double, now: Date,
                                     calendar: Calendar = .current) -> Double? {
        let daysElapsed = calendar.component(.day, from: now)
        guard daysElapsed >= 3, spentSoFar > 0,
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count
        else { return nil }
        return spentSoFar / Double(daysElapsed) * Double(daysInMonth)
    }
}
