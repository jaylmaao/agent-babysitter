import XCTest
@testable import AgentBabysitterCore

final class HooksInstallerTests: XCTestCase {

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hookEntries(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    private func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    // MARK: - Install

    func testInstallIntoMissingSettingsCreatesHooks() throws {
        let result = try HooksInstaller.settingsWithHooksInstalled(nil)
        let root = try json(result)
        for event in ["Notification", "Stop"] {
            let cmds = commands(in: hookEntries(root, event))
            XCTAssertEqual(cmds.count, 1, "\(event) should have exactly our hook")
            XCTAssertTrue(cmds[0].contains(HooksInstaller.marker))
            XCTAssertTrue(cmds[0].contains("events.jsonl"))
        }
    }

    func testInstallPreservesExistingUserHooksAndSettings() throws {
        let existing = """
        {
          "model": "opus",
          "hooks": {
            "Notification": [
              {"hooks": [{"type": "command", "command": "say 'user hook'"}]}
            ],
            "PreToolUse": [
              {"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/lint"}]}
            ]
          }
        }
        """
        let result = try HooksInstaller.settingsWithHooksInstalled(Data(existing.utf8))
        let root = try json(result)

        // Untouched user config
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertEqual(commands(in: hookEntries(root, "PreToolUse")), ["/usr/local/bin/lint"])

        // User Notification hook kept, ours appended
        let notificationCommands = commands(in: hookEntries(root, "Notification"))
        XCTAssertEqual(notificationCommands.count, 2)
        XCTAssertEqual(notificationCommands[0], "say 'user hook'")
        XCTAssertTrue(notificationCommands[1].contains(HooksInstaller.marker))

        // Stop added fresh
        XCTAssertEqual(commands(in: hookEntries(root, "Stop")).count, 1)
    }

    func testInstallIsIdempotent() throws {
        let once = try HooksInstaller.settingsWithHooksInstalled(nil)
        let twice = try HooksInstaller.settingsWithHooksInstalled(once)
        let root = try json(twice)
        XCTAssertEqual(commands(in: hookEntries(root, "Notification")).count, 1)
        XCTAssertEqual(commands(in: hookEntries(root, "Stop")).count, 1)
    }

    func testInstallThrowsOnMalformedSettingsWithoutWriting() {
        let malformed = Data("{ this is not json".utf8)
        XCTAssertThrowsError(try HooksInstaller.settingsWithHooksInstalled(malformed)) { error in
            XCTAssertTrue(error is HooksInstaller.SettingsError)
        }
        // Non-object JSON is also unparseable-as-settings
        XCTAssertThrowsError(try HooksInstaller.settingsWithHooksInstalled(Data("[1,2]".utf8)))
    }

    // MARK: - Remove

    func testRemoveDeletesOnlyOurHooks() throws {
        let existing = """
        {
          "hooks": {
            "Notification": [
              {"hooks": [{"type": "command", "command": "say 'user hook'"}]}
            ]
          }
        }
        """
        let installed = try HooksInstaller.settingsWithHooksInstalled(Data(existing.utf8))
        let removed = try HooksInstaller.settingsWithHooksRemoved(installed)
        let root = try json(removed)

        XCTAssertEqual(commands(in: hookEntries(root, "Notification")), ["say 'user hook'"])
        XCTAssertTrue(hookEntries(root, "Stop").isEmpty)
    }

    func testRemoveOnCleanSettingsIsNoOp() throws {
        let clean = Data("{\"model\": \"opus\"}".utf8)
        let result = try HooksInstaller.settingsWithHooksRemoved(clean)
        XCTAssertEqual(try json(result)["model"] as? String, "opus")
    }

    func testRemoveThrowsOnMalformedSettings() {
        XCTAssertThrowsError(try HooksInstaller.settingsWithHooksRemoved(Data("not json".utf8)))
    }

    func testInstallDetection() throws {
        XCTAssertFalse(HooksInstaller.isInstalled(in: nil))
        XCTAssertFalse(HooksInstaller.isInstalled(in: Data("{}".utf8)))
        let installed = try HooksInstaller.settingsWithHooksInstalled(nil)
        XCTAssertTrue(HooksInstaller.isInstalled(in: installed))
    }
}

final class HookEventParserTests: XCTestCase {

    func testParsesNotificationEvent() {
        let line = """
        {"session_id":"abc-123","transcript_path":"/x/y.jsonl","hook_event_name":"Notification",\
        "message":"Claude needs your permission to use Bash"}
        """
        let event = HookEventParser.parse(line: Data(line.utf8))
        XCTAssertEqual(event?.sessionID, "abc-123")
        XCTAssertEqual(event?.kind, .waitingForInput)
    }

    func testParsesStopEvent() {
        let line = "{\"session_id\":\"abc-123\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}"
        let event = HookEventParser.parse(line: Data(line.utf8))
        XCTAssertEqual(event?.sessionID, "abc-123")
        XCTAssertEqual(event?.kind, .turnCompleted)
    }

    func testIgnoresUnknownEventsAndGarbage() {
        XCTAssertNil(HookEventParser.parse(line: Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"x\"}".utf8)))
        XCTAssertNil(HookEventParser.parse(line: Data("garbage".utf8)))
        XCTAssertNil(HookEventParser.parse(line: Data()))
    }
}
