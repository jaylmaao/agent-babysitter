import XCTest
@testable import AgentBabysitterCore

final class WaitingReminderPlannerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_783_158_000)
    private let tenMinutes: TimeInterval = 600

    private func row(_ id: String, _ state: SessionState) -> SessionRow {
        SessionRow(id: id, projectName: "proj", state: state,
                   turnStartedAt: nil, lastGrowthAt: nil, isUnreadable: false,
                   pid: 1, cwd: nil)
    }

    func testRemindsOncePerEpisodeAfterInterval() {
        var planner = WaitingReminderPlanner()
        let waiting = [row("a", .waitingForInput)]
        // Not yet due
        XCTAssertEqual(planner.dueReminders(rows: waiting, interval: tenMinutes, now: base), [])
        XCTAssertEqual(planner.dueReminders(rows: waiting, interval: tenMinutes,
                                            now: base.addingTimeInterval(599)), [])
        // Due exactly once
        XCTAssertEqual(planner.dueReminders(rows: waiting, interval: tenMinutes,
                                            now: base.addingTimeInterval(600)), ["a"])
        XCTAssertEqual(planner.dueReminders(rows: waiting, interval: tenMinutes,
                                            now: base.addingTimeInterval(3000)), [])
    }

    func testLeavingWaitingResetsTheEpisode() {
        var planner = WaitingReminderPlanner()
        _ = planner.dueReminders(rows: [row("a", .waitingForInput)],
                                 interval: tenMinutes, now: base)
        // Answered: back to working, then waiting again → fresh episode
        _ = planner.dueReminders(rows: [row("a", .working)],
                                 interval: tenMinutes, now: base.addingTimeInterval(300))
        let t2 = base.addingTimeInterval(700)
        XCTAssertEqual(planner.dueReminders(rows: [row("a", .waitingForInput)],
                                            interval: tenMinutes, now: t2), [],
                       "new episode starts its own clock")
        XCTAssertEqual(planner.dueReminders(rows: [row("a", .waitingForInput)],
                                            interval: tenMinutes,
                                            now: t2.addingTimeInterval(600)), ["a"],
                       "second episode earns its own reminder")
    }

    func testVanishedSessionsAreForgotten() {
        var planner = WaitingReminderPlanner()
        _ = planner.dueReminders(rows: [row("a", .waitingForInput)],
                                 interval: tenMinutes, now: base)
        _ = planner.dueReminders(rows: [], interval: tenMinutes,
                                 now: base.addingTimeInterval(60))
        // Comes back waiting much later: fresh episode, not instantly due
        XCTAssertEqual(planner.dueReminders(rows: [row("a", .waitingForInput)],
                                            interval: tenMinutes,
                                            now: base.addingTimeInterval(5000)), [])
    }

    func testMultipleSessionsTrackIndependently() {
        var planner = WaitingReminderPlanner()
        _ = planner.dueReminders(rows: [row("a", .waitingForInput), row("b", .working)],
                                 interval: tenMinutes, now: base)
        let later = base.addingTimeInterval(600)
        XCTAssertEqual(planner.dueReminders(
            rows: [row("a", .waitingForInput), row("b", .waitingForInput)],
            interval: tenMinutes, now: later), ["a"])
    }
}
