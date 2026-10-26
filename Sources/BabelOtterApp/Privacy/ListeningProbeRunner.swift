import BabelOtterKit
import Foundation

/// Asks macOS where Ollama's port is open (#73): `lsof`, read-only and part
/// of macOS, as a child process. No network call is made, so the one
/// networking call site stays the only one (`NFR-P4`).
enum ListeningProbeRunner {

    static let lsof = URL(filePath: "/usr/sbin/lsof")
    static let timeLimit: TimeInterval = 2

    /// Unknown when lsof is missing, fails, or takes too long. `port` is
    /// the model server's in use (#126).
    static func run(port: Int) async -> ListeningExposure {
        await Task.detached { measure(port: port) }.value
    }

    /// The processes listening on `port`; empty when lsof cannot say (#126).
    static func owners(port: Int) async -> Set<Int32> {
        await Task.detached {
            ListeningProbe.owners(output(ListeningProbe.ownerArguments(port: port)) ?? "")
        }.value
    }

    private static func measure(port: Int) -> ListeningExposure {
        guard let text = output(ListeningProbe.arguments(port: port)) else { return .unknown }
        return ListeningProbe.parse(text)
    }

    /// lsof's output, nil when it is missing, fails or takes too long.
    private static func output(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = lsof
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = DispatchTime.now() + timeLimit
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
