import XCTest
@testable import AgentBabysitterCore

/// The whole point of `PlatformPaths` is that a Windows port edits ONE file.
/// The risk that creates: someone edits that file and silently moves every
/// macOS path with it. These tests pin the macOS answers to the literals the
/// adapters used before the indirection, so a port can add branches but can
/// never change what macOS resolves to.
final class PlatformPathsTests: XCTestCase {

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    func testHomeIsTheCurrentUsersHome() {
        XCTAssertEqual(PlatformPaths.home.path, home.path)
    }

    func testDotDirectoriesResolveUnderHome() {
        // The exact strings the adapters pass, spot-checked end to end.
        XCTAssertEqual(PlatformPaths.homeDirectory(".codex/sessions").path,
                       home.appendingPathComponent(".codex/sessions").path)
        XCTAssertEqual(PlatformPaths.homeDirectory(".claude/projects").path,
                       home.appendingPathComponent(".claude/projects").path)
        XCTAssertEqual(PlatformPaths.homeDirectory(".hermes").path,
                       home.appendingPathComponent(".hermes").path)
    }

    func testApplicationSupportIsTheMacConvention() {
        XCTAssertEqual(PlatformPaths.applicationSupport.path,
                       home.appendingPathComponent("Library/Application Support").path)
    }

    func testApplicationSupportSubpathsMatchTheOldLiterals() {
        XCTAssertEqual(
            PlatformPaths.applicationSupport("AgentBabysitter/events.jsonl").path,
            home.appendingPathComponent(
                "Library/Application Support/AgentBabysitter/events.jsonl").path)
        XCTAssertEqual(
            PlatformPaths.applicationSupport(
                "Antigravity IDE/User/globalStorage/state.vscdb").path,
            home.appendingPathComponent(
                "Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb").path)
    }

    func testICloudDriveIsPresentOnApplePlatforms() {
        // Present as a PATH regardless of whether iCloud Drive is enabled —
        // callers do their own fileExists check before using it.
        XCTAssertEqual(PlatformPaths.iCloudDrive?.path,
                       home.appendingPathComponent(
                           "Library/Mobile Documents/com~apple~CloudDocs").path)
    }

    /// The adapters' own defaults, not just the helper — this is what would
    /// actually break if a port rewired the helper wrongly.
    func testAdapterDefaultRootsAreUnchanged() {
        XCTAssertEqual(CodexAdapter().transcriptRoot.path,
                       home.appendingPathComponent(".codex/sessions").path)
        XCTAssertEqual(ClaudeCodeAdapter().transcriptRoot.path,
                       home.appendingPathComponent(".claude/projects").path)
        XCTAssertEqual(HermesAdapter().transcriptRoot.path,
                       home.appendingPathComponent(".hermes").path)
        XCTAssertEqual(CursorAdapter().transcriptRoot.path,
                       home.appendingPathComponent(
                           "Library/Application Support/Cursor/User/globalStorage").path)
        XCTAssertEqual(ManusAdapter().transcriptRoot.path,
                       home.appendingPathComponent(
                           "Library/Application Support/Manus/IndexedDB").path)
        XCTAssertEqual(HooksInstaller.defaultEventLogURL.path,
                       home.appendingPathComponent(
                           "Library/Application Support/AgentBabysitter/events.jsonl").path)
        XCTAssertEqual(HooksInstaller.defaultSettingsURL.path,
                       home.appendingPathComponent(".claude/settings.json").path)
    }
}
