import Foundation
import Testing

@testable import BabelOtterKit

private let support = URL(filePath: "/Users/u/Library/Application Support/ch.lingoswen", directoryHint: .isDirectory)
private let resources = URL(filePath: "/Applications/lingoSwen.app/Contents/Resources", directoryHint: .isDirectory)

@Suite("Built-in server: files and launch (#126)")
struct BuiltInServerLaunchTests {

    @Test("its files live in lingoSwen's own folder, never ~/.ollama")
    func files() {
        let files = BuiltInServerFiles(supportDirectory: support)
        #expect(files.models.path(percentEncoded: false) == support.path(percentEncoded: false) + "ollama/models/")
        #expect(files.pidFile.path(percentEncoded: false) == support.path(percentEncoded: false) + "ollama/server.pid")
        #expect(files.log.path(percentEncoded: false) == support.path(percentEncoded: false) + "ollama/server.log")
    }

    @Test("the bundled binary serves on 47434, loopback only, with its own models and no cloud")
    func launch() {
        let files = BuiltInServerFiles(supportDirectory: support)
        let launch = BuiltInServerLaunch(
            resources: resources, files: files,
            inherited: ["HOME": "/Users/u", "PATH": "/usr/bin:/bin"])
        #expect(launch.executable.path(percentEncoded: false) == "/Applications/lingoSwen.app/Contents/Resources/ollama/ollama")
        #expect(launch.arguments == ["serve"])
        #expect(launch.environment == [
            "HOME": "/Users/u",
            "PATH": "/usr/bin:/bin",
            "OLLAMA_HOST": "127.0.0.1:47434",
            "OLLAMA_MODELS": files.models.path(percentEncoded: false),
            "OLLAMA_KEEP_ALIVE": "30m",
            "OLLAMA_NO_CLOUD": "1",
        ])
    }

    @Test("nothing else is inherited: the user's own OLLAMA_ settings never reach it")
    func nothingElseInherited() {
        let launch = BuiltInServerLaunch(
            resources: resources, files: BuiltInServerFiles(supportDirectory: support),
            inherited: [
                "OLLAMA_HOST": "0.0.0.0:11434", "OLLAMA_DEBUG": "1", "OLLAMA_MODELS": "/elsewhere",
                "OLLAMA_KEEP_ALIVE": "-1", "DYLD_INSERT_LIBRARIES": "/x.dylib",
            ])
        #expect(launch.environment["OLLAMA_HOST"] == "127.0.0.1:47434")
        #expect(launch.environment["OLLAMA_DEBUG"] == nil)
        #expect(launch.environment["OLLAMA_KEEP_ALIVE"] == "30m")
        #expect(launch.environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(launch.environment["HOME"] == nil)
        #expect(launch.environment.count == 4)
    }

    @Test("the built-in model is the default model")
    func model() {
        #expect(BuiltInServer.model == "mistral-small3.2:24b")
        #expect(BuiltInServer.modelDisplayName == "Mistral Small 3.2")
    }
}

@Suite("Built-in server: start, stop and restart (#126)")
struct BuiltInServerPolicyTests {

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("start launches once, and is running when it answers")
    func startRuns() {
        var policy = BuiltInServerPolicy()
        #expect(policy.state == .stopped)
        #expect(policy.start() == .launch)
        #expect(policy.state == .starting)
        #expect(policy.start() == .none)
        policy.reachable()
        #expect(policy.state == .running)
        #expect(policy.start() == .none)
    }

    @Test("answering while stopped changes nothing")
    func reachableWhileStopped() {
        var policy = BuiltInServerPolicy()
        policy.reachable()
        #expect(policy.state == .stopped)
    }

    @Test("stop terminates a running or starting server, and its exit is no crash")
    func stopIsNoCrash() {
        var policy = BuiltInServerPolicy()
        _ = policy.start()
        #expect(policy.stop() == .terminate)
        #expect(policy.state == .stopped)
        #expect(policy.exited(status: 15, lastLogLine: nil, at: start) == .none)
        #expect(policy.state == .stopped)
        _ = policy.start()
        policy.reachable()
        #expect(policy.stop() == .terminate)
    }

    @Test("stopping a stopped or failed server does nothing, and leaves it stopped")
    func stopWhenStopped() {
        var policy = BuiltInServerPolicy()
        #expect(policy.stop() == .none)
        _ = policy.start()
        _ = policy.exited(status: 1, lastLogLine: "listen tcp 127.0.0.1:47434: bind: address already in use", at: start)
        #expect(policy.stop() == .none)
        #expect(policy.state == .stopped)
    }

    @Test("an unexpected exit restarts once; a second within a minute leaves it failed")
    func restartOnce() {
        var policy = BuiltInServerPolicy()
        _ = policy.start()
        policy.reachable()
        #expect(policy.exited(status: 2, lastLogLine: nil, at: start) == .launch)
        #expect(policy.state == .starting)
        #expect(policy.exited(status: 2, lastLogLine: "panic: boom", at: start.addingTimeInterval(59)) == .none)
        #expect(policy.state == .failed("it exited with status 2. Last log line: panic: boom"))
    }

