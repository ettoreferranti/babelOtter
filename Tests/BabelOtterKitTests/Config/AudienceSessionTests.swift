import Testing

@testable import BabelOtterKit

private final class Memory: AudienceMemory {
    var perApp: [String: String] = [:]
    var last: String?
    func lastChoice(forApp bundleIdentifier: String) -> String? { perApp[bundleIdentifier] }
    func lastChoice() -> String? { last }
    func remember(_ id: String, forApp bundleIdentifier: String?) {
        last = id
        if let bundleIdentifier { perApp[bundleIdentifier] = id }
    }
}

private let mail = SourceApplication(processIdentifier: 1, bundleIdentifier: "com.apple.mail", name: "Mail")
private let teams = SourceApplication(processIdentifier: 2, bundleIdentifier: "com.microsoft.teams2", name: "Microsoft Teams")
private let profiles = AudienceProfile.shippedDefaults

private func session(
    _ action: Action = .translate, in application: SourceApplication? = mail,
    memory: Memory = Memory(), profiles: [AudienceProfile] = profiles
) -> AudienceSession {
    AudienceSession(profiles: profiles, action: action, application: application, memory: memory)
}

@Suite("One popup's audience: where it starts, what each run is told, what a choice does")
struct AudienceSessionTests {

    @Test("this app's last choice comes first")
    func rememberedForApp() {
        let memory = Memory()
        memory.perApp["com.apple.mail"] = "students"
        memory.last = "informal"
        let start = session(memory: memory)
        #expect(start.audience == .students)
        #expect(start.origin == .rememberedForApp)
    }

    @Test("then the last choice anywhere")
    func rememberedAnywhere() {
        let memory = Memory()
        memory.last = "informal"
        let start = session(memory: memory)
        #expect(start.audience == .informal)
        #expect(start.origin == .rememberedAnywhere)
    }

    @Test("then Colleagues")
    func standard() {
        let start = session()
        #expect(start.audience == .colleagues)
        #expect(start.origin == .standard)
    }

    @Test("a remembered id no longer configured is skipped")
    func staleId() {
        let memory = Memory()
        memory.perApp["com.apple.mail"] = "parents"
        memory.last = "administration"
        let start = session(memory: memory)
        #expect(start.audience == .administration)
        #expect(start.origin == .rememberedAnywhere)
    }

    @Test("without Colleagues, the first configured audience; without any, Colleagues")
    func noConfiguredAudiences() {
        #expect(session(profiles: [.students, .informal]).audience == .students)
        #expect(session(profiles: []).audience == .colleagues)
    }

    @Test("an app without a bundle id skips the per-app step")
    func noBundleId() {
        let memory = Memory()
        memory.last = "students"
        let app = SourceApplication(processIdentifier: 3, bundleIdentifier: nil, name: "Tool")
        #expect(session(in: app, memory: memory).origin == .rememberedAnywhere)
    }

    @Test("Translate's first run infers, with the starting audience as fallback")
    func firstTranslateRunInfers() {
        let start = session()
        #expect(start.request == .infer(profiles: profiles, fallback: .colleagues))
        #expect(start.isDetecting)
        #expect(start.note == "detecting...")
    }

    @Test("Correct never infers")
    func correctNeverInfers() {
        let start = session(.correct)
        #expect(start.request == .fixed(.colleagues))
        #expect(!start.isDetecting)
        #expect(start.note == "default")
    }

    @Test("an inferred report is shown as a guess; later runs are fixed and keep it")
    func laterRunsAreFixedAndKeepTheGuess() {
        var current = session()
        current.apply(reported: .students, inferred: true)
        #expect(current.audience == .students)
        #expect(current.origin == .inferred)
        #expect(current.request == .fixed(.students))
        #expect(!current.isDetecting)
        #expect(current.note == "guessed from the text, change if wrong")
    }

    @Test("a fallback report keeps the fallback's origin")
    func fallbackReportKeepsOrigin() {
        let memory = Memory()
        memory.perApp["com.apple.mail"] = "students"
        var current = session(memory: memory)
        current.apply(reported: .students, inferred: false)
        #expect(current.origin == .rememberedForApp)
        #expect(current.note == "last used in Mail")
        #expect(current.request == .fixed(.students))
    }

    @Test("a guess is never remembered")
    func guessNotRemembered() {
        let memory = Memory()
        var current = session(memory: memory)
        current.apply(reported: .students, inferred: true)
        #expect(memory.perApp.isEmpty)
        #expect(memory.last == nil)
    }

    @Test("choosing remembers for this app and overall, and asks for a re-run")
    func chooseRemembers() {
        let memory = Memory()
        var current = session(memory: memory)
        let rerun = current.choose("administration")
        #expect(rerun)
        #expect(current.audience == .administration)
        #expect(current.origin == .chosen)
        #expect(current.note == nil)
        #expect(current.request == .fixed(.administration))
        #expect(memory.perApp == ["com.apple.mail": "administration"])
        #expect(memory.last == "administration")
        #expect(session(in: teams, memory: memory).origin == .rememberedAnywhere)
        #expect(session(in: mail, memory: memory).origin == .rememberedForApp)
    }

    @Test("once reported, choosing the audience shown, or an unknown one, does nothing")
    func chooseNothing() {
        let memory = Memory()
        var current = session(memory: memory)
        current.apply(reported: .colleagues, inferred: false)
        let sameAgain = current.choose("colleagues")
        let unknown = current.choose("parents")
        #expect(!sameAgain)
        #expect(!unknown)
        #expect(memory.last == nil)
        #expect(current.origin == .standard)
    }

    @Test("picking the audience shown while detecting is a pick: kept, remembered, re-run")
    func pickTheShownOneWhileDetecting() {
        let memory = Memory()
        var current = session(memory: memory)
        let rerun = current.choose("colleagues")
        #expect(rerun)
        #expect(current.origin == .chosen)
        #expect(memory.perApp == ["com.apple.mail": "colleagues"])
        current.apply(reported: .students, inferred: true)
        #expect(current.audience == .colleagues)
    }

    @Test("a run that ends without a report stops saying detecting, and the next one infers again")
    func failedRunStopsDetecting() {
        var current = session()
        current.runEnded()
        #expect(current.note == "default")
        #expect(current.request == .infer(profiles: profiles, fallback: .colleagues))
        current.runStarted()
        #expect(current.note == "detecting...")
    }

    @Test("a stale report after a choice does not override it")
    func aStaleReportDoesNotOverrideAChoice() {
        var current = session()
        current.choose("informal")
        current.apply(reported: .students, inferred: true)
        #expect(current.audience == .informal)
        #expect(current.origin == .chosen)
    }

    @Test("the last-anywhere note")
    func anywhereNote() {
        let memory = Memory()
        memory.last = "informal"
        var current = session(memory: memory)
        current.apply(reported: .informal, inferred: false)
        #expect(current.note == "last used")
    }
}
