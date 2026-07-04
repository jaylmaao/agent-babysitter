import XCTest
@testable import AgentBabysitterCore

final class ProcessParsingTests: XCTestCase {

    // MARK: - ps output → claude CLI candidates

    func testFindsNativeClaudeBinary() {
        let ps = """
          312 /usr/sbin/distnoted
        41234 /Users/dev/.local/bin/claude
        41567 claude
          999 /Applications/Claude.app/Contents/MacOS/Claude
        """
        XCTAssertEqual(ProcessOutputParser.claudePIDs(fromPS: ps), [41234, 41567])
    }

    func testFindsNodeHostedClaudeCLI() {
        let ps = """
        5100 node /Users/dev/.nvm/versions/node/v22.1.0/bin/claude --resume
        5200 node /Users/dev/projects/server/index.js
        5300 /opt/homebrew/bin/bun /Users/dev/.bun/bin/claude
        """
        XCTAssertEqual(ProcessOutputParser.claudePIDs(fromPS: ps), [5100, 5300])
    }

    func testDesktopAppAndHelpersAreNotCLIProcesses() {
        let ps = """
        6118 /Applications/Claude.app/Contents/MacOS/Claude
        6125 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process
        7001 /usr/bin/grep claude
        7002 vim claude-notes.md
        """
        XCTAssertEqual(ProcessOutputParser.claudePIDs(fromPS: ps), [])
    }

    func testIgnoresGarbagePSLines() {
        XCTAssertEqual(ProcessOutputParser.claudePIDs(fromPS: "notapid claude\n\n  \n"), [])
    }

    // MARK: - ps comm output (full executable path, may contain spaces)

    func testCommMatchesClaudeBinariesInPathsWithSpaces() {
        // The Claude desktop app's embedded Claude Code runtime — the path
        // contains spaces, which args-based tokenization gets wrong.
        let ps = """
        6237 /Users/dev/Library/Application Support/Claude/claude-code/2.1.197/claude.app/Contents/MacOS/claude
        6236 /Applications/Claude.app/Contents/Helpers/disclaimer
        6118 /Applications/Claude.app/Contents/MacOS/Claude
        41234 /Users/dev/.local/bin/claude
          312 /usr/sbin/distnoted
        """
        XCTAssertEqual(ProcessOutputParser.claudePIDs(fromPSComm: ps), [6237, 41234])
    }

    func testCommIsCaseSensitiveSoDesktopElectronIsExcluded() {
        // "Claude" (the Electron shell) is not the CLI runtime "claude"
        XCTAssertEqual(ProcessOutputParser.claudePIDs(
            fromPSComm: "1 /Applications/Claude.app/Contents/MacOS/Claude"), [])
    }

    // MARK: - lsof -Fn output → pid:cwd map

    func testParsesLSOFFieldOutputForMultiplePIDs() {
        let lsof = """
        p5100
        fcwd
        n/Users/dev/projectA
        p5300
        fcwd
        n/Users/dev/project B with spaces
        """
        XCTAssertEqual(ProcessOutputParser.cwdsByPID(fromLSOF: lsof),
                       [5100: "/Users/dev/projectA", 5300: "/Users/dev/project B with spaces"])
    }

    func testLSOFMissingCWDForOnePIDIsSkipped() {
        let lsof = """
        p5100
        fcwd
        n/Users/dev/projectA
        p5300
        """
        XCTAssertEqual(ProcessOutputParser.cwdsByPID(fromLSOF: lsof), [5100: "/Users/dev/projectA"])
    }

    func testLSOFEmptyOutput() {
        XCTAssertEqual(ProcessOutputParser.cwdsByPID(fromLSOF: ""), [:])
    }
}

final class SessionProcessMatcherTests: XCTestCase {

    // MARK: - cwd munging (verified against real ~/.claude/projects dir names)

