import Foundation

/// Source of live agent processes. The real implementation shells out to
/// ps/lsof; tests inject a fake.
public protocol ProcessScanning: Sendable {
    func scanClaudeProcesses() async throws -> [RunningProcess]
}

/// Real scanner: `ps -axo pid=,args=` filtered to claude CLI processes, then
/// one `lsof` call resolving all their cwds.
public struct ShellProcessScanner: ProcessScanning {

    public init() {}

    public func scanClaudeProcesses() async throws -> [RunningProcess] {
        // comm= catches native `claude` binaries even when their path
        // contains spaces; args= catches runtime-hosted installs
        // (`node …/claude`). Union both.
        let commOutput = try await run("/bin/ps", ["-axo", "pid=,comm="])
        let argsOutput = try await run("/bin/ps", ["-axo", "pid=,args="])
        let pids = Array(Set(ProcessOutputParser.claudePIDs(fromPSComm: commOutput))
            .union(ProcessOutputParser.claudePIDs(fromPS: argsOutput))).sorted()
        guard !pids.isEmpty else { return [] }

        let pidList = pids.map(String.init).joined(separator: ",")
        // lsof exits non-zero if any pid vanished between ps and lsof; that's
        // fine — parse whatever it printed.
        let lsofOutput = (try? await run("/usr/sbin/lsof",
                                         ["-a", "-d", "cwd", "-Fn", "-p", pidList])) ?? ""
        let cwds = ProcessOutputParser.cwdsByPID(fromLSOF: lsofOutput)
        return pids.compactMap { pid in
            cwds[pid].map { RunningProcess(pid: pid, cwd: $0) }
        }
    }

    private func run(_ launchPath: String, _ arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Drain stdout BEFORE waiting for exit: ps output easily exceeds
            // the 64KB pipe buffer, and an undrained pipe deadlocks the child.
            let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

/// Polls for claude CLI processes on an interval. On scanner failure it
/// reports degraded mode (transcript-only; Ended detection paused) instead of
/// wiping the session list with an empty result.
public actor ProcessWatcher {

    public struct Update: Equatable, Sendable {
        public let processes: [RunningProcess]
        /// True when the last scan failed and `processes` is stale.
        public let degraded: Bool

        public init(processes: [RunningProcess], degraded: Bool) {
            self.processes = processes
            self.degraded = degraded
        }
    }

    private let scanner: any ProcessScanning
    private let interval: Duration
    private var pollTask: Task<Void, Never>?
    private var handler: (@Sendable (Update) -> Void)?

    public private(set) var latest = Update(processes: [], degraded: false)

    public init(scanner: any ProcessScanning = ShellProcessScanner(),
                interval: Duration = .seconds(5)) {
        self.scanner = scanner
        self.interval = interval
    }

    public func start(onUpdate: @escaping @Sendable (Update) -> Void) {
        handler = onUpdate
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        handler = nil
    }

    /// One scan cycle; exposed for tests to drive without the timer.
    public func pollOnce() async {
        do {
            let processes = try await scanner.scanClaudeProcesses()
            latest = Update(processes: processes, degraded: false)
        } catch {
            latest = Update(processes: latest.processes, degraded: true)
        }
        handler?(latest)
    }
}
