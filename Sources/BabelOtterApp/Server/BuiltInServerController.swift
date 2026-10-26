import BabelOtterKit
import Darwin
import Foundation

/// Runs the Ollama bundled in the app (#126). Every decision is
/// `BuiltInServerPolicy`'s; this carries out its effects: start the
/// process, watch it, stop it.
///
/// A child process, not a network call: `NetworkingCallSiteTests` keeps
/// the one networking file the only one (`NFR-P4`). The server binds to
/// 127.0.0.1 because its environment says so (`BuiltInServerLaunch`).
@MainActor
final class BuiltInServerController {

    /// Told of every state change.
    var onChange: ((BuiltInServerState) -> Void)?

    let files: BuiltInServerFiles
    private let launch: BuiltInServerLaunch
    private var policy = BuiltInServerPolicy()
    private var process: Process?
    /// Counts launches, so the exit of an earlier process, reported late,
    /// is never taken for the current one's.
    private var generation = 0
    private var watch: Task<Void, Never>?

    /// How often a starting server is asked whether it answers.
    private static let probeInterval = Duration.milliseconds(500)
    /// SIGTERM, then this long, then SIGKILL.
    private static let stopGrace: TimeInterval = 3

    var state: BuiltInServerState { policy.state }

    init(supportDirectory: URL, resources: URL) {
        files = BuiltInServerFiles(supportDirectory: supportDirectory)
        launch = BuiltInServerLaunch(
            resources: resources, files: files, inherited: ProcessInfo.processInfo.environment)
    }

    /// At launch, on switching to Built-in, and for Restart.
    func start() {
        apply(policy.start())
    }

    /// On switching to the user's own Ollama.
    func stop() {
        apply(policy.stop())
    }

    /// At quit: the server must not outlive lingoSwen. Blocks for at most
    /// the grace period, since the app is about to exit.
    func stopAndWait() {
        guard policy.stop() == .terminate else { return }
        watch?.cancel()
        guard let process else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(Self.stopGrace)
        while process.isRunning {
            if Date() > deadline {
                kill(process.processIdentifier, SIGKILL)
                break
            }
            usleep(50_000)
        }
        removePidFile()
    }

    private func apply(_ effect: BuiltInServerEffect) {
        switch effect {
        case .none:
            break
        case .launch:
            run()
        case .terminate:
            terminate()
        }
        onChange?(policy.state)
    }

    private func run() {
        let path = launch.executable.path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: path) else {
            policy.launchFailed(BuiltInServerPolicy.missingBinary)
            return
        }
        terminateLeftover(bundled: path)
        let log: FileHandle
        do {
            try FileManager.default.createDirectory(at: files.models, withIntermediateDirectories: true)
            // Emptied at each start.
            try Data().write(to: files.log)
            log = try FileHandle(forWritingTo: files.log)
        } catch {
            policy.launchFailed("its folder could not be prepared: \(error.localizedDescription)")
            return
        }
        let process = Process()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.environment = launch.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        generation += 1
        let current = generation
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            Task { @MainActor in self?.exited(generation: current, status: status) }
        }
        do {
            try process.run()
        } catch {
            try? log.close()
            policy.launchFailed("it could not be started: \(error.localizedDescription)")
            return
        }
        try? log.close()
        self.process = process
        try? Data("\(process.processIdentifier)\n".utf8).write(to: files.pidFile)
        watchUntilReachable(generation: current)
    }

    /// Asks the server whether it answers until it does, or until this
    /// process is no longer the current one.
    private func watchUntilReachable(generation current: Int) {
        watch?.cancel()
        let client = OllamaClient.loopback(.builtIn, timeout: 2)
        watch = Task { [weak self] in
            while !Task.isCancelled {
                if case .reachable = await client.probe() {
                    guard let self, current == self.generation else { return }
                    if self.policy.state == .starting {
                        self.policy.reachable()
                        self.onChange?(self.policy.state)
                    }
                    return
                }
                try? await Task.sleep(for: Self.probeInterval)
            }
        }
    }

    private func exited(generation exited: Int, status: Int32) {
        guard exited == generation else { return }
        watch?.cancel()
        process = nil
        removePidFile()
        let log = (try? String(contentsOfFile: files.log.path(percentEncoded: false), encoding: .utf8)) ?? ""
        let effect = policy.exited(
            status: status, lastLogLine: BuiltInServerPolicy.lastLine(of: log), at: Date())
        apply(effect)
    }

    private func terminate() {
        watch?.cancel()
        guard let process else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(Self.stopGrace))
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// A server left running by a lingoSwen that crashed: stopped first,
    /// but only when that pid is still our bundled binary.
    private func terminateLeftover(bundled: String) {
        let recorded = try? String(contentsOfFile: files.pidFile.path(percentEncoded: false), encoding: .utf8)
        let leftover = BuiltInServerPolicy.leftover(
            pidFile: recorded, bundledExecutable: bundled, executableOf: Self.executablePath)
        guard let pid = leftover else { return }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(Self.stopGrace)
        while kill(pid, 0) == 0 {
            if Date() > deadline {
                kill(pid, SIGKILL)
                break
            }
            usleep(50_000)
        }
    }

    private func removePidFile() {
        try? FileManager.default.removeItem(at: files.pidFile)
    }

    /// The executable a pid runs, as macOS reports it; nil for no process.
    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
