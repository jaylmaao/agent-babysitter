import XCTest
@testable import AgentBabysitterCore

final class WeeklyDigestTests: XCTestCase {

    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = kolkata
        return c
    }

    /// 2026-07-05 is a Sunday.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testComputeSumsLastSevenLocalDays() {
        var ledger = StatsLedger.Ledger()
        let now = date(2026, 7, 5, 19)
        // Inside the window: today and 6 days back
        ledger.costByAgent["2026-07-05"] = ["claude-code": 10, "codex": 2]
        ledger.costByAgent["2026-06-29"] = ["claude-code": 5]
        // Outside: 7 days back
        ledger.costByAgent["2026-06-28"] = ["claude-code": 100]
        ledger.sessionCounts = ["2026-07-05": 4, "2026-06-29": 2, "2026-06-28": 50]
        ledger.costByProject["2026-07-05"] = ["babysitter": 9, "velmori": 3]
        ledger.costByProject["2026-06-29"] = ["velmori": 8]

        let digest = WeeklyDigest.compute(ledger: ledger, now: now, timeZone: kolkata)
        XCTAssertEqual(digest.dollars, 17, accuracy: 1e-9)
        XCTAssertEqual(digest.sessions, 6)
        XCTAssertEqual(digest.busiestProject, "velmori")  // 11 vs 9 across the week
    }

    func testEmptyWeekHasNoBusiestProject() {
        let digest = WeeklyDigest.compute(ledger: .init(),
                                          now: date(2026, 7, 5, 19), timeZone: kolkata)
        XCTAssertEqual(digest.dollars, 0)
        XCTAssertEqual(digest.sessions, 0)
        XCTAssertNil(digest.busiestProject)
    }

    func testDueOnlySundayEveningOncePerWeek() {
        // Saturday evening: not due
        XCTAssertFalse(WeeklyDigest.isDue(now: date(2026, 7, 4, 19),
                                          lastFired: nil, calendar: calendar))
        // Sunday 17:59: not yet
        XCTAssertFalse(WeeklyDigest.isDue(now: date(2026, 7, 5, 17, 59),
                                          lastFired: nil, calendar: calendar))
        // Sunday 18:00: due
        XCTAssertTrue(WeeklyDigest.isDue(now: date(2026, 7, 5, 18),
                                         lastFired: nil, calendar: calendar))
        // Later the same evening, already fired this week: not due again
        let key = WeeklyDigest.weekKey(for: date(2026, 7, 5, 18), calendar: calendar)
        XCTAssertFalse(WeeklyDigest.isDue(now: date(2026, 7, 5, 22),
                                          lastFired: key, calendar: calendar))
        // Next Sunday: due again (different week key)
        XCTAssertTrue(WeeklyDigest.isDue(now: date(2026, 7, 12, 18),
                                         lastFired: key, calendar: calendar))
    }

    func testWeekKeyIsStableWithinAWeekAndChangesAcross() {
        let sunday = WeeklyDigest.weekKey(for: date(2026, 7, 5, 20), calendar: calendar)
        let thatMonday = WeeklyDigest.weekKey(for: date(2026, 6, 29, 9), calendar: calendar)
        XCTAssertEqual(sunday, thatMonday, "ISO week runs Monday–Sunday")
        XCTAssertNotEqual(sunday, WeeklyDigest.weekKey(for: date(2026, 7, 6, 9),
                                                       calendar: calendar))
    }
}
