import XCTest
@testable import AgentBabysitterCore

final class NotificationPlannerTests: XCTestCase {

    private func row(_ id: String, _ state: SessionState) -> SessionRow {
        SessionRow(id: id, projectName: id, state: state, turnStartedAt: nil,
                   lastGrowthAt: nil, isUnreadable: false, pid: 1, cwd: nil)
    }

    func testNoNotificationsOnFirstObservation() {
        var planner = NotificationPlanner()
        // Launch scan finds sessions already waiting/stalled/done: stay quiet,
        // the user just opened the app and can see the list.
        let events = planner.events(for: [row("a", .waitingForInput),
                                          row("b", .stalled),
                                          row("c", .done)])
        XCTAssertTrue(events.isEmpty)
    }

    func testWaitingFiresOncePerEpisode() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])

        let first = planner.events(for: [row("a", .waitingForInput)])
        XCTAssertEqual(first, [NotificationEvent(sessionID: "a", kind: .waitingForInput)])

        // Still waiting: no re-fire
        XCTAssertTrue(planner.events(for: [row("a", .waitingForInput)]).isEmpty)

        // Episode ends, next waiting episode fires again
        _ = planner.events(for: [row("a", .working)])
        let second = planner.events(for: [row("a", .waitingForInput)])
        XCTAssertEqual(second, [NotificationEvent(sessionID: "a", kind: .waitingForInput)])
    }

    func testTurnCompletionFiresOnlyAfterActivity() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])
        let events = planner.events(for: [row("a", .done)])
        XCTAssertEqual(events, [NotificationEvent(sessionID: "a", kind: .turnCompleted)])

        // done -> done: nothing new
        XCTAssertTrue(planner.events(for: [row("a", .done)]).isEmpty)
    }

    func testDoneAfterWaitingAlsoCounts() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])
        _ = planner.events(for: [row("a", .waitingForInput)])
        let events = planner.events(for: [row("a", .done)])
        XCTAssertEqual(events, [NotificationEvent(sessionID: "a", kind: .turnCompleted)])
    }

    func testStallFiresOnceAndResetsOnResume() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])

        XCTAssertEqual(planner.events(for: [row("a", .stalled)]),
                       [NotificationEvent(sessionID: "a", kind: .stalled)])
        XCTAssertTrue(planner.events(for: [row("a", .stalled)]).isEmpty)

        // Resumes, then stalls again -> fires again
        _ = planner.events(for: [row("a", .working)])
        XCTAssertEqual(planner.events(for: [row("a", .stalled)]),
                       [NotificationEvent(sessionID: "a", kind: .stalled)])
    }

    func testEndedSessionIsForgotten() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])
        _ = planner.events(for: [row("a", .ended)])
        // Session comes back (same id re-observed): treat like first sight
        XCTAssertTrue(planner.events(for: [row("a", .waitingForInput)]).isEmpty)
    }

    func testMultipleSessionsAreIndependent() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working), row("b", .working)])
        let events = planner.events(for: [row("a", .waitingForInput), row("b", .done)])
        XCTAssertEqual(Set(events), [NotificationEvent(sessionID: "a", kind: .waitingForInput),
                                     NotificationEvent(sessionID: "b", kind: .turnCompleted)])
    }

    func testWorkingToDoneWithoutEverWaitingOrStallingStillFires() {
        var planner = NotificationPlanner()
        _ = planner.events(for: [row("a", .working)])
        XCTAssertEqual(planner.events(for: [row("a", .done)]),
                       [NotificationEvent(sessionID: "a", kind: .turnCompleted)])
    }
}

final class ProcessAncestryTests: XCTestCase {

    func testAncestorsOfCurrentProcessIncludeParentAndTerminate() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ancestors = ProcessAncestry.ancestorPIDs(of: pid)
        XCTAssertFalse(ancestors.isEmpty)
        XCTAssertEqual(ancestors.first, getppid())
        XCTAssertEqual(ancestors.last, 1, "chain should reach launchd")
        XCTAssertLessThan(ancestors.count, 30)
    }

    func testUnknownPIDReturnsEmpty() {
        XCTAssertTrue(ProcessAncestry.ancestorPIDs(of: 99_999_999).isEmpty)
    }
}
