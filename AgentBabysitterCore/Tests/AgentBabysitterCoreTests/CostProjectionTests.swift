import XCTest
@testable import AgentBabysitterCore

final class CostProjectionTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: 12))!
    }

    func testProjectsStraightLineOverTheMonth() {
        // $50 by July 10 → $5/day × 31 days = $155
        let estimate = CostProjection.monthEstimate(spentSoFar: 50,
                                                    now: date(2026, 7, 10),
                                                    calendar: calendar)
        XCTAssertEqual(estimate ?? 0, 155, accuracy: 1e-9)
    }

    func testRespectsShortMonths() {
        // February 2026: 28 days. $28 by Feb 7 → $4/day × 28 = $112
        let estimate = CostProjection.monthEstimate(spentSoFar: 28,
                                                    now: date(2026, 2, 7),
                                                    calendar: calendar)
        XCTAssertEqual(estimate ?? 0, 112, accuracy: 1e-9)
    }

    func testTooEarlyOrEmptyGivesNoEstimate() {
        XCTAssertNil(CostProjection.monthEstimate(spentSoFar: 400,
                                                  now: date(2026, 7, 2),
                                                  calendar: calendar),
                     "day 2: one heavy day would extrapolate wildly")
        XCTAssertNil(CostProjection.monthEstimate(spentSoFar: 0,
                                                  now: date(2026, 7, 20),
                                                  calendar: calendar))
    }

    func testMonthEndProjectsRoughlyItself() {
        let estimate = CostProjection.monthEstimate(spentSoFar: 310,
                                                    now: date(2026, 7, 31),
                                                    calendar: calendar)
        XCTAssertEqual(estimate ?? 0, 310, accuracy: 1e-9)
    }
}
