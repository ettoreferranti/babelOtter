# Audience Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate infers the audience from the source text in the same request, the popup marks a guess as a guess and remembers an explicit choice per application, and Correct starts from that memory (#52).

**Architecture:** The kit gains the inference vocabulary (`AudienceRequest`, `AudienceInference.match`), a partial-JSON field reader, an inferring prompt, a translator that reports the audience once per translation as an `.audience` event, and `AudienceSession`, a value type holding the popup's audience rules over an `AudienceMemory` protocol. The app only stores ids in `UserDefaults`, passes `session.request` to the translator, and shows `session.note`.

**Tech Stack:** Swift 6 (CI: Xcode 16.4 / Swift 6.1), SwiftPM, Swift Testing, SwiftUI/AppKit in the app target, muter mutation testing.

**Spec:** `docs/superpowers/specs/2026-10-15-audience-inference-design.md`

## Global Constraints

- `BabelOtterKit` sources are ASCII-only and import no UI framework (architecture tests enforce both).
- In kit code, no comma-separated conditions in `if`/`guard`/`while` and no ternary whose condition ends in an enum member: muter mis-parses both. Nest the conditions instead.
- Every new file under `Sources/BabelOtterKit/` is added to the pass-1 list in `.github/workflows/mutation.yml`, or the mutation job fails.
- Must build on Swift 6.1: no `isolated deinit`, no APIs newer than macOS 14.
- Test suites that consume a stream carry `.timeLimit(.minutes(1))`.
- Only audience ids are stored, never text (`NFR-P3`).
- `Configuration` keeps no new fields: audiences are the existing `profiles`.
- Run tests with `swift test --filter <Suite> 2>&1 | tail -5`; the whole suite with `swift test 2>&1 | grep "Test run with"`.

## Review Focus

1. A stale `.audience` event, from a run cancelled because the user just chose an audience, must not overwrite the choice. Pinned in Task 5 (`aStaleReportDoesNotOverrideAChoice`).
2. A configuration with no audiences at all must still start (on Colleagues) and translate. Pinned in Task 5 (`noConfiguredAudiences`) and Task 3 (`emptyListIsFixed`).
3. Regenerate or a style note after an inference must not re-infer and must keep the "guessed" note. Pinned in Task 5 (`laterRunsAreFixedAndKeepTheGuess`).
4. The model naming the fallback audience explicitly is a real inference, shown as guessed, not as the default. Pinned in Task 1 (`exactId`) and Task 4 (`fallbackNamedExplicitly`).
5. `detected_audience` written after `blocks` (the model ignored the key order) must still be read. Pinned in Task 2 (`afterBlocks`) and Task 4 (`missingFieldFallsBackBeforeFinished` covers the end-of-reply path).

## File map

| File | Task | Responsibility |
|---|---|---|
| `Sources/BabelOtterKit/Config/AudienceInference.swift` (new) | 1 | `AudienceRequest`, `AudienceInference.match` |
| `Sources/BabelOtterKit/Pipeline/PartialField.swift` (new) | 2 | One string field of a reply still arriving |
| `Sources/BabelOtterKit/Pipeline/PartialBlocks.swift` | 2 | Two helpers become internal for reuse |
| `Sources/BabelOtterKit/LLM/PromptBuilder.swift` | 3 | The inferring audience section |
| `Sources/BabelOtterKit/Pipeline/ReplyStream.swift` | 4 | An `onRaw` hook |
| `Sources/BabelOtterKit/Pipeline/Translator.swift` | 4 | `.audience` event, result fields, `audience:` entry point |
| `Sources/BabelOtterApp/PopupModel.swift` | 4, 6 | Compiles with the new event (4); uses the session (6) |
| `Sources/BabelOtterKit/Config/AudienceSession.swift` (new) | 5 | `AudienceOrigin`, `AudienceMemory`, `AudienceSession` |
| `Sources/BabelOtterApp/UserDefaultsAudienceMemory.swift` (new) | 6 | `AudienceMemory` over `UserDefaults` |
| `Sources/BabelOtterApp/PopupView.swift`, `AppDelegate.swift` | 6 | Note, placeholder, passing the application |
| `Tests/BabelOtterKitTests/Integration/AudienceInferenceIntegrationTests.swift` (new) | 7 | Real-model checks, local only |
| `.github/workflows/mutation.yml`, `docs/HANDOFF.md` | 8 | Mutation list, hand-over |

---

### Task 1: The inference vocabulary

**Files:**
- Create: `Sources/BabelOtterKit/Config/AudienceInference.swift`
- Test: `Tests/BabelOtterKitTests/Config/AudienceInferenceTests.swift`

**Interfaces:**
- Consumes: `AudienceProfile` (id, name, register, toneGuidance), `AudienceProfile.shippedDefaults`.
- Produces: `public enum AudienceRequest: Sendable, Equatable { case fixed(AudienceProfile); case infer(profiles: [AudienceProfile], fallback: AudienceProfile) }`; `public enum AudienceInference { public static let unclear: String; public static func match(_ detected: String?, in profiles: [AudienceProfile]) -> AudienceProfile? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

@Suite("The model's detected_audience, matched to a configured audience")
struct AudienceInferenceTests {

    let profiles = AudienceProfile.shippedDefaults

    @Test("an exact id matches, including the fallback's own id")
    func exactId() {
        #expect(AudienceInference.match("students", in: profiles) == .students)
        #expect(AudienceInference.match("colleagues", in: profiles) == .colleagues)
    }

    @Test("case and surrounding space do not matter")
    func caseAndSpace() {
        #expect(AudienceInference.match("  Students \n", in: profiles) == .students)
    }

    @Test("a name matches when no id does")
    func byName() {
        let team = AudienceProfile(id: "team", name: "My Team", register: .informal, toneGuidance: "Short.")
        #expect(AudienceInference.match("my team", in: profiles + [team]) == team)
    }

    @Test("an id wins over another audience's name")
    func idBeforeName() {
        let first = AudienceProfile(id: "x", name: "y", register: .formal, toneGuidance: "")
        let second = AudienceProfile(id: "y", name: "z", register: .formal, toneGuidance: "")
        #expect(AudienceInference.match("y", in: [first, second]) == second)
    }

    @Test("unclear, nothing, empty or unknown means the fallback")
    func noMatch() {
        #expect(AudienceInference.match(AudienceInference.unclear, in: profiles) == nil)
        #expect(AudienceInference.match(nil, in: profiles) == nil)
        #expect(AudienceInference.match("   ", in: profiles) == nil)
        #expect(AudienceInference.match("parents", in: profiles) == nil)
    }

    @Test("the prompt's word for no sign is unclear")
    func unclearWord() {
        #expect(AudienceInference.unclear == "unclear")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter AudienceInferenceTests 2>&1 | tail -5`
