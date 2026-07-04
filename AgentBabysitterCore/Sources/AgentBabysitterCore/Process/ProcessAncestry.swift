import Foundation
import Darwin

/// Walks parent pids so the app can find which terminal application owns a
/// claude CLI process (claude → zsh → login → iTerm2/Terminal/VS Code…).
public enum ProcessAncestry {

    /// Parent chain of `pid` (excluding `pid` itself), ending at launchd
    /// (pid 1). Empty if the process doesn't exist.
    public static func ancestorPIDs(of pid: Int32, maxDepth: Int = 25) -> [Int32] {
        var ancestors: [Int32] = []
        var current = pid
        for _ in 0..<maxDepth {
            guard let parent = parentPID(of: current), parent != current else { break }
            ancestors.append(parent)
            if parent <= 1 { break }
            current = parent
        }
        return ancestors
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              size > 0,
              info.kp_proc.p_pid == pid else {
            return nil
        }
        return info.kp_eproc.e_ppid
    }
}
