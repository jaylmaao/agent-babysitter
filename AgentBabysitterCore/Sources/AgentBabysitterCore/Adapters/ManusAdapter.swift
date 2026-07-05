import Foundation

/// Manus — the macOS desktop app (an Electron shell over the cloud agent;
/// verified 2026-07: no local transcripts, chats cached in IndexedDB).
/// Sessions are cloud-side, so this surface is one activity row per
/// profile driven by the cache's leveldb writes plus the same network-flow
/// sensing as Gemini: tasks stream to the app, so bytes flowing = working.
/// No Manus CLI exists on the verified machine; that surface is absent.
public struct ManusAdapter: AgentAdapter {

    public let id = "manus"
    public let displayName = "Manus"
    public let transcriptRoot: URL
    public var focusBundleIdentifiers: [String] { ["im.manus.desktop"] }
    public var isActivityBased: Bool { true }
    public var usesNetworkActivity: Bool { true }

    public init(appSupport: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support")) {
        transcriptRoot = appSupport.appendingPathComponent("Manus/IndexedDB")
    }

    public func recentTranscripts(maxAge: TimeInterval, now: Date) -> [SessionFileInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: transcriptRoot,
                                                     includingPropertiesForKeys: nil) else {
            return []
        }
        var found: [SessionFileInfo] = []
        for dir in dirs where dir.lastPathComponent.hasSuffix(".leveldb") {
            guard let newest = Self.newestWrite(in: dir),
                  now.timeIntervalSince(newest) <= maxAge else { continue }
            found.append(SessionFileInfo(sessionID: sessionID(forTranscript: dir),
                                         projectDirName: "Manus tasks",
                                         lastModified: newest,
                                         url: dir))
        }
        return found
    }

    static func newestWrite(in dir: URL) -> Date? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return files.compactMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }.max()
    }

    public func isTranscript(path: String) -> Bool {
        path.hasPrefix(transcriptRoot.path)
    }

    public func canonicalTranscriptURL(forPath path: String) -> URL {
        // Any file inside a .leveldb dir canonicalizes to the dir itself.
        var url = URL(fileURLWithPath: path)
        while url.path.hasPrefix(transcriptRoot.path),
              !url.lastPathComponent.hasSuffix(".leveldb"),
              url.path != transcriptRoot.path {
            url = url.deletingLastPathComponent()
        }
        return url
    }

    public func sessionID(forTranscript url: URL) -> String {
        url.lastPathComponent.replacingOccurrences(of: ".indexeddb.leveldb", with: "")
    }

    public func parseLine(_ line: Data) -> LineParseResult { .malformed }

    public func makeReader(url: URL) -> any SessionReading {
        DirActivityReader(url: url,
                          sessionID: sessionID(forTranscript: url),
                          entrypoint: displayName)
    }

    public func projectDirName(forTranscript url: URL) -> String { "Manus tasks" }

    public func match(processes: [RunningProcess],
                      candidates: [SessionMatchCandidate]) -> [String: Int32] {
        let recent = candidates.sorted { $0.lastModified > $1.lastModified }
        var match: [String: Int32] = [:]
        for (candidate, process) in zip(recent, processes.sorted { $0.pid < $1.pid }) {
            match[candidate.sessionID] = process.pid
        }
        return match
    }

    public func agentPIDs(psComm: String, psArgs: String) -> [Int32] {
        var pids: [Int32] = []
        for rawLine in psComm.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let pid = Int32(line[..<space]) else { continue }
            let command = line[line.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
            if command.hasSuffix("/Manus.app/Contents/MacOS/Manus") {
                pids.append(pid)
            }
        }
        return pids.sorted()
    }

    public func liveNetworkBytes(pid: Int32) -> Int? {
        ProcessNetworkSampler.cumulativeBytes(pid: pid)
    }
}

/// Like FileActivityReader, but for a directory (leveldb): activity is the
/// newest mtime of any file inside.
public final class DirActivityReader: SessionReading {

    public let url: URL
    public let sessionID: String
    public let lastKnownCWD: String? = nil
    public let lastKnownEntrypoint: String?
    public let isSidechain = false
    public let isUnreadable = false
    public let hasPendingToolUses = false
    public let cost = SessionCost()
    public let dailyCosts: [Date: SessionCost] = [:]
    public let usageLimit: UsageLimitSnapshot? = nil

    public private(set) var lastGrowthAt: Date?
    public private(set) var currentTurnStartedAt: Date?
    private let idleCutoff: TimeInterval
    private let now: @Sendable () -> Date

    public var turnPhase: TurnPhase {
        guard let growth = lastGrowthAt else { return .completed }
        return now().timeIntervalSince(growth) < idleCutoff ? .midTurn : .completed
    }

    public init(url: URL, sessionID: String, entrypoint: String?,
                idleCutoff: TimeInterval = 6,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.sessionID = sessionID
        self.lastKnownEntrypoint = entrypoint
        self.idleCutoff = idleCutoff
        self.now = now
    }

    public func refresh() throws {
        guard let newest = ManusAdapter.newestWrite(in: url) else { return }
        if lastGrowthAt == nil || newest > lastGrowthAt! {
            if turnPhase == .completed { currentTurnStartedAt = newest }
            lastGrowthAt = newest
        }
    }
}
