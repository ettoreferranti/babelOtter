import Testing

@testable import BabelOtterKit

@Suite("Scratchpad policy: what Run, Continue, Stop and Copy allow (#84)")
struct ScratchpadPolicyTests {

    private let text = ScratchpadSettings(action: .translate, source: "Hello there")

    private func policy(
        _ status: ScratchpadStatus, current: ScratchpadSettings? = nil, ran: ScratchpadSettings? = nil,
        server: String? = nil
    ) -> ScratchpadPolicy {
        ScratchpadPolicy(status: status, current: current ?? text, ran: ran, serverProblem: server)
    }

    @Test("Run needs text, no run in progress and a ready server")
    func run() {
        #expect(policy(.idle).canRun)
        #expect(policy(.finished, ran: text).canRun)
        #expect(!policy(.running(chunk: 0, of: 1)).canRun)
        #expect(!policy(.idle, current: ScratchpadSettings(action: .translate, source: " \n\t ")).canRun)
        #expect(!policy(.idle, current: ScratchpadSettings(action: .translate, source: "")).canRun)
        #expect(!policy(.idle, server: "Starting the built-in server").canRun)
    }

    @Test("the server's problem is the bar's line")
    func serverProblem() {
        #expect(policy(.idle, server: "Starting").problem == "Starting")
        #expect(policy(.idle).problem == nil)
    }

    @Test("Explain is capped at 6,000 characters; the other actions are not")
    func explainCap() {
        #expect(ScratchpadPolicy.explainLimit == 6_000)
        let atLimit = String(repeating: "a", count: 6_000)
        let over = atLimit + "a"
        #expect(policy(.idle, current: ScratchpadSettings(action: .explain, source: atLimit)).canRun)
        let tooLong = policy(.idle, current: ScratchpadSettings(action: .explain, source: over))
        #expect(!tooLong.canRun)
        #expect(tooLong.problem?.contains("6,000") == true)
        #expect(policy(.idle, current: ScratchpadSettings(action: .translate, source: over)).canRun)
        #expect(policy(.idle, current: ScratchpadSettings(action: .translate, source: over)).problem == nil)
    }

    @Test("Stop only while running")
    func stop() {
        #expect(policy(.running(chunk: 1, of: 3)).canStop)
        #expect(!policy(.idle).canStop)
        #expect(!policy(.finished).canStop)
        #expect(!policy(.interrupted(done: 1, of: 3, reason: nil)).canStop)
        #expect(policy(.running(chunk: 0, of: 1)).isRunning)
        #expect(!policy(.finished).isRunning)
    }

    @Test("Copy takes a whole result only")
    func copy() {
        #expect(policy(.finished, ran: text).canCopy)
        #expect(!policy(.idle).canCopy)
        #expect(!policy(.running(chunk: 0, of: 2)).canCopy)
        #expect(!policy(.interrupted(done: 1, of: 2, reason: nil), ran: text).canCopy)
    }

    @Test("Run becomes Continue after an interruption, while nothing changed")
    func continues() {
        let stopped = policy(.interrupted(done: 1, of: 3, reason: nil), ran: text)
        #expect(stopped.continues)
        #expect(stopped.runTitle == "Continue")
        #expect(stopped.canRun)
    }

    @Test("Continue is Run again once anything changed, or when nothing was done")
    func runAgain() {
        var edited = text
        edited.styleNote = "shorter"
        #expect(!policy(.interrupted(done: 1, of: 3, reason: nil), current: edited, ran: text).continues)
        #expect(!policy(.interrupted(done: 0, of: 3, reason: nil), ran: text).continues)
        #expect(!policy(.interrupted(done: 3, of: 3, reason: nil), ran: text).continues)
        #expect(!policy(.finished, ran: text).continues)
        #expect(policy(.finished, ran: text).runTitle == "Run")
        #expect(!policy(.idle).continues)
    }

    @Test("a result is out of date once anything it depends on changed", arguments: [
        { (s: inout ScratchpadSettings) in s.action = .correct },
        { (s: inout ScratchpadSettings) in s.source = "Hello again" },
        { (s: inout ScratchpadSettings) in s.target = LanguageCode("fr") },
        { (s: inout ScratchpadSettings) in s.swapped = Direction(source: LanguageCode("de"), target: LanguageCode("en")) },
        { (s: inout ScratchpadSettings) in s.profileID = "students" },
        { (s: inout ScratchpadSettings) in s.styleNote = "shorter" },
        { (s: inout ScratchpadSettings) in s.language = LanguageCode("en") },
    ] as [@Sendable (inout ScratchpadSettings) -> Void])
    func outOfDate(_ change: @Sendable (inout ScratchpadSettings) -> Void) {
        var changed = text
        change(&changed)
        #expect(policy(.finished, current: changed, ran: text).isOutOfDate)
        #expect(policy(.interrupted(done: 1, of: 2, reason: nil), current: changed, ran: text).isOutOfDate)
    }

    @Test("no result, or an unchanged one, is never out of date")
    func upToDate() {
        #expect(!policy(.finished, ran: text).isOutOfDate)
        var changed = text
        changed.source = "Other"
        #expect(!policy(.idle, current: changed, ran: text).isOutOfDate)
        #expect(!policy(.running(chunk: 0, of: 1), current: changed, ran: text).isOutOfDate)
        #expect(!policy(.interrupted(done: 0, of: 2, reason: nil), current: changed, ran: text).isOutOfDate)
    }

    @Test("the progress line")
    func progress() {
        #expect(policy(.running(chunk: 1, of: 4)).progress == "Part 2 of 4\u{2026}")
        #expect(policy(.running(chunk: 0, of: 1)).progress == "Working\u{2026}")
        #expect(policy(.interrupted(done: 2, of: 4, reason: nil)).progress == "Stopped after 2 of 4 parts.")
        #expect(policy(.interrupted(done: 0, of: 1, reason: nil)).progress == "Stopped.")
        #expect(policy(.interrupted(done: 1, of: 4, reason: "Timed out.")).progress == "Timed out.")
        #expect(policy(.idle).progress == nil)
        #expect(policy(.finished).progress == nil)
    }
}