Expected: build error, `cannot find 'AudienceInference' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What a translation is told about its audience (#52).
public enum AudienceRequest: Sendable, Equatable {
    /// Write for this audience.
    case fixed(AudienceProfile)
    /// Choose from `profiles` the audience the text addresses and write for
    /// it; `fallback` when the text gives no clear sign.
    case infer(profiles: [AudienceProfile], fallback: AudienceProfile)
}

/// Reads the model's `detected_audience` against the configured audiences.
public enum AudienceInference {

    /// What the prompt asks the model to answer when the text gives no sign.
    public static let unclear = "unclear"

    /// The configured audience the model named: by id first, then by name,
    /// ignoring case and surrounding space. Nil means "use the fallback":
    /// no answer, `unclear`, or a name that is not configured.
    public static func match(_ detected: String?, in profiles: [AudienceProfile]) -> AudienceProfile? {
        guard let detected else { return nil }
        let wanted = detected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if wanted.isEmpty { return nil }
        for profile in profiles where profile.id.lowercased() == wanted {
            return profile
        }
        for profile in profiles where profile.name.lowercased() == wanted {
            return profile
        }
        return nil
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter AudienceInferenceTests 2>&1 | tail -5`
Expected: `Test run with 6 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Config/AudienceInference.swift Tests/BabelOtterKitTests/Config/AudienceInferenceTests.swift
git commit -m "feat(audience): match the model's detected audience to a configured one"
```

---

### Task 2: One string field of a reply still arriving

**Files:**
- Create: `Sources/BabelOtterKit/Pipeline/PartialField.swift`
- Modify: `Sources/BabelOtterKit/Pipeline/PartialBlocks.swift` (`skipWhitespace` and `readString` lose `private`)
- Test: `Tests/BabelOtterKitTests/Pipeline/PartialFieldTests.swift`

**Interfaces:**
- Consumes: `PartialBlocks.skipWhitespace(_:from:) -> Int`, `PartialBlocks.readString(_:from:) -> (text: String, next: Int, closed: Bool)` (made internal here).
- Produces: `public enum PartialField { public static func string(named key: String, in partial: String) -> String? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

@Suite("A string field read from a reply that is still arriving")
struct PartialFieldTests {

    private func read(_ partial: String) -> String? {
        PartialField.string(named: "detected_audience", in: partial)
    }

    @Test("a complete value is read before the rest of the reply arrives")
    func complete() {
        #expect(read(#"{"detected_source": "en", "detected_audience": "students", "blocks": ["Hal"#) == "students")
    }

    @Test("a value still arriving is not read")
    func cutOff() {
        #expect(read(#"{"detected_audience": "stud"#) == nil)
        #expect(read(#"{"detected_audience""#) == nil)
        #expect(read(#"{"detected_audience": "#) == nil)
    }

    @Test("escapes are decoded")
    func escaped() {
        #expect(read(#"{"detected_audience": "a\"b", "#) == "a\"b")
    }

    @Test("an absent field is nil")
    func absent() {
        #expect(read(#"{"blocks": ["x"]}"#) == nil)
    }

    @Test("a field written after the blocks is still read")
    func afterBlocks() {
        #expect(read(#"{"blocks": ["x"], "detected_audience": "colleagues"}"#) == "colleagues")
    }

    @Test("space around the colon is allowed")
    func spacing() {
        #expect(read(#"{"detected_audience" :   "students""#) == "students")
    }

    @Test("a value that is not a string is nil")
    func notAString() {
        #expect(read(#"{"detected_audience": null}"#) == nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PartialFieldTests 2>&1 | tail -5`
Expected: build error, `cannot find 'PartialField' in scope`.

- [ ] **Step 3: Implement**

In `PartialBlocks.swift`, change `private static func skipWhitespace` to `static func skipWhitespace` and `private static func readString` to `static func readString` (no other change). Then create `PartialField.swift`:

```swift
import Foundation

/// One string field of a reply that is still arriving, once its value has
/// fully arrived (#52: `detected_audience`, shown before the translation
/// finishes). Nil while the value is still being written.
///
/// Like `PartialBlocks`, only a preview: the result always comes from
/// `ResponseParser` on the complete reply.
public enum PartialField {

    public static func string(named key: String, in partial: String) -> String? {
        guard let found = partial.range(of: "\"" + key + "\"") else { return nil }
        let scalars = Array(partial[found.upperBound...].unicodeScalars)
        var index = PartialBlocks.skipWhitespace(scalars, from: 0)
        guard index < scalars.count else { return nil }
        guard scalars[index] == ":" else { return nil }
        index = PartialBlocks.skipWhitespace(scalars, from: index + 1)
        guard index < scalars.count else { return nil }
        guard scalars[index] == "\"" else { return nil }
        let read = PartialBlocks.readString(scalars, from: index + 1)
        guard read.closed else { return nil }
        return read.text
    }
}
```

