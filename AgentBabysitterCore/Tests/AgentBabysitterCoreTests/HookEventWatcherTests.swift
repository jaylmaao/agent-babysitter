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
}
