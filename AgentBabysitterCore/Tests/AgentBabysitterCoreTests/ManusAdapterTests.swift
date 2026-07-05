import XCTest
@testable import AgentBabysitterCore

final class ManusAdapterTests: XCTestCase {

    private func makeAppSupport() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("manus-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Layout captured from a real install: one leveldb dir per IndexedDB
    /// database under App Support/Manus/IndexedDB.
    private func makeLevelDB(appSupport: URL, name: String,
                             fileAges: [TimeInterval]) throws -> URL {
        let dir = appSupport.appendingPathComponent(
            "Manus/IndexedDB/\(name).indexeddb.leveldb")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, age) in fileAges.enumerated() {
            let file = dir.appendingPathComponent(String(format: "%06d.log", index))
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-age)],
                ofItemAtPath: file.path)
        }
        return dir
    }

    func testDiscoversLevelDBDirsWithNewestInnerWrite() throws {
        let appSupport = try makeAppSupport()
        let fresh = try makeLevelDB(appSupport: appSupport, name: "app_manus_0",
                                    fileAges: [30, 7200])
        _ = try makeLevelDB(appSupport: appSupport, name: "app_stale_0",
                            fileAges: [7200])
        let adapter = ManusAdapter(appSupport: appSupport)

        let found = adapter.recentTranscripts(maxAge: 3600, now: Date())
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].sessionID, "app_manus_0")
        // Path compare: temp dirs mix /var and /private/var URL forms.
        XCTAssertEqual(found[0].url?.resolvingSymlinksInPath().path,
                       fresh.resolvingSymlinksInPath().path)
        // Newest file inside wins, not the dir's own mtime.
        XCTAssertEqual(found[0].lastModified.timeIntervalSinceNow, -30, accuracy: 5)
    }

    func testInnerFileCanonicalizesToItsLevelDBDir() throws {
        let appSupport = try makeAppSupport()
        let dir = try makeLevelDB(appSupport: appSupport, name: "app_manus_0",
                                  fileAges: [10])
        let adapter = ManusAdapter(appSupport: appSupport)
        let inner = dir.appendingPathComponent("000042.log").path
        XCTAssertTrue(adapter.isTranscript(path: inner))
        XCTAssertEqual(adapter.canonicalTranscriptURL(forPath: inner).path, dir.path)
        XCTAssertEqual(adapter.sessionID(forTranscript: dir), "app_manus_0")
    }

    func testAgentPIDsMatchesMainBinaryNotHelpers() {
        let adapter = ManusAdapter()
        let comm = """
        100 /Applications/Manus.app/Contents/MacOS/Manus
        200 /Applications/Manus.app/Contents/Frameworks/Manus Helper (Renderer).app/Contents/MacOS/Manus Helper (Renderer)
        300 zsh
        """
        XCTAssertEqual(adapter.agentPIDs(psComm: comm, psArgs: ""), [100])
    }

    func testUsesNetworkActivityForStreamedCloudSessions() {
        XCTAssertTrue(ManusAdapter().usesNetworkActivity)
        XCTAssertTrue(ManusAdapter().isActivityBased)
    }

    func testDirActivityReaderTracksNewestWrite() throws {
        let appSupport = try makeAppSupport()
        let dir = try makeLevelDB(appSupport: appSupport, name: "app_manus_0",
                                  fileAges: [2])
        let active = DirActivityReader(url: dir, sessionID: "app_manus_0",
                                       entrypoint: "Manus", idleCutoff: 6)
        try active.refresh()
        XCTAssertEqual(active.turnPhase, .midTurn)

        // Same write viewed past the cutoff reads as done.
        let idle = DirActivityReader(url: dir, sessionID: "app_manus_0",
                                     entrypoint: "Manus", idleCutoff: 1)
        try idle.refresh()
        XCTAssertEqual(idle.turnPhase, .completed)
    }
}
