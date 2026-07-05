import Foundation

/// Per-process cumulative network bytes via nettop — the real-time
/// activity signal for cloud-streaming desktop agents whose files don't
/// record completion. nettop has been observed HANGING when launched from
/// a GUI app context, so every invocation gets a hard watchdog; callers
/// must still sample off-actor (see SessionStore's probe loop).
public enum ProcessNetworkSampler {

    public static func cumulativeBytes(pid: Int32) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-p", String(pid), "-x", "-l", "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return parse(output)
    }

    /// Last data row: time, name, bytes_in, bytes_out, …
    public static func parse(_ output: String) -> Int? {
        for line in output.split(separator: "\n").reversed() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4, fields[1].contains("."),
                  let bytesIn = Int(fields[2]), let bytesOut = Int(fields[3]) else { continue }
            return bytesIn + bytesOut
        }
        return nil
    }
}
