import XCTest
@testable import AgentBabysitterCore

final class LocalDayTests: XCTestCase {

    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!      // UTC+5:30
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")! // UTC-7 (PDT)

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: - The day boundary follows the local timezone

    func testSameInstantFallsOnDifferentLocalDays() {
        // 02:00 UTC on Jul 5 is still Jul 4 evening in Los Angeles but already
        // Jul 5 morning in Kolkata.
        let moment = instant("2026-07-05T02:00:00Z")
        XCTAssertEqual(LocalDay.key(of: moment, timeZone: kolkata), "2026-07-05")
        XCTAssertEqual(LocalDay.key(of: moment, timeZone: losAngeles), "2026-07-04")
    }

    func testStartIsLocalMidnight() {
        let moment = instant("2026-07-05T02:00:00Z")
        // Kolkata midnight Jul 5 = 18:30 UTC Jul 4.
        XCTAssertEqual(LocalDay.start(of: moment, timeZone: kolkata),
                       instant("2026-07-04T18:30:00Z"))
        // LA midnight Jul 4 (PDT, UTC-7) = 07:00 UTC Jul 4.
        XCTAssertEqual(LocalDay.start(of: moment, timeZone: losAngeles),
                       instant("2026-07-04T07:00:00Z"))
    }

    func testKeyMatchesDailyCostHistory() {
        // DailyCostHistory now delegates to LocalDay, so they must agree.
        let moment = instant("2026-07-05T12:00:00Z")
        XCTAssertEqual(DailyCostHistory.key(for: moment), LocalDay.key(of: moment))
    }
}

final class CostAccumulatorLocalDayTests: XCTestCase {

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func entry(_ messageID: String, at timestamp: Date,
                       inputTokens: Int) -> TranscriptEntry {
        TranscriptEntry(kind: .assistant(AssistantPayload(
            messageID: messageID, model: "claude-opus-4-8", stopReason: .endTurn,
            usage: TokenUsage(inputTokens: inputTokens, outputTokens: 0,
                              cacheCreationInputTokens: 0, cacheReadInputTokens: 0),
            toolUses: [], hasText: true, hasThinking: false)),
            uuid: nil, timestamp: timestamp, sessionID: "s", cwd: nil, isSidechain: false)
    }

    func testEntriesStraddlingLocalMidnightSplitAcrossDays() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var accumulator = CostAccumulator(timeZone: la)
        // 23:00 PDT Jul 4 (before local midnight) and 01:00 PDT Jul 5 (after).
        accumulator.consume(entry("before", at: instant("2026-07-05T06:00:00Z"),
                                  inputTokens: 1_000_000))  // $5, Jul 4 local
        accumulator.consume(entry("after", at: instant("2026-07-05T08:00:00Z"),
                                  inputTokens: 2_000_000))  // $10, Jul 5 local

        let jul4 = LocalDay.start(of: instant("2026-07-05T06:00:00Z"), timeZone: la)
        let jul5 = LocalDay.start(of: instant("2026-07-05T08:00:00Z"), timeZone: la)
        XCTAssertNotEqual(jul4, jul5)
        XCTAssertEqual(accumulator.dailyCosts[jul4]?.dollars ?? 0, 5.0, accuracy: 0.0001)
        XCTAssertEqual(accumulator.dailyCosts[jul5]?.dollars ?? 0, 10.0, accuracy: 0.0001)
        // Total spans both days; the daily split is what "today" reads from.
        XCTAssertEqual(accumulator.cost.dollars, 15.0, accuracy: 0.0001)
    }

    func testJustAfterLocalMidnightIsANewDay() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var accumulator = CostAccumulator(timeZone: la)
        // Yesterday's big spend...
        accumulator.consume(entry("yesterday", at: instant("2026-07-05T06:00:00Z"),
                                  inputTokens: 20_000_000))  // 23:00 PDT Jul 4
        // ...and one small entry just after local midnight.
        accumulator.consume(entry("today", at: instant("2026-07-05T07:05:00Z"),
                                  inputTokens: 1_000_000))   // 00:05 PDT Jul 5

        let today = LocalDay.start(of: instant("2026-07-05T07:05:00Z"), timeZone: la)
        XCTAssertEqual(accumulator.dailyCosts[today]?.dollars ?? 0, 5.0, accuracy: 0.0001,
                       "today's bucket holds only the after-midnight entry")
    }
}
