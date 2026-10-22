import BabelOtterKit
import Foundation

/// Asks macOS where Ollama's port is open (#73): `lsof`, read-only and part
/// of macOS, as a child process. No network call is made, so the one
/// networking call site stays the only one (`NFR-P4`).
enum ListeningProbeRunner {

    static let lsof = URL(filePath: "/usr/sbin/lsof")
    static let timeLimit: TimeInterval = 2

    /// Unknown when lsof is missing, fails, or takes too long.
    static func run() async -> ListeningExposure {
        await Task.detached { measure() }.value
    }

    private static func measure() -> ListeningExposure {
        let process = Process()
        process.executableURL = lsof
        process.arguments = ListeningProbe.arguments()
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unknown
        }
        let deadline = DispatchTime.now() + timeLimit
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal { return .unknown }
        return ListeningProbe.parse(String(decoding: data, as: UTF8.self))
    }
}