- [ ] **Step 4: Run them to verify they pass, with PartialBlocks still green**

Run: `swift test --filter "PartialFieldTests|PartialBlocksTests" 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Pipeline/PartialField.swift Sources/BabelOtterKit/Pipeline/PartialBlocks.swift Tests/BabelOtterKitTests/Pipeline/PartialFieldTests.swift
git commit -m "feat(audience): read one string field from a reply still arriving"
```

---

### Task 3: The inferring prompt

**Files:**
- Modify: `Sources/BabelOtterKit/LLM/PromptBuilder.swift` (`PromptRequest`, `audience(_:)`)
- Test: `Tests/BabelOtterKitTests/LLM/PromptBuilderTests.swift`

**Interfaces:**
- Consumes: `AudienceInference.unclear` (Task 1).
- Produces: `PromptRequest.inferAudienceFrom: [AudienceProfile]` (init parameter after `profile:`, default `[]`). Non-empty means "infer"; `profile` is then the fallback. Correct ignores it.

Ruling against the spec's wording: the spec says `PromptRequest` carries an `AudienceRequest` "in place of a bare profile". This plan keeps `profile` and adds the list, which says the same thing without touching every existing `PromptRequest(...)` call; Translator (Task 4) maps `AudienceRequest` onto the two fields.

- [ ] **Step 1: Write the failing tests**

In `PromptBuilderTests`, add `inferFrom: [AudienceProfile] = []` to the `request(...)` helper's parameters (after `profile`) and pass `inferAudienceFrom: inferFrom` to `PromptRequest(...)` after `profile: profile`. Then add:

```swift
    @Test("inferring lists every audience with its id and names the fallback")
    func inferringListsAudiences() {
        let prompt = builder.build(request(profile: .colleagues, inferFrom: AudienceProfile.shippedDefaults))
        for profile in AudienceProfile.shippedDefaults {
            #expect(prompt.contains("- \(profile.id): \(profile.name)"))
        }
        #expect(prompt.contains("Decide which of these audiences the text addresses"))
        #expect(prompt.contains(#"put "unclear" and write for "colleagues""#))
        #expect(!prompt.contains("Audience: Colleagues."))
    }

    @Test("an empty list is the fixed audience, unchanged")
    func emptyListIsFixed() {
        let prompt = builder.build(request(profile: .students, inferFrom: []))
        #expect(prompt.contains("Audience: Students."))
        #expect(!prompt.contains("Decide which"))
    }

    @Test("Correct never infers")
    func correctNeverInfers() {
        let prompt = builder.build(request(action: .correct, profile: .students, inferFrom: AudienceProfile.shippedDefaults))
        #expect(!prompt.contains("Decide which"))
        #expect(prompt.contains("addressed to Students"))
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PromptBuilderTests 2>&1 | tail -5`
Expected: build error, `extra argument 'inferAudienceFrom' in call`.

- [ ] **Step 3: Implement**

In `PromptRequest`: add `public let inferAudienceFrom: [AudienceProfile]` after `profile`, the init parameter `inferAudienceFrom: [AudienceProfile] = []` after `profile: AudienceProfile,`, and `self.inferAudienceFrom = inferAudienceFrom`.

In `audience(_:)`, make the first lines inside the `guard request.action == .correct else {` block:

```swift
            if !request.inferAudienceFrom.isEmpty {
                return inferredAudience(request)
            }
```

and add after `audience(_:)`:

```swift
    /// #52: the model picks the audience the text addresses and writes for
    /// it. `request.profile` is the fallback for a text with no clear sign.
    private func inferredAudience(_ request: PromptRequest) -> String {
        var lines = ["Audiences (id: name, form of address, tone):"]
        for profile in request.inferAudienceFrom {
            lines.append(
                #"- \#(profile.id): \#(profile.name), "\#(profile.register.rawValue)". \#(profile.toneGuidance)"#)
        }
        lines.append(
            "Decide which of these audiences the text addresses and write for it. "
                + #"Put its id in "detected_audience". If the text gives no clear sign, put ""#
                + AudienceInference.unclear
                + #"" and write for "\#(request.profile.id)"."#)
        return lines.joined(separator: "\n")
    }
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter PromptBuilderTests 2>&1 | tail -5`
Expected: all pass, the existing ones unchanged.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/LLM/PromptBuilder.swift Tests/BabelOtterKitTests/LLM/PromptBuilderTests.swift
git commit -m "feat(audience): a prompt that asks the model to pick the audience"
```

---

### Task 4: The translator reports the audience

**Files:**
- Modify: `Sources/BabelOtterKit/Pipeline/ReplyStream.swift`, `Sources/BabelOtterKit/Pipeline/Translator.swift`, `Sources/BabelOtterApp/PopupModel.swift` (one `case`)
- Test: `Tests/BabelOtterKitTests/Pipeline/ReplyStreamTests.swift`, `Tests/BabelOtterKitTests/Pipeline/TranslatorTests.swift`

**Interfaces:**
- Consumes: `AudienceRequest`, `AudienceInference.match` (Task 1); `PartialField.string(named:in:)` (Task 2); `PromptRequest(inferAudienceFrom:)` (Task 3).
- Produces:
  - `ReplyStream.collect(..., onRaw: (String) -> Void = { _ in }, onDelta:..., onPartial:...)`; `onRaw` gets the whole reply so far after each piece.
  - `TranslationEvent.audience(AudienceProfile, inferred: Bool)`: exactly once per translation, before `.finished`.
  - `TranslationResult.audience: AudienceProfile`, `TranslationResult.audienceInferred: Bool`.
  - `Translator.translate(_ text: UserText, direction: Direction, audience: AudienceRequest, styleNote: String? = nil) -> LazyStream<TranslationEvent>`; the existing `translate(_:direction:profile:styleNote:)` stays and means `.fixed(profile)`.

- [ ] **Step 1: Write the failing tests**

In `ReplyStreamTests`, add:

```swift
    @Test("onRaw sees the whole reply so far after every piece")
    func onRawSeesTheReplySoFar() async throws {
        var seen: [String] = []
        let raw = try await ReplyStream.collect(
            chat: Scripted(["{\"a\"", ": 1}"]), model: "m", prompt: "p", key: "blocks",
            onRaw: { seen.append($0) }, onPartial: { _ in })
        #expect(seen == ["{\"a\"", "{\"a\": 1}"])
        #expect(raw == "{\"a\": 1}")
    }
