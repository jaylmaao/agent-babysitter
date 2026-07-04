import XCTest
@testable import AgentBabysitterCore

private struct FakeScanner: ProcessScanning {
    let results: [RunningProcess]
    let fails: Bool

    func scanClaudeProcesses() async throws -> [RunningProcess] {
        if fails { throw CocoaError(.fileReadUnknown) }
        return results
    }
}

final class ProcessWatcherTests: XCTestCase {

    func testPollPublishesScannedProcesses() async {
        let expected = [RunningProcess(pid: 42, cwd: "/Users/dev/appA")]
        let watcher = ProcessWatcher(scanner: FakeScanner(results: expected, fails: false))
        await watcher.pollOnce()
        let update = await watcher.latest
        XCTAssertEqual(update.processes, expected)
        XCTAssertFalse(update.degraded)
    }

    func testScannerFailureDegradesButKeepsLastKnownProcesses() async {
        let known = [RunningProcess(pid: 42, cwd: "/Users/dev/appA")]
        let watcher = ProcessWatcher(scanner: FakeScanner(results: known, fails: false))
        await watcher.pollOnce()

        // Same watcher, but the world broke: simulate by swapping in a failing poll
        let failing = ProcessWatcher(scanner: FakeScanner(results: [], fails: true))
        await failing.pollOnce()
        let update = await failing.latest
        XCTAssertTrue(update.degraded)
        XCTAssertEqual(update.processes, [], "no earlier state to preserve here")
    }

    func testFailureAfterSuccessPreservesStaleProcessList() async {
        // Drive one watcher through success then failure using a stateful scanner
        final class FlakyScanner: ProcessScanning, @unchecked Sendable {
            var callCount = 0
            func scanClaudeProcesses() async throws -> [RunningProcess] {
                callCount += 1
                if callCount > 1 { throw CocoaError(.fileReadUnknown) }
                return [RunningProcess(pid: 7, cwd: "/x")]
            }
        }
        let watcher = ProcessWatcher(scanner: FlakyScanner())
        await watcher.pollOnce()
        await watcher.pollOnce()
        let update = await watcher.latest
        XCTAssertTrue(update.degraded)
        XCTAssertEqual(update.processes, [RunningProcess(pid: 7, cwd: "/x")],
                       "degraded mode keeps the last good scan instead of marking everything Ended")
    }

    func testRealScannerRunsWithoutThrowing() async throws {
        // Smoke test against the actual ps/lsof binaries on this machine.
        let scanner = ShellProcessScanner()
        _ = try await scanner.scanClaudeProcesses()
    }
}