    @Test("crashes more than a minute apart restart each time")
    func restartAfterWindow() {
        var policy = BuiltInServerPolicy()
        _ = policy.start()
        #expect(policy.exited(status: 2, lastLogLine: nil, at: start) == .launch)
        #expect(policy.exited(status: 2, lastLogLine: nil, at: start.addingTimeInterval(60)) == .launch)
        #expect(policy.exited(status: 2, lastLogLine: nil, at: start.addingTimeInterval(130)) == .launch)
        #expect(policy.state == .starting)
    }

    @Test("Restart after a failure starts afresh, with a new restart allowance")
    func restartRemedy() {
        var policy = BuiltInServerPolicy()
        _ = policy.start()
        _ = policy.exited(status: 2, lastLogLine: nil, at: start)
        _ = policy.exited(status: 2, lastLogLine: nil, at: start.addingTimeInterval(1))
        #expect(policy.state == .failed("it exited with status 2."))
        #expect(policy.start() == .launch)
        #expect(policy.exited(status: 2, lastLogLine: nil, at: start.addingTimeInterval(2)) == .launch)
    }

    @Test("a taken port fails at once, without a restart")
    func portTaken() {
        var policy = BuiltInServerPolicy()
        _ = policy.start()
        let line = "Error: listen tcp 127.0.0.1:47434: bind: Address already in use"
        #expect(policy.exited(status: 1, lastLogLine: line, at: start) == .none)
        #expect(policy.state == .failed("Port 47434 is in use by another program."))
        #expect(policy.state.status == "The built-in server stopped: Port 47434 is in use by another program.")
    }

    @Test("a long log line is cut, and a blank one is left out")
    func reasonExcerpt() {
        let long = String(repeating: "x", count: 200)
        let reason = BuiltInServerPolicy.reason(status: 3, lastLogLine: long)
        #expect(reason == "it exited with status 3. Last log line: " + String(repeating: "x", count: 160) + "\u{2026}")
        #expect(BuiltInServerPolicy.reason(status: 3, lastLogLine: "  ") == "it exited with status 3.")
        #expect(BuiltInServerPolicy.reason(status: 3, lastLogLine: String(repeating: "y", count: 160)).hasSuffix("y"))
    }

    @Test("each state has its status line")
    func statuses() {
        #expect(BuiltInServerState.stopped.status == "The built-in server isn't running.")
        #expect(BuiltInServerState.starting.status == "Starting the built-in server\u{2026}")
        #expect(BuiltInServerState.running.status == "Built-in server running")
    }

    @Test("the last non-empty log line is found")
    func lastLine() {
        #expect(BuiltInServerPolicy.lastLine(of: "a\nb\n\n  \n") == "b")
        #expect(BuiltInServerPolicy.lastLine(of: "") == nil)
        #expect(BuiltInServerPolicy.lastLine(of: "only") == "only")
    }

    @Test("a left-over pid is terminated only when it is still our binary")
    func leftover() {
        let ours = "/Applications/lingoSwen.app/Contents/Resources/ollama/ollama"
        let lookup: (Int32) -> String? = { pid in
            switch pid {
            case 4242: return ours
            case 5151: return "/usr/bin/other"
            default: return nil
            }
        }
        #expect(BuiltInServerPolicy.leftover(pidFile: "4242\n", bundledExecutable: ours, executableOf: lookup) == 4242)
        #expect(BuiltInServerPolicy.leftover(pidFile: "5151", bundledExecutable: ours, executableOf: lookup) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: "6161", bundledExecutable: ours, executableOf: lookup) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: nil, bundledExecutable: ours, executableOf: lookup) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: "abc", bundledExecutable: ours, executableOf: lookup) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: "1", bundledExecutable: ours, executableOf: { _ in ours }) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: "0", bundledExecutable: ours, executableOf: { _ in ours }) == nil)
        #expect(BuiltInServerPolicy.leftover(pidFile: "2", bundledExecutable: ours, executableOf: { _ in ours }) == 2)
    }
}

@Suite("Built-in server: disk space for the download (#126)")
struct DiskSpacePolicyTests {

    @Test("20 GB free is enough; less is refused with both amounts")
    func refusal() {
        #expect(DiskSpacePolicy.refusal(availableBytes: 20_000_000_000) == nil)
        #expect(DiskSpacePolicy.refusal(availableBytes: 500_000_000_000) == nil)
        #expect(DiskSpacePolicy.refusal(availableBytes: 19_999_999_999) == "Mistral Small 3.2 needs about 20.0 GB free, and this Mac has 19.9 GB. Free some space, then try again.")
        #expect(DiskSpacePolicy.refusal(availableBytes: 12_340_000_000) == "Mistral Small 3.2 needs about 20.0 GB free, and this Mac has 12.3 GB. Free some space, then try again.")
    }

    @Test("gigabytes are decimal, cut to one place")
    func gigabytes() {
        #expect(DiskSpacePolicy.gigabytes(0) == "0.0 GB")
        #expect(DiskSpacePolicy.gigabytes(-5) == "0.0 GB")
        #expect(DiskSpacePolicy.gigabytes(99_999_999) == "0.0 GB")
        #expect(DiskSpacePolicy.gigabytes(100_000_000) == "0.1 GB")
        #expect(DiskSpacePolicy.gigabytes(15_190_000_000) == "15.1 GB")
        #expect(DiskSpacePolicy.gigabytes(1_000_000_000_000) == "1000.0 GB")
    }
}
