import XCTest
@testable import AgentBabysitterCore

final class HookEventWatcherTests: XCTestCase {

    func testEmitsSignalsForAppendedEventsButSkipsStaleOnes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")

        // Stale event from a previous run — must NOT be emitted
        try "{\"session_id\":\"stale\",\"hook_event_name\":\"Stop\"}\n"
            .write(to: log, atomically: false, encoding: .utf8)

        let expectation = expectation(description: "fresh signal delivered")
        expectation.assertForOverFulfill = false
        let received = Locked<[(String, HookSignal.Kind)]>([])

        let watcher = HookEventWatcher(eventLogURL: log) { sessionID, signal in
            received.withLock { $0.append((sessionID, signal.kind)) }
            if sessionID == "fresh" { expectation.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)  // let the stream arm

        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        handle.write(Data("{\"session_id\":\"fresh\",\"hook_event_name\":\"Notification\"}\n".utf8))
        try handle.close()

        wait(for: [expectation], timeout: 10)
        let events = received.withLock { $0 }
        XCTAssertFalse(events.contains { $0.0 == "stale" },
                       "events from before the watcher started are stale")
        XCTAssertTrue(events.contains { $0.0 == "fresh" && $0.1 == .waitingForInput })
    }

    /// A status-line update (no hook_event_name, rate_limits present)
    /// appended to the shared log must reach the usage callback.
    func testEmitsUsageForStatusLineUpdates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")
        try Data().write(to: log)

        let expectation = expectation(description: "usage delivered")
        expectation.assertForOverFulfill = false
        let received = Locked<[UsageLimitSnapshot]>([])

        let watcher = HookEventWatcher(eventLogURL: log, onSignal: { _, _ in
            XCTFail("a pure status-line update carries no session signal")
        }, onUsage: { snapshot in
            received.withLock { $0.append(snapshot) }
            expectation.fulfill()
        })
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)

        let line = """
        {"session_id":"s1","model":{"id":"claude-opus-4-8"},\
        "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":"2026-07-05T18:00:00Z"}}}\n
        """
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try handle.close()

        wait(for: [expectation], timeout: 10)
        let snapshot = received.withLock { $0.first }
        XCTAssertEqual(snapshot?.usedPercent, 42.5)
        XCTAssertEqual(snapshot?.windowMinutes, 300)
        XCTAssertEqual(snapshot?.isLive, false)
    }
}