```

In `TranslatorTests`, add these helpers below `result(_:)`:

```swift
private func audiences(_ events: [TranslationEvent]) -> [TranslationEvent] {
    events.filter { event in
        guard case .audience = event else { return false }
        return true
    }
}

private func index(of wanted: (TranslationEvent) -> Bool, in events: [TranslationEvent]) -> Int? {
    events.firstIndex(where: wanted)
}

private let inferring = AudienceRequest.infer(profiles: AudienceProfile.shippedDefaults, fallback: .colleagues)
```

and these tests inside the suite:

```swift
    @Test("an inferred audience is reported once, before the result, and carried by it")
    func inferredAudience() async throws {
        let chat = ScriptedChat([["{\"detected_audience\": \"students\", \"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.students, inferred: true)])
        let reported = try #require(index(of: { $0 == .audience(.students, inferred: true) }, in: events))
        #expect(reported < events.count - 1)
        let finished = try #require(result(events))
        #expect(finished.audience == .students)
        #expect(finished.audienceInferred)
        #expect(chat.prompts[0].contains("Decide which of these audiences"))
    }

    @Test("the audience is reported as soon as it arrives, before the text")
    func audienceBeforeText() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"students\", \"blocks\": [\"Hal", "lo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        let reported = try #require(index(of: { $0 == .audience(.students, inferred: true) }, in: events))
        let firstPreview = try #require(index(of: { event in
            guard case .preview = event else { return false }
            return true
        }, in: events))
        #expect(reported < firstPreview)
    }

    @Test("unclear means the fallback, not presented as inferred")
    func unclearFallsBack() async throws {
        let chat = ScriptedChat([["{\"detected_audience\": \"unclear\", \"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        #expect(result(events)?.audienceInferred == false)
    }

    @Test("the model naming the fallback is still an inference")
    func fallbackNamedExplicitly() async throws {
        let chat = ScriptedChat([["{\"detected_audience\": \"colleagues\", \"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: true)])
    }

    @Test("a reply without the field falls back, still before the result")
    func missingFieldFallsBackBeforeFinished() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        let reported = try #require(index(of: { $0 == .audience(.colleagues, inferred: false) }, in: events))
        #expect(reported == events.count - 2)
    }

    @Test("an unparseable reply falls back, before the result")
    func unparseableFallsBack() async throws {
        let chat = ScriptedChat([["Hallo, no JSON"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        #expect(result(events)?.audience == .colleagues)
    }

    @Test("the whole-text retry writes for the reported audience, fixed")
    func retryIsFixed() async throws {
        let chat = ScriptedChat([
            ["{\"detected_audience\": \"students\", \"blocks\": [\"only one\"]}"],
            ["{\"blocks\": [\"Erste Zeile.\\nZweite Zeile.\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), audience: inferring))

        #expect(chat.prompts.count == 2)
        #expect(!chat.prompts[1].contains("Decide which"))
        #expect(chat.prompts[1].contains("Audience: Students."))
        #expect(audiences(events) == [.audience(.students, inferred: true)])
        #expect(result(events)?.audience == .students)
    }

    @Test("a fixed audience is reported at once, as not inferred")
    func fixedIsReportedAtOnce() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), profile: .administration))

        #expect(events.count > 1)
        #expect(events[1] == .audience(.administration, inferred: false))
        #expect(audiences(events).count == 1)
        #expect(!chat.prompts[0].contains("Decide which"))
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "TranslatorTests|ReplyStreamTests" 2>&1 | tail -5`
Expected: build errors (`extra argument 'onRaw'`, `type 'TranslationEvent' has no member 'audience'`).

- [ ] **Step 3: Implement `ReplyStream`**

Add the parameter `onRaw: (String) -> Void = { _ in },` before `onDelta` in `collect`, and call `onRaw(raw)` on the line after `raw += piece`.

- [ ] **Step 4: Implement the translator**

In `Translator.swift`:

1. Add the event, between `started` and `progress`:

```swift
    /// The audience this translation writes for, once known: as soon as the
    /// model's `detected_audience` has arrived when inferring, at once when
    /// fixed. Exactly once per translation, always before `finished` (#52).
    case audience(AudienceProfile, inferred: Bool)
```

2. Add to `TranslationResult`, after `warnings`:

```swift
    /// The audience the text was written for, and whether the model chose it.
    public let audience: AudienceProfile
    public let audienceInferred: Bool
```

3. Replace the public `translate(_:direction:profile:styleNote:)` with these two:

```swift
    public func translate(
        _ text: UserText, direction: Direction, profile: AudienceProfile,
        styleNote: String? = nil
    ) -> LazyStream<TranslationEvent> {
        translate(text, direction: direction, audience: .fixed(profile), styleNote: styleNote)
    }

    /// `.infer` asks the model to choose the audience from the text (#52);
    /// the choice is reported as `.audience` and fixed for the retry.
    public func translate(
        _ text: UserText, direction: Direction, audience: AudienceRequest,
        styleNote: String? = nil
    ) -> LazyStream<TranslationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(
                            text, direction: direction, audience: audience, styleNote: styleNote
                        ) {
                            continuation.yield($0)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
```

4. Add above `private struct Context`:

```swift
    /// The audience one translation settled on, so it is reported once and
    /// the retry and the result use the same one.
    private final class AudienceReport: @unchecked Sendable {
        var profile: AudienceProfile?
        var inferred = false
    }
```

5. In `Context`, replace `let profile: AudienceProfile` with:

```swift
        var audience: AudienceRequest
        let report: AudienceReport
```

and add inside `Context`:

```swift
        /// The audience the prompt writes for: the reported one once known,
        /// else the fixed one or the fallback.
        var writingFor: AudienceProfile {
            if let reported = report.profile { return reported }
            switch audience {
            case .fixed(let profile):
                return profile
            case .infer(_, let fallback):
                return fallback
            }
        }

        /// The audiences to choose from, or none for a fixed audience.
        var choices: [AudienceProfile] {
            guard case .infer(let profiles, _) = audience else { return [] }
            return profiles
        }
```

6. In `run`, change the signature's `profile: AudienceProfile` to `audience: AudienceRequest`, build the context with `audience: audience, report: AudienceReport(),` in place of `profile: profile,`, and replace `emit(.started(direction))` with:

```swift
        emit(.started(direction))
        if case .fixed = audience { settle(nil, context, emit) }
```

In `run`, replace the parse guard with one that settles first:

```swift
        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            settle(nil, context, emit)
            return emit(.finished(unparsed(raw, masked.first, direction, context)))
        }
        settle(response.detectedAudience, context, emit)
```

and change `try await retryWholeText(text, direction, context, emit)` to:

```swift
            var fixed = context
            fixed.audience = .fixed(context.writingFor)
            try await retryWholeText(text, direction, fixed, emit)
```

7. In `generate`, pass the audience into the prompt and read the field as it arrives:

```swift
        let prompt = PromptBuilder().build(PromptRequest(
            action: .translate, source: context.source, target: context.target,
            profile: context.writingFor, inferAudienceFrom: context.choices,
            glossary: context.glossary,
            doNotTranslate: context.terms, styleNote: context.styleNote,
            blocks: blocks.map(\.text)))
        let raw = try await ReplyStream.collect(
            chat: chat, model: context.model, prompt: prompt, key: "blocks",
            onRaw: { reply in
                guard !context.choices.isEmpty else { return }
                guard let detected = PartialField.string(named: "detected_audience", in: reply) else { return }
                settle(detected, context, emit)
            },
            onDelta: { emit(.progress) },
            onPartial: { emit(.preview(UserText(preview($0, blocks, context)))) })
```

8. Add the settling method next to `warnings(_:)`:

```swift
    /// Reports the audience if it has not been yet: the model's answer when
    /// inferring (nil, `unclear` or unknown means the fallback), the fixed
    /// one otherwise.
    private func settle(
        _ detected: String?, _ context: Context, _ emit: (TranslationEvent) -> Void
    ) {
        guard context.report.profile == nil else { return }
        var chosen = context.writingFor
        var inferred = false
        if case .infer(let profiles, _) = context.audience {
            if let matched = AudienceInference.match(detected, in: profiles) {
                chosen = matched
                inferred = true
            }
        }
        context.report.profile = chosen
        context.report.inferred = inferred
        emit(.audience(chosen, inferred: inferred))
    }
```

9. Give every `TranslationResult(...)` in the file (the `.accept` case, `retryWholeText`, both in `unparsed`, `joined`) the two new arguments after `warnings:`:

```swift
audience: context.writingFor, audienceInferred: context.report.inferred
```

10. In `Sources/BabelOtterApp/PopupModel.swift`, `apply(_ event: TranslationEvent)`, add a case so the app still builds (Task 6 replaces it):

```swift
        case .audience:
            break
```

- [ ] **Step 5: Run the translator, stream and prompt tests**

Run: `swift test --filter "TranslatorTests|ReplyStreamTests|PromptBuilderTests" 2>&1 | tail -5`
Expected: all pass, the existing ones unchanged.

- [ ] **Step 6: Run the whole suite and build the app**

Run: `swift test 2>&1 | grep "Test run with"` and `swift build --product BabelOtterApp 2>&1 | tail -1`
Expected: every test passes; `Build complete!`.

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterKit/Pipeline/ReplyStream.swift Sources/BabelOtterKit/Pipeline/Translator.swift Sources/BabelOtterApp/PopupModel.swift Tests/BabelOtterKitTests/Pipeline/ReplyStreamTests.swift Tests/BabelOtterKitTests/Pipeline/TranslatorTests.swift
git commit -m "feat(audience): the translator reports the audience it writes for, inferred or fixed"
```

---

### Task 5: The popup's audience rules, in the kit

**Files:**
- Create: `Sources/BabelOtterKit/Config/AudienceSession.swift`
- Test: `Tests/BabelOtterKitTests/Config/AudienceSessionTests.swift`

**Interfaces:**
- Consumes: `AudienceRequest` (Task 1), `Action`, `SourceApplication` (`bundleIdentifier: String?`, `name: String`).
- Produces:
  - `public enum AudienceOrigin: Sendable, Equatable { case chosen, inferred, rememberedForApp, rememberedAnywhere, standard }`
  - `public protocol AudienceMemory: AnyObject { func lastChoice(forApp bundleIdentifier: String) -> String?; func lastChoice() -> String?; func remember(_ id: String, forApp bundleIdentifier: String?) }`
  - `public struct AudienceSession` with `init(profiles: [AudienceProfile], action: Action, application: SourceApplication?, memory: any AudienceMemory)`, `audience: AudienceProfile`, `origin: AudienceOrigin`, `isDetecting: Bool`, `request: AudienceRequest`, `note: String?`, `mutating func apply(reported: AudienceProfile, inferred: Bool)`, `@discardableResult mutating func choose(_ id: String) -> Bool`.

Ruling against the spec's wording: the spec's note reads "✦ guessed from the text — change if wrong". Kit sources are ASCII-only, so `note` returns `guessed from the text, change if wrong` and the view (Task 6) adds the ✦.

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(current.choose("administration"))
        #expect(current.audience == .administration)
        #expect(current.origin == .chosen)
        #expect(current.note == nil)
        #expect(current.request == .fixed(.administration))
        #expect(memory.perApp == ["com.apple.mail": "administration"])
        #expect(memory.last == "administration")
        #expect(session(in: teams, memory: memory).origin == .rememberedAnywhere)
        #expect(session(in: mail, memory: memory).origin == .rememberedForApp)
    }

    @Test("choosing the audience shown, or an unknown one, does nothing")
    func chooseNothing() {
        let memory = Memory()
        var current = session(memory: memory)
        #expect(!current.choose("colleagues"))
        #expect(!current.choose("parents"))
        #expect(memory.last == nil)
        #expect(current.origin == .standard)
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter AudienceSessionTests 2>&1 | tail -5`
Expected: build error, `cannot find type 'AudienceMemory' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Where the audience shown in the popup came from (#52).
public enum AudienceOrigin: Sendable, Equatable {
    /// Picked in the popup.
    case chosen
    /// The model read it from the text.
    case inferred
    /// Last picked in this application.
    case rememberedForApp
    /// Last picked anywhere.
    case rememberedAnywhere
    /// Nothing remembered: Colleagues.
    case standard
}

/// The audience ids the user picked, per application and overall. Ids only,
/// never text (NFR-P3).
public protocol AudienceMemory: AnyObject {
    func lastChoice(forApp bundleIdentifier: String) -> String?
    func lastChoice() -> String?
    func remember(_ id: String, forApp bundleIdentifier: String?)
}

/// One popup's audience: where it starts, what each run is told, and what
/// picking another one does (#52).
///
/// A value, so the popup's observation sees every change. Translate's first
/// run infers; once a run has reported its audience, or the user has picked
/// one, every later run is fixed, so the label never changes under the user.
public struct AudienceSession {

    public private(set) var audience: AudienceProfile
    public private(set) var origin: AudienceOrigin
    private var settled = false

    private let profiles: [AudienceProfile]
    private let action: Action
    private let application: SourceApplication?
    private let memory: any AudienceMemory

    public init(
        profiles: [AudienceProfile], action: Action, application: SourceApplication?,
        memory: any AudienceMemory
    ) {
        self.profiles = profiles
        self.action = action
        self.application = application
        self.memory = memory
        let start = Self.starting(profiles, application?.bundleIdentifier, memory)
        audience = start.profile
        origin = start.origin
    }

    /// True until Translate's first run reports its audience.
    public var isDetecting: Bool {
        guard action == .translate else { return false }
        return !settled
    }

    /// What the next run is told.
    public var request: AudienceRequest {
        if isDetecting {
            return .infer(profiles: profiles, fallback: audience)
        }
        return .fixed(audience)
    }

    /// The text beside the picker. Nil for an audience the user picked.
    public var note: String? {
        if isDetecting { return "detecting..." }
        switch origin {
        case .chosen:
            return nil
        case .inferred:
            return "guessed from the text, change if wrong"
        case .rememberedForApp:
            return "last used in " + (application?.name ?? "this app")
        case .rememberedAnywhere:
            return "last used"
        case .standard:
            return "default"
        }
    }

    /// Records the audience a run reported. A guess is shown as one and
    /// never remembered; a fallback keeps its own origin. Ignored once the
    /// user has picked: that report came from a run the pick replaced.
    public mutating func apply(reported profile: AudienceProfile, inferred: Bool) {
        if origin == .chosen { return }
        settled = true
        audience = profile
        if inferred { origin = .inferred }
    }

    /// Picks an audience: remembered for this application and overall.
    /// Returns whether the result must be generated again.
    @discardableResult
    public mutating func choose(_ id: String) -> Bool {
        guard let profile = Self.find(id, in: profiles) else { return false }
        if profile.id == audience.id { return false }
        audience = profile
        origin = .chosen
        settled = true
        memory.remember(profile.id, forApp: application?.bundleIdentifier)
        return true
    }

    private static func starting(
        _ profiles: [AudienceProfile], _ bundleIdentifier: String?, _ memory: any AudienceMemory
    ) -> (profile: AudienceProfile, origin: AudienceOrigin) {
        if let bundleIdentifier {
            if let profile = find(memory.lastChoice(forApp: bundleIdentifier), in: profiles) {
                return (profile, .rememberedForApp)
            }
        }
        if let profile = find(memory.lastChoice(), in: profiles) {
            return (profile, .rememberedAnywhere)
        }
        if let profile = find(AudienceProfile.colleagues.id, in: profiles) {
            return (profile, .standard)
        }
        return (profiles.first ?? .colleagues, .standard)
    }

    private static func find(_ id: String?, in profiles: [AudienceProfile]) -> AudienceProfile? {
        guard let id else { return nil }
        for profile in profiles where profile.id == id {
            return profile
        }
        return nil
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter AudienceSessionTests 2>&1 | tail -5`
Expected: `Test run with 15 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Config/AudienceSession.swift Tests/BabelOtterKitTests/Config/AudienceSessionTests.swift
git commit -m "feat(audience): one popup's audience rules, remembered per app, in the kit"
```

---

### Task 6: The popup uses the session

**Files:**
- Create: `Sources/BabelOtterApp/UserDefaultsAudienceMemory.swift`
- Modify: `Sources/BabelOtterApp/PopupModel.swift`, `Sources/BabelOtterApp/PopupView.swift`, `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `AudienceSession`, `AudienceMemory`, `AudienceOrigin` (Task 5); `Translator.translate(_:direction:audience:styleNote:)` and `.audience` (Task 4).
- Produces: `PopupModel.init(action:application:environment:close:reopen:)`; `PopupModel.audienceNote: String?`; `PopupModel.audienceInferred: Bool`.

The app target has no unit tests in this repo; every rule it now uses was proven in Task 5. This task is verified by building, the whole suite, and the manual look in Task 8.

- [ ] **Step 1: The memory**

Create `Sources/BabelOtterApp/UserDefaultsAudienceMemory.swift`:

```swift
import BabelOtterKit
import Foundation

/// `AudienceMemory` over UserDefaults: a dictionary of bundle ID to audience
/// id, and the last pick overall under the key the popup used before #52, so
/// an existing preference carries over. Ids only, never text.
final class UserDefaultsAudienceMemory: AudienceMemory {

    private static let perAppKey = "audienceByApp"
    private static let lastKey = "lastProfileID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastChoice(forApp bundleIdentifier: String) -> String? {
        perApp[bundleIdentifier]
    }

    func lastChoice() -> String? {
        defaults.string(forKey: Self.lastKey)
    }

    func remember(_ id: String, forApp bundleIdentifier: String?) {
        defaults.set(id, forKey: Self.lastKey)
        guard let bundleIdentifier else { return }
        var map = perApp
        map[bundleIdentifier] = id
        defaults.set(map, forKey: Self.perAppKey)
    }

    private var perApp: [String: String] {
        defaults.dictionary(forKey: Self.perAppKey) as? [String: String] ?? [:]
    }
}
```

- [ ] **Step 2: The model**

In `PopupModel.swift`:

1. Replace `private(set) var profileID: String` (and its comment) with:

```swift
    /// Where the audience came from and what each run is told (#52).
    private(set) var audience: AudienceSession
```

2. Change the init to take the application and build the session, replacing `self.profileID = Self.initialProfileID(in: environment.configuration)`:

```swift
    init(
        action: Action, application: SourceApplication?, environment: AppEnvironment,
        close: @escaping @MainActor () -> Void,
        reopen: @escaping @MainActor (PopupModel) -> Void
    ) {
        self.action = action
        self.configuration = environment.configuration
        self.translator = Translator(configuration: environment.configuration, chat: environment.client)
        self.corrector = Corrector(configuration: environment.configuration, chat: environment.client)
        self.close = close
        self.reopen = reopen
        self.audience = AudienceSession(
            profiles: environment.configuration.profiles, action: action,
            application: application, memory: UserDefaultsAudienceMemory())
    }
```

3. Delete `lastProfileKey` and `initialProfileID(in:)`, and replace `selectProfile(_:)` and the `profile` property with:

```swift
    var profileID: String { audience.audience.id }

    /// The text beside the picker, and whether it marks a guess.
    var audienceNote: String? { audience.note }
    var audienceInferred: Bool { audience.origin == .inferred }

    /// Picking another audience re-runs the result already on screen, since
    /// the whole point is to see it in the other register.
    func selectProfile(_ id: String) {
        guard !isDismissed else { return }
        if audience.choose(id) { regenerate() }
    }
```

4. In `run(_:)`, replace the `translator.translate(...)` call with:

```swift
            translator.translate(
                snapshot.text, direction: direction, audience: audience.request,
                styleNote: styleNote),
```

5. In `apply(_ event: TranslationEvent)`, replace the `case .audience: break` from Task 4 with:

```swift
        case .audience(let profile, let inferred):
            audience.apply(reported: profile, inferred: inferred)
```

6. In `runCorrection()`, replace `profile: profile` with `profile: audience.audience`.

- [ ] **Step 3: The view**

In `PopupView.swift`'s `controls`, after the `Picker(...)` modifiers (`.fixedSize()`), add:

```swift
            if let note = model.audienceNote {
                Text(model.audienceInferred ? "\u{2726} \(note)" : note)
                    .foregroundStyle(.secondary)
                    .help("Where this audience came from")
            }
```

and change the text field's placeholder from `"Instruction, e.g. shorter"` to `"Style note, e.g. shorter, more encouraging"`.

- [ ] **Step 4: The two places a popup is created**

In `AppDelegate.swift`, `startAction(_:)`: `PopupModel(action: action, application: source, environment: environment, ...)`. In `showAccessibilityNeeded(for:)`: `PopupModel(action: action, application: nil, environment: environment, ...)`. Keep every other argument as it is.

- [ ] **Step 5: Build the app and run the whole suite**

Run: `swift build --product BabelOtterApp 2>&1 | grep -E "error|warning: .*Popup|Build complete"` and `swift test 2>&1 | grep "Test run with"`
Expected: `Build complete!` with no errors; every test passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterApp/UserDefaultsAudienceMemory.swift Sources/BabelOtterApp/PopupModel.swift Sources/BabelOtterApp/PopupView.swift Sources/BabelOtterApp/AppDelegate.swift
git commit -m "feat(popup): the audience is inferred, marked as a guess, and remembered per app"
```

---

### Task 7: The guessing, against the real model

**Files:**
- Create: `Tests/BabelOtterKitTests/Integration/AudienceInferenceIntegrationTests.swift`

**Interfaces:**
- Consumes: `Translator.translate(_:direction:audience:)`, `.audience` (Task 4); `IntegrationGate`, `OllamaClient(endpoint:transport:)`, `URLSessionTransport(timeout:)` (existing).

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing

@testable import BabelOtterKit

/// The prompt and the configured model must agree on who a text is for (#52).
/// Local only, like every test that talks to Ollama:
///
///     BABELOTTER_INTEGRATION=1 swift test --filter AudienceInferenceIntegrationTests
///
/// The model is not deterministic, so each text runs three times and must
/// give the expected answer at least twice. A case that flaps is a finding
/// about the prompt, not noise to retry away. All texts are synthetic.
@Suite(
    "Integration: the model infers who a text is for",
    .enabled(if: IntegrationGate.isEnabled), .timeLimit(.minutes(10)))
struct AudienceInferenceIntegrationTests {

    private let runs = 3

    /// The first `.audience` event; the stream is dropped there, which
    /// cancels the rest of the generation.
    private func reported(_ text: String) async throws -> (AudienceProfile, Bool)? {
        let client = OllamaClient(endpoint: .loopback, transport: URLSessionTransport(timeout: 120))
        let translator = Translator(configuration: .default, chat: client)
        let stream = translator.translate(
            UserText(text),
            direction: Direction(source: LanguageConfig.english.code, target: LanguageConfig.swissGerman.code),
            audience: .infer(profiles: AudienceProfile.shippedDefaults, fallback: .colleagues))
        for try await event in stream {
            if case .audience(let profile, let inferred) = event { return (profile, inferred) }
        }
        return nil
    }

    private func hits(_ text: String, _ expected: (AudienceProfile, Bool)) async throws -> Int {
        var count = 0
        for _ in 0..<runs {
            let answer = try await reported(text)
            if let answer {
                if answer.0 == expected.0 {
                    if answer.1 == expected.1 { count += 1 }
                }
            }
        }
        return count
    }

    @Test("an email to students is for Students")
    func students() async throws {
        let text = """
            Dear students,

            the exam for the module Statistics 1 takes place on 12 January in room TB 610. \
            Please bring your student ID and a calculator. Good luck with your preparation!
            """
        #expect(try await hits(text, (.students, true)) >= 2)
    }

    @Test("a message to a colleague is for Colleagues")
    func colleagues() async throws {
        let text = """
            Hi Anna, I merged the PR for the parser fix and CI is green. \
            Could you rebase your branch on main before the stand-up tomorrow?
            """
        #expect(try await hits(text, (.colleagues, true)) >= 2)
    }

    @Test("a neutral sentence gives no sign, so the fallback")
    func neutral() async throws {
        let text = "The meeting room on the third floor is closed on Friday."
        #expect(try await hits(text, (.colleagues, false)) >= 2)
    }
}
```

- [ ] **Step 2: Check it is skipped by default**

Run: `swift test --filter AudienceInferenceIntegrationTests 2>&1 | tail -3`
Expected: the suite is skipped (no daemon needed), the run passes.

- [ ] **Step 3: Run it against the real model**

Run: `BABELOTTER_INTEGRATION=1 swift test --filter AudienceInferenceIntegrationTests 2>&1 | tail -8`
Expected: 3 tests pass. If one fails, do not loosen the threshold: record the answers the model gave in the ledger and adjust the prompt wording in Task 3's `inferredAudience` (with its tests), then re-run.

- [ ] **Step 4: Commit**

```bash
git add Tests/BabelOtterKitTests/Integration/AudienceInferenceIntegrationTests.swift
git commit -m "test(audience): the model infers students, colleagues and no sign, locally"
```

---

### Task 8: Mutation list, hand-over, manual look

**Files:**
- Modify: `.github/workflows/mutation.yml` (pass-1 list), `docs/HANDOFF.md`

- [ ] **Step 1: Add the three new kit files to pass 1**

In `.github/workflows/mutation.yml`, add these lines to the pass-1 file list, each in alphabetical position among its neighbours (`Config/` entries, then `Pipeline/` entries):

```
          Sources/BabelOtterKit/Config/AudienceInference.swift
          Sources/BabelOtterKit/Config/AudienceSession.swift
          Sources/BabelOtterKit/Pipeline/PartialField.swift
```

- [ ] **Step 2: Verify the list covers every kit file**

Run: `for f in $(find Sources/BabelOtterKit -name '*.swift'); do grep -qF "$f" .github/workflows/mutation.yml || echo "MISSING $f"; done`
Expected: no output.

- [ ] **Step 3: Hand-over**

Add at the top of `docs/HANDOFF.md`, below the intro line, a section:

```markdown
## Update 2026-10-15: the audience is inferred from the text (#52)

Translate asks the model to pick the audience the text addresses, in the same request, and shows it beside the picker as "✦ guessed from the text, change if wrong"; with no clear sign it uses the audience last picked in this app, then the last pick anywhere, then Colleagues, labelled as such. Picking an audience re-runs and is remembered for that app (`UserDefaults`, ids only). Correct never infers. The rules live in `BabelOtterKit/Config/AudienceSession.swift`. Spec: `docs/superpowers/specs/2026-10-15-audience-inference-design.md`.

Local model check: `BABELOTTER_INTEGRATION=1 swift test --filter AudienceInferenceIntegrationTests`.

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| A1 | Translate an English email starting "Dear students" | Beside the picker, "detecting..." then "✦ guessed from the text, change if wrong", with Students selected |
| A2 | Pick Colleagues in the picker | The translation runs again in the du register; the note disappears |
```

- [ ] **Step 4: Full suite, app build, run the app**

Run: `swift test 2>&1 | grep "Test run with"`, then `Tools/make-app.sh --run`
Expected: every test passes; lingoSwen starts.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/mutation.yml docs/HANDOFF.md
git commit -m "chore(audience): mutation list and hand-over for #52"
```