    func testMungingMatchesRealProjectDirNames() {
        XCTAssertEqual(SessionProcessMatcher.projectDirName(forCWD: "/Users/jay"),
                       "-Users-jay")
        XCTAssertEqual(SessionProcessMatcher.projectDirName(forCWD: "/Users/jay/.openclaw/workspace"),
                       "-Users-jay--openclaw-workspace")
        XCTAssertEqual(
            SessionProcessMatcher.projectDirName(
                forCWD: "/private/var/folders/hq/yhm5d7kj07gfh6d5b7bb2b840000gn/T/openclaw-crestodian-planner-CJ3E6S"),
            "-private-var-folders-hq-yhm5d7kj07gfh6d5b7bb2b840000gn-T-openclaw-crestodian-planner-CJ3E6S")
    }

    func testMungingReplacesNonAlphanumerics() {
        XCTAssertEqual(SessionProcessMatcher.projectDirName(forCWD: "/tmp/my_app v2.0"),
                       "-tmp-my-app-v2-0")
    }

    // MARK: - process ↔ session matching

    private func session(_ id: String, dir: String, modified: TimeInterval) -> SessionFileInfo {
        SessionFileInfo(sessionID: id, projectDirName: dir,
                        lastModified: Date(timeIntervalSince1970: modified))
    }

    func testSimpleOneToOneMatch() {
        let match = SessionProcessMatcher.match(
            processes: [RunningProcess(pid: 100, cwd: "/Users/dev/appA")],
            sessions: [session("s1", dir: "-Users-dev-appA", modified: 1000)])
        XCTAssertEqual(match, ["s1": 100])
    }

    func testSessionWithoutProcessIsUnmatched() {
        let match = SessionProcessMatcher.match(
            processes: [],
            sessions: [session("s1", dir: "-Users-dev-appA", modified: 1000)])
        XCTAssertTrue(match.isEmpty)
    }

    func testMostRecentSessionWinsWhenMultipleShareCWD() {
        // Two transcripts in the same project dir, one live process:
        // the most recently modified transcript owns the process.
        let match = SessionProcessMatcher.match(
            processes: [RunningProcess(pid: 100, cwd: "/Users/dev/appA")],
            sessions: [session("old", dir: "-Users-dev-appA", modified: 1000),
                       session("new", dir: "-Users-dev-appA", modified: 2000)])
        XCTAssertEqual(match, ["new": 100])
    }

    func testTwoProcessesSameCWDMatchTwoMostRecentSessions() {
        let match = SessionProcessMatcher.match(
            processes: [RunningProcess(pid: 100, cwd: "/Users/dev/appA"),
                        RunningProcess(pid: 200, cwd: "/Users/dev/appA")],
            sessions: [session("s-old", dir: "-Users-dev-appA", modified: 1000),
                       session("s-mid", dir: "-Users-dev-appA", modified: 2000),
                       session("s-new", dir: "-Users-dev-appA", modified: 3000)])
        XCTAssertEqual(Set(match.keys), ["s-new", "s-mid"])
        XCTAssertEqual(Set(match.values), [100, 200])
        // Deterministic: newest session pairs with lowest pid order stable across polls
        XCTAssertEqual(match["s-new"], 100)
        XCTAssertEqual(match["s-mid"], 200)
    }

    func testProcessInUnrelatedCWDMatchesNothing() {
        let match = SessionProcessMatcher.match(
            processes: [RunningProcess(pid: 100, cwd: "/somewhere/else")],
            sessions: [session("s1", dir: "-Users-dev-appA", modified: 1000)])
        XCTAssertTrue(match.isEmpty)
    }

    func testDifferentProjectsMatchIndependently() {
        let match = SessionProcessMatcher.match(
            processes: [RunningProcess(pid: 100, cwd: "/Users/dev/appA"),
                        RunningProcess(pid: 200, cwd: "/Users/dev/appB")],
            sessions: [session("a", dir: "-Users-dev-appA", modified: 1000),
                       session("b", dir: "-Users-dev-appB", modified: 1000)])
        XCTAssertEqual(match, ["a": 100, "b": 200])
    }
}
