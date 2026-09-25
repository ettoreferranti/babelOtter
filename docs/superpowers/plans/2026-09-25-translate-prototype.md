# Translate Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu bar app you can use every day: select text anywhere, press
Control-Option-T, watch a translation stream into a popup near the cursor, then
Replace, Copy or Dismiss.

**Architecture:** One new pure orchestrator in `BabelOtterKit` (`Translator`)
chains the pipeline that already exists -- direction, structure, masking,
prompt, stream, parse, block-count retry, post-processing, reassembly -- behind
a single call that yields preview and result events. Everything AppKit lives in
`Sources/BabelOtterApp`: a Carbon hotkey, a capture service over the existing
tier ladder, a non-activating `NSPanel` hosting a SwiftUI view, and clipboard
replacement through the existing `ClipboardReplacement`. A shell script wraps
the executable in a signed `.app` so the Accessibility grant survives rebuilds.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, AppKit, SwiftUI (macOS 14
`@Observable`), Carbon `RegisterEventHotKey`, Swift Testing. Zero third-party
dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md` (M1b row of
section 10, cut down to the Translate path), with `docs/architecture.md`
section 7 as measured reality.

## Global Constraints

- **Zero dependencies.** Nothing may be added to `Package.swift` dependencies (NFR-P6, enforced by `DependencyAllowlistTests`).
- **One networking call site.** `NetworkingCallSiteTests` scans *every* file under `Sources/`, the app included. No new file may contain `URLSession`, `URLRequest`, `socket(`, `connect(`, `send(`, `recv(` or `(contentsOf:`. Talk to Ollama only through `OllamaClient`. Watch for accidental matches: use `+=` rather than `append(contentsOf:)`, and avoid method names ending in `send(` / `connect(`.
- **Kit sources are ASCII-only** (`AsciiSourceTests`). Non-ASCII characters in `Sources/BabelOtterKit` are written as escapes: `"\u{27E6}"`, `"\u{00DF}"`. App sources are exempt.
- **The kit imports no UI framework** (`NoUIImportsTests`). AppKit, SwiftUI and Carbon stay in `Sources/BabelOtterApp`.
- **Every new kit file goes in the mutation list** in `.github/workflows/mutation.yml` (the `PASS1` block), or the mutation job fails loudly.
- **Avoid the muter traps in kit code:** no `while a < b, predicate` comma-conjunction conditions; no ternary whose condition ends in an enum member (`x == .foo ? a : b`). Prefer `if`/`else`.
- **User text is `UserText` in the kit** and is never logged, printed or written to disk by either target.
- **Rigour by layer.** Kit tasks are TDD. App tasks are verified by building the `.app` and using it; their checks are listed as manual steps.
- **Default hotkey:** Control-Option-T. Registered through Carbon, so no Input Monitoring permission (FR-UI-01).
- **Default model:** `Configuration.defaultModel` (`mistral-small3.2:24b`), overridable per action in `config.json`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/BabelOtterKit/Capture/ClipboardPolicy.swift` (modify) | `ClipboardReplacement` waits for the paste to land before restoring |
| `Sources/BabelOtterKit/Pipeline/PartialTranslateBlocks.swift` (create) | Reads the `blocks` array out of an incomplete JSON reply, for the live preview |
| `Sources/BabelOtterKit/Pipeline/Translator.swift` (create) | `Direction`, `ChatStreaming`, `TranslationEvent`, `TranslationResult`, `TranslationError`, `Translator` |
| `Tests/BabelOtterKitTests/Pipeline/PartialTranslateBlocksTests.swift` (create) | |
| `Tests/BabelOtterKitTests/Pipeline/TranslatorTests.swift` (create) | |
| `Package.swift` (modify) | Declare `BabelOtterApp` as an executable product so it can be built by name |
| `Tools/app/Info.plist` (create) | Bundle metadata; `LSUIElement` so there is no Dock icon |
| `Tools/make-app.sh` (create) | Build, assemble `build/babelOtter.app`, sign |
| `Sources/BabelOtterApp/main.swift` (rewrite) | `NSApplication` bootstrap |
| `Sources/BabelOtterApp/AppDelegate.swift` (create) | Menu bar item, configuration, Accessibility prompt, Ollama health, hotkey wiring |
| `Sources/BabelOtterApp/AppEnvironment.swift` (create) | Loads configuration from Application Support, builds the `OllamaClient` |
| `Sources/BabelOtterApp/HotKey.swift` (create) | Carbon global hotkey |
| `Sources/BabelOtterApp/SelectionCapturer.swift` (create) | Frontmost app, Accessibility tiers, then clipboard |
| `Sources/BabelOtterApp/PopupPanel.swift` (create) | Non-activating `NSPanel`, placement near the cursor |
| `Sources/BabelOtterApp/PopupModel.swift` (create) | State machine for one invocation: capture, direction, stream, replace |
| `Sources/BabelOtterApp/PopupView.swift` (create) | SwiftUI content |
| `.github/workflows/mutation.yml` (modify) | Add the two new kit files to `PASS1` |
| `.gitignore` (modify) | Ignore `build/` |

---

### Task 1: Replacement waits for the paste before restoring

The kit's `ClipboardReplacement` restores the user's clipboard in a `defer`
immediately after posting Command-V. The target application reads the
pasteboard asynchronously, so an immediate restore can make it paste the
*old* clipboard. `Tools/clipboard-probe.swift:304` waited 0.8 s for exactly this
reason. The wait is injected so the kit stays free of sleeps.

**Files:**
- Modify: `Sources/BabelOtterKit/Capture/ClipboardPolicy.swift` (`ClipboardReplacement`)
- Test: `Tests/BabelOtterKitTests/Capture/ClipboardPolicyTests.swift` (`ClipboardReplacementTests`)

**Interfaces:**
- Produces: `ClipboardReplacement.init(pasteboard: any PasteboardAccess, keystrokes: any KeystrokeSending, settle: @escaping @Sendable () -> Void = {})`. `settle` runs after `paste()` and before the restore.

- [ ] **Step 1: Write the failing test** -- add to `ClipboardReplacementTests`:

```swift
    /// The target reads the pasteboard after Command-V is delivered, not when
    /// it is posted. Restoring first pastes the user's old clipboard.
    @Test("the paste is given time to land before the clipboard is restored")
    func settlesBeforeRestoring() {
        let pasteboard = FakePasteboard(movements: [], arriving: nil)
        let keystrokes = FakeKeystrokes()
        let seen = SettleRecorder()
        let outcome = ClipboardReplacement(
            pasteboard: pasteboard, keystrokes: keystrokes,
            settle: {
                seen.record(pastes: keystrokes.pastes, operations: pasteboard.operations)
            }
        ).replace(with: "die Uebersetzung", activateSource: { true })

        #expect(outcome == .pasted)
        #expect(seen.calls == 1)
        #expect(seen.pastesAtSettle == 1, "settle must run after Command-V")
        #expect(!seen.operationsAtSettle.contains(.restore), "settle must run before the restore")
        #expect(pasteboard.operations.last == .restore)
    }

    @Test("nothing settles when nothing was pasted")
    func noSettleWithoutPaste() {
        let seen = SettleRecorder()
        _ = ClipboardReplacement(
            pasteboard: FakePasteboard(movements: [], arriving: nil),
            keystrokes: FakeKeystrokes(),
            settle: { seen.record(pastes: 0, operations: []) }
        ).replace(with: "text", activateSource: { false })
        #expect(seen.calls == 0)
    }
```

and, next to the other fakes at the top of the file:

```swift
private final class SettleRecorder: @unchecked Sendable {
    private(set) var calls = 0
    private(set) var pastesAtSettle = 0
    private(set) var operationsAtSettle: [FakePasteboard.Operation] = []
    func record(pastes: Int, operations: [FakePasteboard.Operation]) {
        calls += 1
        pastesAtSettle = pastes
        operationsAtSettle = operations
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ClipboardReplacementTests`
Expected: compile failure, `extra argument 'settle' in call`.

- [ ] **Step 3: Implement** -- in `ClipboardReplacement`:

```swift
    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let settle: @Sendable () -> Void

    /// `settle` runs between Command-V and the restore. The target application
    /// reads the pasteboard when it *handles* the keystroke, not when it is
    /// posted, so restoring immediately can paste the user's old clipboard.
    /// The probe waited 0.8s; the app passes a sleep. A closure keeps the kit
    /// free of timing.
    public init(
        pasteboard: any PasteboardAccess,
        keystrokes: any KeystrokeSending,
        settle: @escaping @Sendable () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.settle = settle
    }
```

and in `replace`, after `keystrokes.paste()`:

```swift
        pasteboard.write(text, concealed: true)
        keystrokes.paste()
        settle()
        return .pasted
```

The `defer { pasteboard.restore(saved) }` already runs after the `return`
expression, so the order is paste, settle, restore.

- [ ] **Step 4: Verify the guard by breaking it.** Move `settle()` to after a manual `pasteboard.restore(saved)` temporarily; `settlesBeforeRestoring` must fail. Put it back.

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ClipboardReplacementTests`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterKit/Capture/ClipboardPolicy.swift Tests/BabelOtterKitTests/Capture/ClipboardPolicyTests.swift
git commit -m "fix: let the paste land before the clipboard is restored"
```

---

### Task 2: A preview from a reply that is still arriving

A 24B model takes seconds to finish one JSON object, and nothing in it parses
until the closing brace. This reads what has arrived: every finished string in
`blocks`, plus the one still being written. It is only ever a preview; the
result always comes from `ResponseParser` on the complete reply.

**Files:**
- Create: `Sources/BabelOtterKit/Pipeline/PartialTranslateBlocks.swift`
- Test: `Tests/BabelOtterKitTests/Pipeline/PartialTranslateBlocksTests.swift`
- Modify: `.github/workflows/mutation.yml` (add the file to `PASS1`)

**Interfaces:**
- Produces: `public enum PartialTranslateBlocks { public static func extract(from partial: String) -> [String] }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

@Suite("A translate reply read while it is still arriving")
struct PartialTranslateBlocksTests {

    @Test("nothing before the blocks key has arrived", arguments: [
        "", "{", "{\"detected_source\": \"de\", ", "{\"blocks\"", "{\"blocks\": ", "{\"blocks\": [",
    ])
    func nothingYet(_ partial: String) {
        #expect(PartialTranslateBlocks.extract(from: partial) == [])
    }

    @Test("finished blocks and the one being written")
    func finishedAndInProgress() {
        let partial = "{\"detected_source\": \"de\", \"blocks\": [\"Hallo\", \"Wel"
        #expect(PartialTranslateBlocks.extract(from: partial) == ["Hallo", "Wel"])
    }

    @Test("a block whose opening quote just arrived is an empty block")
    func openingQuoteOnly() {
        #expect(PartialTranslateBlocks.extract(from: "{\"blocks\": [\"a\", \"") == ["a", ""])
    }

    @Test("a complete reply reads the same as the parser would")
    func complete() {
        let reply = "{\"blocks\": [\"one\", \"two\"], \"detected_audience\": \"colleagues\"}"
        #expect(PartialTranslateBlocks.extract(from: reply) == ["one", "two"])
    }

    @Test("a code fence before the object does not matter")
    func codeFence() {
        #expect(PartialTranslateBlocks.extract(from: "```json\n{\"blocks\": [\"x\"") == ["x"])
    }

    @Test("escapes are decoded")
    func escapes() {
        let partial = #"{"blocks": ["say \"hi\"\nnow\\then\ttab"]}"#
        #expect(PartialTranslateBlocks.extract(from: partial) == ["say \"hi\"\nnow\\then\ttab"])
    }

    @Test("a unicode escape is decoded, including a surrogate pair")
    func unicodeEscapes() {
        #expect(PartialTranslateBlocks.extract(from: #"{"blocks": ["café"]}"#) == ["caf\u{00E9}"])
        #expect(PartialTranslateBlocks.extract(from: #"{"blocks": ["🦦"]}"#) == ["\u{1F9A6}"])
    }

    @Test("an escape cut off mid-way is left out rather than guessed", arguments: [
        (#"{"blocks": ["ab\"#, "ab"),
        (#"{"blocks": ["ab\u00"#, "ab"),
        (#"{"blocks": ["ab\ud83e"#, "ab"),
        (#"{"blocks": ["ab\ud83e\ud"#, "ab"),
    ])
    func truncatedEscape(_ partial: String, _ expected: String) {
        #expect(PartialTranslateBlocks.extract(from: partial) == [expected])
    }

    @Test("sentinels pass through untouched")
    func sentinels() {
        let partial = "{\"blocks\": [\"\u{27E6}DNT0\u{27E7} is"
        #expect(PartialTranslateBlocks.extract(from: partial) == ["\u{27E6}DNT0\u{27E7} is"])
    }

    @Test("something that is not a string ends the read")
    func unexpectedToken() {
        #expect(PartialTranslateBlocks.extract(from: "{\"blocks\": [\"a\", 3, \"b\"]}") == ["a"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PartialTranslateBlocksTests`
Expected: compile failure, `cannot find 'PartialTranslateBlocks' in scope`.

- [ ] **Step 3: Implement** `Sources/BabelOtterKit/Pipeline/PartialTranslateBlocks.swift`:

```swift
import Foundation

/// The `blocks` of a translate reply that is still arriving.
///
/// The model streams one JSON object, and nothing in it parses until the
/// closing brace. On a 24B local model that is seconds of a frozen popup. This
/// reads what has arrived: every finished string in the array, plus the one
/// still being written.
///
/// Only ever a preview. The result always comes from `ResponseParser` on the
/// complete reply, so a misreading here costs a flicker, never a wrong paste.
public enum PartialTranslateBlocks {

    public static func extract(from partial: String) -> [String] {
        guard let key = partial.range(of: "\"blocks\"") else { return [] }
        let scalars = Array(partial[key.upperBound...].unicodeScalars)

        var index = skipWhitespace(scalars, from: 0)
        guard index < scalars.count, scalars[index] == ":" else { return [] }
        index = skipWhitespace(scalars, from: index + 1)
        guard index < scalars.count, scalars[index] == "[" else { return [] }
        index += 1

        var blocks: [String] = []
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                let read = readString(scalars, from: index + 1)
                blocks.append(read.text)
                guard read.closed else { break }
                index = read.next
            } else if scalar == "," || scalar.properties.isWhitespace {
                index += 1
            } else {
                // `]`, or anything that is not a string: the array is over,
                // or is not the shape a preview can use.
                break
            }
        }
        return blocks
    }

    private static func skipWhitespace(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start
        while index < scalars.count {
            guard scalars[index].properties.isWhitespace else { break }
            index += 1
        }
        return index
    }

    /// A JSON string body, starting just after its opening quote.
    private static func readString(
        _ scalars: [Unicode.Scalar], from start: Int
    ) -> (text: String, next: Int, closed: Bool) {
        var text = String.UnicodeScalarView()
        var index = start
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                return (String(text), index + 1, true)
            }
            if scalar != "\\" {
                text.append(scalar)
                index += 1
                continue
            }
            // An escape that has not fully arrived is left out, not guessed.
            guard index + 1 < scalars.count else { break }
            let code = scalars[index + 1]
            if code == "u" {
                guard let decoded = unicodeEscape(scalars, at: index + 2) else { break }
                text.append(decoded.scalar)
                index = decoded.next
            } else {
                text.append(simpleEscape(code))
                index += 2
            }
        }
        return (String(text), index, false)
    }

    private static func simpleEscape(_ code: Unicode.Scalar) -> Unicode.Scalar {
        switch code {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        default: return code
        }
    }

    private static let replacement: Unicode.Scalar = "\u{FFFD}"

    /// `\uXXXX`, including a surrogate pair written as two escapes. `nil`
    /// while the escape is still incomplete.
    private static func unicodeEscape(
        _ scalars: [Unicode.Scalar], at start: Int
    ) -> (scalar: Unicode.Scalar, next: Int)? {
        guard let high = hex4(scalars, at: start) else { return nil }
        guard (0xD800...0xDBFF).contains(high) else {
            return (Unicode.Scalar(high) ?? replacement, start + 4)
        }
        // A high surrogate means nothing without its low half.
        guard start + 5 < scalars.count else { return nil }
        guard scalars[start + 4] == "\\", scalars[start + 5] == "u" else {
            return (replacement, start + 4)
        }
        guard let low = hex4(scalars, at: start + 6) else { return nil }
        let combined = 0x10000 + ((high - 0xD800) << 10) + (low &- 0xDC00)
        return (Unicode.Scalar(combined) ?? replacement, start + 10)
    }

    private static func hex4(_ scalars: [Unicode.Scalar], at start: Int) -> UInt32? {
        guard start + 4 <= scalars.count else { return nil }
        var value: UInt32 = 0
        for scalar in scalars[start..<start + 4] {
            guard let digit = UInt32(String(scalar), radix: 16) else { return nil }
            value = value * 16 + digit
        }
        return value
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PartialTranslateBlocksTests`
Expected: all pass.

- [ ] **Step 5: Add to the mutation list.** In `.github/workflows/mutation.yml`, add `Sources/BabelOtterKit/Pipeline/PartialTranslateBlocks.swift` to the `PASS1` block. Run `swift test` (the ASCII and networking guards scan the new file).

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterKit/Pipeline Tests/BabelOtterKitTests/Pipeline .github/workflows/mutation.yml
git commit -m "feat: read a translate reply's blocks while it is still arriving"
```

---

### Task 3: The Translator -- one call from selected text to finished translation

**Files:**
- Create: `Sources/BabelOtterKit/Pipeline/Translator.swift`
- Test: `Tests/BabelOtterKitTests/Pipeline/TranslatorTests.swift`
- Modify: `.github/workflows/mutation.yml` (add the file to `PASS1`)

**Interfaces:**
- Consumes: `PartialTranslateBlocks.extract(from:)` (Task 2); existing `StructureExtractor`, `TokenProtector`, `PromptBuilder`, `ResponseParser`, `BlockCountPolicy`, `PostProcessor`, `LanguageDetector`, `TargetLanguageResolver`, `OllamaClient.chat(model:messages:)`, internal `LazyStream.init(_:)`.
- Produces:

```swift
public struct Direction: Sendable, Equatable {
    public let source: LanguageCode
    public let target: LanguageCode
    public init(source: LanguageCode, target: LanguageCode)
    public var swapped: Direction
}
public protocol ChatStreaming: Sendable {
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent>
}
extension OllamaClient: ChatStreaming {}
public enum TranslationEvent: Sendable, Equatable {
    case started(Direction)
    case preview(UserText)
    case finished(TranslationResult)
}
public struct TranslationResult: Sendable, Equatable {
    public let text: UserText
    public let direction: Direction
    public let warnings: [String]
}
public enum TranslationError: Error, Equatable {
    case directionUnknown(candidates: [LanguageCode])
    case languageNotConfigured(LanguageCode)
    case emptyResponse
}
public struct Translator: Sendable {
    public init(configuration: Configuration, chat: any ChatStreaming,
                recognizer: any LanguageRecognizing = NaturalLanguageRecognizer())
    public func direction(for text: UserText) -> Result<Direction, TranslationError>
    public func direction(into target: LanguageCode) -> Direction?
    public func translate(_ text: UserText, direction: Direction,
                          profile: AudienceProfile) -> LazyStream<TranslationEvent>
}
```

**Design notes:**
- `translate` returns a `LazyStream`, so building the value transmits nothing (NFR-P1, the same reason `OllamaClient.chat` is lazy).
- Block-count mismatch on the first reply: retry **once** with the whole text as a single block (`BlockCountDecision.retryWholeText`), expecting one block back. That reply carries its own line breaks, so it is used as-is. A second mismatch degrades: the received blocks joined by `"\n"`, with a warning.
- An unparseable reply (`ParseOutcome.degraded`) is shown as it came, with a warning (`NFR-REL-1`). Locale rules are still applied, so an eszett never reaches a de-CH result.
- The preview runs each partial block through `PostProcessor.finish`, so sentinels and the eszett never flash on screen.

- [ ] **Step 1: Write the failing tests** -- `Tests/BabelOtterKitTests/Pipeline/TranslatorTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

/// Replies scripted per call, recording what was asked.
private final class ScriptedChat: ChatStreaming, @unchecked Sendable {
    private var replies: [[String]]
    private(set) var prompts: [String] = []
    private(set) var models: [String] = []

    init(_ replies: [[String]]) { self.replies = replies }

    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        LazyStream { [self] in
            models.append(model)
            prompts.append(messages.last?.content ?? "")
            let reply = replies.isEmpty ? [] : replies.removeFirst()
            return AsyncThrowingStream { continuation in
                for piece in reply { continuation.yield(.delta(piece)) }
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }
}

private let open = "\u{27E6}"
private let close = "\u{27E7}"
private let german = LanguageConfig.swissGerman.code
private let english = LanguageConfig.english.code

private func collect(_ stream: LazyStream<TranslationEvent>) async throws -> [TranslationEvent] {
    var events: [TranslationEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func result(_ events: [TranslationEvent]) -> TranslationResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

@Suite("The translator, from selected text to finished translation")
struct TranslatorTests {

    private func translator(
        _ chat: ScriptedChat, configure: (inout Configuration) -> Void = { _ in }
    ) -> Translator {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Translator(configuration: configuration, chat: chat)
    }

    @Test("a German list becomes an English list with its terms and markers intact")
    func germanListToEnglish() async throws {
        let chat = ScriptedChat([[
            "{\"blocks\": [\"The street", " is big\", \"\(open)DNT0\(close) is a school\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("- Die Strasse ist gross\n- Otterbach ist eine Schule"),
            direction: Direction(source: german, target: english), profile: .colleagues))

        #expect(events.first == .started(Direction(source: german, target: english)))
        let finished = try #require(result(events))
        #expect(finished.text == UserText("- The street is big\n- Otterbach is a school"))
        #expect(finished.warnings.isEmpty)
        #expect(chat.prompts.count == 1)
        #expect(chat.prompts[0].contains("exactly 2 block"))
        #expect(!chat.prompts[0].contains("Otterbach ist"), "the protected term must be masked")
    }

    @Test("the preview grows as the reply arrives, and is post-processed")
    func previewIsPostProcessed() async throws {
        let chat = ScriptedChat([[
            "{\"blocks\": [\"Die Stra", "\u{00DF}e ist gro", "\u{00DF}\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("The street is big"),
            direction: Direction(source: english, target: german), profile: .colleagues))

        let previews = events.compactMap { event -> String? in
            guard case .preview(let text) = event else { return nil }
            return text.value
        }
        #expect(previews.count >= 2)
        #expect(previews.allSatisfy { !$0.contains("\u{00DF}") }, "FR-TRN-05 holds in the preview too")
        #expect(result(events)?.text == UserText("Die Strasse ist gross"))
    }

    @Test("a wrong block count retries once with the whole text")
    func retriesWholeText() async throws {
        let chat = ScriptedChat([
            ["{\"blocks\": [\"only one\"]}"],
            ["{\"blocks\": [\"Erste Zeile.\\nZweite Zeile.\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        #expect(chat.prompts.count == 2)
        #expect(chat.prompts[1].contains("exactly 1 block"))
        let finished = try #require(result(events))
        #expect(finished.text == UserText("Erste Zeile.\nZweite Zeile."))
        #expect(finished.warnings.isEmpty)
    }

    @Test("a second wrong count degrades with a warning instead of retrying again")
    func degradesAfterOneRetry() async throws {
        let chat = ScriptedChat([
            ["{\"blocks\": [\"one\"]}"],
            ["{\"blocks\": [\"eins\", \"zwei\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        #expect(chat.prompts.count == 2, "never more than one retry")
        let finished = try #require(result(events))
        #expect(finished.text == UserText("eins\nzwei"))
        #expect(!finished.warnings.isEmpty)
    }

    @Test("an unparseable reply is shown as it came, with the locale rules applied")
    func unparseableReply() async throws {
        let chat = ScriptedChat([["Die Stra\u{00DF}e ist gro\u{00DF}."]])
        let events = try await collect(translator(chat).translate(
            UserText("The street is big."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        let finished = try #require(result(events))
        #expect(finished.text == UserText("Die Strasse ist gross."))
        #expect(!finished.warnings.isEmpty)
    }

    @Test("a mangled sentinel becomes a warning")
    func mangledSentinel() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"The school is good\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Otterbach ist gut"),
            direction: Direction(source: german, target: english), profile: .colleagues))
        #expect(result(events)?.warnings.contains { $0.contains("Otterbach") } == true)
    }

    @Test("an empty reply is an error, not an empty translation")
    func emptyReply() async {
        let chat = ScriptedChat([["  "]])
        await #expect(throws: TranslationError.emptyResponse) {
            _ = try await collect(translator(chat).translate(
                UserText("Hello there"),
                direction: Direction(source: english, target: german), profile: .colleagues))
        }
    }

    @Test("a language that is not configured is refused before anything is sent")
    func unconfiguredLanguage() async {
        let chat = ScriptedChat([])
        let french = LanguageCode("fr")
        await #expect(throws: TranslationError.languageNotConfigured(french)) {
            _ = try await collect(translator(chat).translate(
                UserText("Bonjour"),
                direction: Direction(source: french, target: english), profile: .colleagues))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("the configured translate model is the one asked")
    func usesConfiguredModel() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = try await collect(translator(chat) { $0.models[.translate] = "tiny:1b" }.translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(chat.models == ["tiny:1b"])
    }

    @Test("building a translation sends nothing until it is iterated")
    func lazy() {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = translator(chat).translate(
            UserText("secret"),
            direction: Direction(source: english, target: german), profile: .colleagues)
        #expect(chat.prompts.isEmpty, "NFR-P1: constructing must not transmit")
    }

    @Test("a long German selection resolves to German into English")
    func directionForGerman() {
        let text = UserText(
            "Der Ausschuss hat beschlossen, die Entscheidung bis zur naechsten Sitzung zu "
                + "verschieben, weil die Zahlen noch nicht vorliegen.")
        #expect(translator(ScriptedChat([])).direction(for: text)
            == .success(Direction(source: german, target: english)))
    }

    @Test("a selection too short to judge asks, offering every enabled language")
    func directionTooShort() {
        #expect(translator(ScriptedChat([])).direction(for: UserText("Hallo"))
            == .failure(.directionUnknown(candidates: [english, german])))
    }

    @Test("choosing a target picks the other enabled language as the source")
    func directionInto() {
        let subject = translator(ScriptedChat([]))
        #expect(subject.direction(into: english) == Direction(source: german, target: english))
        #expect(subject.direction(into: german) == Direction(source: english, target: german))
        #expect(subject.direction(into: LanguageCode("fr")) == nil)
    }

    @Test("swapping reverses the direction")
    func swap() {
        #expect(Direction(source: german, target: english).swapped
            == Direction(source: english, target: german))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TranslatorTests`
Expected: compile failure, `cannot find type 'ChatStreaming' in scope`.

- [ ] **Step 3: Implement** `Sources/BabelOtterKit/Pipeline/Translator.swift`:

```swift
import Foundation

/// Which way a translation goes.
public struct Direction: Sendable, Equatable {
    public let source: LanguageCode
    public let target: LanguageCode

    public init(source: LanguageCode, target: LanguageCode) {
        self.source = source
        self.target = target
    }

    public var swapped: Direction { Direction(source: target, target: source) }
}

/// The one thing the translator needs from Ollama, so tests can script it.
public protocol ChatStreaming: Sendable {
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent>
}

extension OllamaClient: ChatStreaming {}

public enum TranslationEvent: Sendable, Equatable {
    case started(Direction)
    /// The translation so far, post-processed. Never the result.
    case preview(UserText)
    case finished(TranslationResult)
}

public struct TranslationResult: Sendable, Equatable {
    public let text: UserText
    public let direction: Direction
    /// Things the user should know before pasting: lost structure, a
    /// protected term that did not come back.
    public let warnings: [String]
}

public enum TranslationError: Error, Equatable {
    /// Detection could not decide; ask, offering these.
    case directionUnknown(candidates: [LanguageCode])
    case languageNotConfigured(LanguageCode)
    case emptyResponse
}

/// Selected text in, translation out: the whole core pipeline behind one call.
///
/// Every step already exists and is proven on its own; this owns only the
/// order and the one retry. `PipelineTests` drives the same order by hand.
public struct Translator: Sendable {

    private let configuration: Configuration
    private let chat: any ChatStreaming
    private let detector: LanguageDetector

    public init(
        configuration: Configuration,
        chat: any ChatStreaming,
        recognizer: any LanguageRecognizing = NaturalLanguageRecognizer()
    ) {
        self.configuration = configuration
        self.chat = chat
        self.detector = LanguageDetector(configuration: configuration, recognizer: recognizer)
    }

    public func direction(for text: UserText) -> Result<Direction, TranslationError> {
        let resolution = TargetLanguageResolver(configuration: configuration)
            .resolve(detector.detect(text.value))
        switch resolution {
        case .resolved(let source, let target):
            return .success(Direction(source: source, target: target))
        case .notEnabled(let code):
            return .failure(.languageNotConfigured(code))
        case .ambiguousPairing(let candidates):
            if candidates.isEmpty {
                return .failure(.directionUnknown(candidates: enabledCodes))
            }
            return .failure(.directionUnknown(candidates: candidates))
        case .needsUserChoice:
            return .failure(.directionUnknown(candidates: enabledCodes))
        }
    }

    /// The direction for a target the user picked: from the first other
    /// enabled language.
    public func direction(into target: LanguageCode) -> Direction? {
        guard configuration.language(for: target) != nil else { return nil }
        guard let source = configuration.enabledLanguages.first(where: { $0.code != target })
        else { return nil }
        return Direction(source: source.code, target: target)
    }

    /// Lazy for the same reason `OllamaClient.chat` is: building the value
    /// must not transmit the user's text (NFR-P1).
    public func translate(
        _ text: UserText, direction: Direction, profile: AudienceProfile
    ) -> LazyStream<TranslationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(text, direction: direction, profile: profile) {
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

    // MARK: - The pipeline

    private var enabledCodes: [LanguageCode] { configuration.enabledLanguages.map(\.code) }

    private struct Context {
        let source: LanguageConfig
        let target: LanguageConfig
        let profile: AudienceProfile
        let glossary: [GlossaryEntry]
        let terms: [String]
        let model: String
        let processor: PostProcessor
    }

    private func run(
        _ text: UserText, direction: Direction, profile: AudienceProfile,
        emit: (TranslationEvent) -> Void
    ) async throws {
        guard let source = configuration.language(for: direction.source) else {
            throw TranslationError.languageNotConfigured(direction.source)
        }
        guard let target = configuration.language(for: direction.target) else {
            throw TranslationError.languageNotConfigured(direction.target)
        }
        let context = Context(
            source: source, target: target, profile: profile,
            glossary: configuration.glossary.entries(
                for: LanguagePair(source: direction.source, target: direction.target)),
            terms: configuration.doNotTranslate,
            model: configuration.models[.translate] ?? Configuration.defaultModel,
            processor: PostProcessor(target: target))
        emit(.started(direction))

        let extracted = StructureExtractor.extract(text.value)
        let masked = extracted.blocks.map { TokenProtector.mask($0, terms: context.terms) }
        let raw = try await generate(masked, context, emit)

        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            return emit(.finished(unparsed(raw, direction, context)))
        }
        let decision = BlockCountPolicy().decide(
            expected: extracted.skeleton.blockCount, received: response.blocks.count, attempt: 0)
        switch decision {
        case .accept:
            let finished = zip(response.blocks, masked).map {
                context.processor.finish($0, protected: $1)
            }
            let output = try StructureExtractor.reapply(
                finished.map(\.text), to: extracted.skeleton)
            emit(.finished(TranslationResult(
                text: UserText(output), direction: direction,
                warnings: warnings(finished.flatMap(\.problems)))))
        case .retryWholeText:
            try await retryWholeText(text, direction, context, emit)
        case .degrade(let reason):
            emit(.finished(joined(response.blocks, masked.first, direction, context, reason)))
        }
    }

    /// The single retry: the whole text as one block, whose line breaks the
    /// model carries through itself.
    private func retryWholeText(
        _ text: UserText, _ direction: Direction, _ context: Context,
        _ emit: (TranslationEvent) -> Void
    ) async throws {
        let whole = TokenProtector.mask(text.value, terms: context.terms)
        let raw = try await generate([whole], context, emit)
        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            return emit(.finished(unparsed(raw, direction, context)))
        }
        let decision = BlockCountPolicy().decide(
            expected: 1, received: response.blocks.count, attempt: 1)
        guard decision == .accept else {
            var reason = "The model did not keep the text's structure."
            if case .degrade(let detail) = decision { reason = detail }
            return emit(.finished(joined(response.blocks, whole, direction, context, reason)))
        }
        let finished = context.processor.finish(response.blocks[0], protected: whole)
        emit(.finished(TranslationResult(
            text: UserText(finished.text), direction: direction,
            warnings: warnings(finished.problems))))
    }

    private func generate(
        _ blocks: [ProtectedText], _ context: Context, _ emit: (TranslationEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: .translate, source: context.source, target: context.target,
            profile: context.profile, glossary: context.glossary,
            doNotTranslate: context.terms, blocks: blocks.map(\.text)))

        var raw = ""
        var shown: [String] = []
        for try await event in chat.chat(
            model: context.model, messages: [ChatMessage(role: "user", content: prompt)])
        {
            try Task.checkCancellation()
            guard case .delta(let piece) = event else { continue }
            raw += piece
            let partial = PartialTranslateBlocks.extract(from: raw)
            guard !partial.isEmpty, partial != shown else { continue }
            shown = partial
            emit(.preview(UserText(preview(partial, blocks, context))))
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyResponse
        }
        return raw
    }

    private func preview(
        _ partial: [String], _ blocks: [ProtectedText], _ context: Context
    ) -> String {
        partial.enumerated().map { index, block in
            guard index < blocks.count else { return block }
            return context.processor.finish(block, protected: blocks[index]).text
        }.joined(separator: "\n")
    }

    private func unparsed(
        _ raw: String, _ direction: Direction, _ context: Context
    ) -> TranslationResult {
        let text = LocaleRuleApplier.apply(context.processor.rules, to: raw, protecting: [])
        return TranslationResult(
            text: UserText(text), direction: direction,
            warnings: ["The model's reply was not in the expected format, so it is shown as it came."])
    }

    private func joined(
        _ blocks: [String], _ protected: ProtectedText?, _ direction: Direction,
        _ context: Context, _ reason: String
    ) -> TranslationResult {
        let texts = blocks.map { block -> String in
            guard let protected else { return block }
            return context.processor.finish(block, protected: protected).text
        }
        return TranslationResult(
            text: UserText(texts.joined(separator: "\n")), direction: direction,
            warnings: [reason])
    }

    private func warnings(_ problems: [ProtectionProblem]) -> [String] {
        problems.map { problem in
            switch problem {
            case .sentinelMissing(_, let term):
                return "\"\(term)\" may not have been kept as written."
            case .sentinelDebris:
                return "The model left a placeholder behind; check the text before using it."
            }
        }
    }
}
```

`LocaleRuleApplier.apply(_:to:protecting:)` and `PostProcessor.rules` are both public (`LocaleRuleApplier.swift:15`, `PostProcessor.swift:22`).

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TranslatorTests`
Expected: all pass.

- [ ] **Step 5: Verify two guards by breaking them.**
  - Change `attempt: 1` to `attempt: 0` in `retryWholeText`'s decision and remove the `guard decision == .accept` early return's `return`: `degradesAfterOneRetry` must fail. Revert.
  - Delete `try Task.checkCancellation()` and confirm nothing fails -- then note it in the commit message as unguarded by tests (cancellation is exercised manually in Task 6). Restore it.

- [ ] **Step 6: Add to the mutation list** -- `Sources/BabelOtterKit/Pipeline/Translator.swift` into `PASS1` in `.github/workflows/mutation.yml`. Run the full `swift test`.

- [ ] **Step 7: Live check against the real model** (local only, not committed as a test):

```bash
BABELOTTER_INTEGRATION=1 swift test --filter OllamaIntegrationTests
```

Expected: pass with `mistral-small3.2:24b` installed.

- [ ] **Step 8: Commit**

```bash
git add Sources/BabelOtterKit/Pipeline Tests/BabelOtterKitTests/Pipeline .github/workflows/mutation.yml
git commit -m "feat: one call from selected text to a finished translation"
```

---

### Task 4: A menu bar app you can launch

**Files:**
- Modify: `Package.swift`, `.gitignore`
- Create: `Tools/app/Info.plist`, `Tools/make-app.sh`
- Rewrite: `Sources/BabelOtterApp/main.swift`
- Create: `Sources/BabelOtterApp/AppDelegate.swift`, `Sources/BabelOtterApp/AppEnvironment.swift`

**Interfaces:**
- Produces: `AppEnvironment` with `configuration: Configuration` and `client: OllamaClient`; `AppDelegate` owning the status item. Task 5 adds `translateSelection()` to `AppDelegate`.

**One-time manual step (the user):** create a stable signing identity, or macOS
forgets the Accessibility grant on every rebuild (an ad-hoc signature changes
with every binary). Keychain Access > Certificate Assistant > Create a
Certificate... Name `babelOtter Dev`, Identity Type *Self Signed Root*,
Certificate Type *Code Signing*. `make-app.sh` falls back to ad-hoc signing,
with a warning, when it is absent.

- [ ] **Step 1: Declare the product** -- in `Package.swift` `products:` add:

```swift
        .executable(name: "BabelOtterApp", targets: ["BabelOtterApp"]),
```

and append to `.gitignore`:

```
# The assembled .app from Tools/make-app.sh
build/
```

- [ ] **Step 2: `Tools/app/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>ch.babelotter</string>
    <key>CFBundleName</key><string>babelOtter</string>
    <key>CFBundleDisplayName</key><string>babelOtter</string>
    <key>CFBundleExecutable</key><string>babelOtter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Runs entirely on this Mac.</string>
</dict>
</plist>
```

- [ ] **Step 3: `Tools/make-app.sh`** (then `chmod +x`)

```bash
#!/usr/bin/env bash
# Builds build/babelOtter.app from the BabelOtterApp target and signs it.
#
# The signature is what the Accessibility grant is attached to. An ad-hoc
# signature changes with every build, so macOS forgets the grant each time;
# a stable identity ("babelOtter Dev", self-signed, Code Signing) keeps it.
#
#   Tools/make-app.sh          build and assemble
#   Tools/make-app.sh --run    ...then quit any running copy and open it
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product BabelOtterApp
bin="$(swift build -c release --show-bin-path)/BabelOtterApp"

app="build/babelOtter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/babelOtter"
cp Tools/app/Info.plist "$app/Contents/Info.plist"

identity="${BABELOTTER_SIGNING_IDENTITY:-babelOtter Dev}"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
  codesign --force --sign "$identity" "$app"
else
  echo "warning: no '$identity' signing identity; signing ad hoc." >&2
  echo "warning: Accessibility will need granting again after every build." >&2
  codesign --force --sign - "$app"
fi
echo "built $app"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x babelOtter || true
  open "$app"
fi
```

- [ ] **Step 4: `Sources/BabelOtterApp/AppEnvironment.swift`**

```swift
import BabelOtterKit
import Foundation

/// Configuration and the Ollama client, built once at launch.
struct AppEnvironment: Sendable {

    let configuration: Configuration
    let configurationProblems: [ConfigurationProblem]
    let client: OllamaClient

    /// Reads `~/Library/Application Support/ch.babelotter/config.json`, and
    /// writes the defaults there on first launch so the glossary and
    /// do-not-translate list can be edited by hand until settings exist (M3).
    static func load() -> AppEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // NFR-P7: the directories iCloud Drive can sync on this machine.
        let locator = StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })

        var configuration = Configuration.default
        var problems: [ConfigurationProblem] = []
        if let store = try? ConfigurationStore.inApplicationSupport(locator: locator) {
            let loaded = store.load()
            configuration = loaded.configuration
            problems = loaded.problems
            if !FileManager.default.fileExists(atPath: store.fileURL.path) {
                try? store.save(configuration)
            }
        }
        return AppEnvironment(
            configuration: configuration,
            configurationProblems: problems,
            client: OllamaClient(
                transport: URLSessionTransport(timeout: configuration.timeoutSeconds)))
    }
}
```

- [ ] **Step 5: `Sources/BabelOtterApp/AppDelegate.swift`**

```swift
import AppKit
import ApplicationServices
import BabelOtterKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let ollamaLine = NSMenuItem(title: "Ollama: checking...", action: nil, keyEquivalent: "")
    private let accessLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private(set) var environment = AppEnvironment.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        promptForAccessibilityIfNeeded()
        refreshStatus()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "\u{1F9A6}"
        item.button?.toolTip = "babelOtter"

        let menu = NSMenu()
        menu.addItem(ollamaLine)
        menu.addItem(accessLine)
        menu.addItem(.separator())
        menu.addItem(action("Check Again", #selector(refreshStatusAction)))
        menu.addItem(action("Open Configuration Folder", #selector(openConfiguration)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit babelOtter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Shows the system prompt once; the grant itself happens in System Settings.
    private func promptForAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func refreshStatusAction() { refreshStatus() }

    func refreshStatus() {
        accessLine.title = AXIsProcessTrusted()
            ? "Accessibility: granted"
            : "Accessibility: not granted (System Settings > Privacy & Security)"
        let client = environment.client
        let model = environment.configuration.models[.translate] ?? Configuration.defaultModel
        Task {
            let status = await client.health(configuredModel: model)
            ollamaLine.title = "Ollama: \(status.detail)"
        }
    }

    @objc private func openConfiguration() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appending(path: "Library/Application Support/ch.babelotter"))
    }
}
```

- [ ] **Step 6: `Sources/BabelOtterApp/main.swift`**

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
```

- [ ] **Step 7: Build and run**

Run: `swift test && Tools/make-app.sh --run`
Expected: tests pass (the networking and UI-import guards scan the new files); an otter appears in the menu bar; its menu reads `Ollama: ...` with the model ready, and an Accessibility line. On first launch macOS shows the Accessibility prompt. Grant it in System Settings, then choose *Check Again*: the line reads *granted*. Rebuild with `Tools/make-app.sh --run`: with the `babelOtter Dev` identity the grant survives.

- [ ] **Step 8: Commit**

```bash
git add Package.swift .gitignore Tools/app Tools/make-app.sh Sources/BabelOtterApp
git commit -m "feat: a menu bar app that reports Ollama and Accessibility status"
```

---

### Task 5: Hotkey, capture, and a popup that shows what was captured

**Files:**
- Create: `Sources/BabelOtterApp/HotKey.swift`, `Sources/BabelOtterApp/SelectionCapturer.swift`, `Sources/BabelOtterApp/PopupPanel.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `HotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping @MainActor () -> Void)`, failable.
  - `enum CaptureOutcome: Sendable { case captured(SelectionSnapshot), refused(CaptureRefusal) }`
  - `struct SelectionCapturer: Sendable { let configuration: Configuration; func capture(from application: SourceApplication) -> CaptureOutcome }` -- blocking; call it off the main thread.
  - `@MainActor final class PopupPanel: NSPanel` with `func show<Content: View>(_ content: Content)` and `func dismiss()`.

- [ ] **Step 1: `Sources/BabelOtterApp/HotKey.swift`**

```swift
import AppKit
import Carbon.HIToolbox

/// A global hotkey through Carbon's `RegisterEventHotKey`.
///
/// FR-UI-01: this needs no Input Monitoring permission, where an `NSEvent`
/// global monitor or a `CGEventTap` would.
@MainActor
final class HotKey {

    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false

    private var reference: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping @MainActor () -> Void) {
        Self.installHandlerOnce()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4254_4F54), id: id)  // "BTOT"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        self.reference = reference
        Self.actions[id] = action
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKey.actions[id]?() }
                }
                return noErr
            },
            1, &spec, nil, nil)
    }
}
```

- [ ] **Step 2: `Sources/BabelOtterApp/SelectionCapturer.swift`**

```swift
import BabelOtterKit
import CoreGraphics
import Foundation

enum CaptureOutcome: Sendable {
    case captured(SelectionSnapshot)
    case refused(CaptureRefusal)
}

/// Accessibility tiers first, then the clipboard (architecture section 7).
///
/// Blocking -- the clipboard tier polls the pasteboard -- so call it off the
/// main thread.
struct SelectionCapturer: Sendable {

    let configuration: Configuration

    func capture(from application: SourceApplication) -> CaptureOutcome {
        let policy = CapturePolicy(configuration: configuration)
        let reader = AccessibilityReader(processIdentifier: application.processIdentifier)
        let accessibilityTiers = policy.allowedTiers.filter { !$0.usesPasteboard }

        if let hit = TierLadder().capture(from: reader, allowing: accessibilityTiers) {
            return checked(SelectionSnapshot(
                text: UserText(hit.text), tier: hit.tier, application: application))
        }
        guard policy.allowedTiers.contains(.clipboard) else {
            return .refused(policy.refusal(
                application: application.name, clipboardWouldHaveBeenTried: true))
        }

        waitForModifierRelease()
        let capture = ClipboardCapture(pasteboard: SystemPasteboard(), keystrokes: SyntheticKeystrokes())
        guard case .success(let text) = capture.capture() else {
            return .refused(.nothingSelected)
        }
        return checked(SelectionSnapshot(
            text: UserText(text), tier: .clipboard, application: application))
    }

    private func checked(_ snapshot: SelectionSnapshot) -> CaptureOutcome {
        if let refusal = ActionPrecondition.refusal(for: snapshot) { return .refused(refusal) }
        return .captured(snapshot)
    }

    /// The hotkey fires while Control and Option are still held. A synthetic
    /// Command-C posted then can arrive as Control-Option-Command-C, which
    /// copies nothing. Wait, briefly, for the hand to come off the keys.
    private func waitForModifierRelease(timeout: TimeInterval = 1.0) {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
```

- [ ] **Step 3: `Sources/BabelOtterApp/PopupPanel.swift`**

```swift
import AppKit
import SwiftUI

/// A floating panel that takes keyboard focus without activating babelOtter,
/// so the application the text came from stays frontmost (spec M1b,
/// "non-activating popup").
@MainActor
final class PopupPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    func show<Content: View>(_ content: Content) {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        contentViewController = controller
        placeNearCursor()
        orderFrontRegardless()
        makeKey()
    }

    func dismiss() {
        orderOut(nil)
        contentViewController = nil
    }

    private func placeNearCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(origin)
    }
}
```

- [ ] **Step 4: Wire the hotkey to a capture-only popup** -- in `AppDelegate`, add stored properties and a method, and register in `applicationDidFinishLaunching` after `buildMenu()`:

```swift
    private var hotKey: HotKey?
    private let panel = PopupPanel()
```

```swift
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), id: 1
        ) { [weak self] in self?.translateSelection() }
        if hotKey == nil { ollamaLine.title = "Control-Option-T is taken by another app" }
```

(`import Carbon.HIToolbox` at the top of the file for `kVK_ANSI_T`, `controlKey`, `optionKey`.)

```swift
    func translateSelection() {
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let source = SourceApplication(
            processIdentifier: front.processIdentifier,
            bundleIdentifier: front.bundleIdentifier,
            name: front.localizedName ?? "this application")

        panel.show(Text("Reading the selection...").padding(16))
        let capturer = SelectionCapturer(configuration: environment.configuration)
        Task {
            let outcome = await Task.detached { capturer.capture(from: source) }.value
            switch outcome {
            case .refused(let refusal):
                panel.show(Text(refusal.detail).padding(16))
            case .captured(let snapshot):
                panel.show(Text("Captured \(snapshot.text.characterCount) characters via \(String(describing: snapshot.tier))").padding(16))
            }
        }
    }
```

Add `menu.addItem(action("Translate Selection (Control-Option-T)", #selector(translateSelectionAction)))` at the top of `buildMenu()`'s menu, with `@objc private func translateSelectionAction() { translateSelection() }`. It is useful for the menu-bar trigger the spec asks for, but choosing it moves focus to the menu, so the hotkey remains the primary path.

- [ ] **Step 5: Manual check**

Run: `swift test && Tools/make-app.sh --run`, then select text and press Control-Option-T in each of:

| App | Expected |
|---|---|
| TextEdit | `via accessibilityText` |
| Safari (page text) | `via textMarkerRange` |
| VS Code, Teams, Word | `via clipboard`; your previous clipboard is still there afterwards |
| Any app, nothing selected | the *nothing selected* message |

The panel must appear near the pointer without the source app losing its
active title bar.

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterApp
git commit -m "feat: capture the selection from a global hotkey into a popup"
```

---

### Task 6: Translation in the popup

**Files:**
- Create: `Sources/BabelOtterApp/PopupModel.swift`, `Sources/BabelOtterApp/PopupView.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `Translator`, `Direction`, `TranslationEvent`, `TranslationError` (Task 3); `SelectionCapturer`, `PopupPanel` (Task 5).
- Produces: `@MainActor @Observable final class PopupModel` with `init(environment: AppEnvironment, close: @escaping @MainActor () -> Void)`, `func begin(with outcome: CaptureOutcome)`, `func choose(target: LanguageCode)`, `func swap()`, `func copy()`, `func dismiss()`; Task 7 adds `replace()`.

- [ ] **Step 1: `Sources/BabelOtterApp/PopupModel.swift`**

```swift
import AppKit
import BabelOtterKit
import Observation

/// One invocation, from capture to a decision about the result.
@MainActor
@Observable
final class PopupModel {

    enum Phase: Equatable {
        case capturing
        case choosingDirection([LanguageCode])
        case translating
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .capturing
    private(set) var direction: Direction?
    private(set) var text = ""
    private(set) var warnings: [String] = []
    private(set) var message: String?

    let configuration: Configuration
    private let translator: Translator
    private let close: @MainActor () -> Void
    private(set) var snapshot: SelectionSnapshot?
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    init(environment: AppEnvironment, close: @escaping @MainActor () -> Void) {
        self.configuration = environment.configuration
        self.translator = Translator(configuration: environment.configuration, chat: environment.client)
        self.close = close
    }

    func begin(with outcome: CaptureOutcome) {
        switch outcome {
        case .refused(let refusal):
            phase = .failed(refusal.detail)
        case .captured(let snapshot):
            self.snapshot = snapshot
            switch translator.direction(for: snapshot.text) {
            case .success(let direction):
                run(direction)
            case .failure(.directionUnknown(let candidates)):
                phase = .choosingDirection(candidates)
            case .failure(.languageNotConfigured(let code)):
                phase = .failed("This looks like \(code), which is not one of your languages.")
            case .failure(.emptyResponse):
                phase = .failed("Nothing came back from the model.")
            }
        }
    }

    func choose(target: LanguageCode) {
        guard let direction = translator.direction(into: target) else { return }
        run(direction)
    }

    func swap() {
        guard let direction else { return }
        run(direction.swapped)
    }

    func displayName(_ code: LanguageCode) -> String {
        configuration.language(for: code)?.displayName ?? code.description
    }

    func copy() {
        guard phase == .finished else { return }
        SystemPasteboard().write(text, concealed: false)
        dismiss()
    }

    func dismiss() {
        stop()
        close()
    }

    /// Cancelling the consumer ends the `for await`, which terminates the
    /// translator's stream, which cancels the HTTP request.
    private func stop() {
        consumer?.cancel()
        watchdog?.cancel()
        consumer = nil
        watchdog = nil
    }

    private var profile: AudienceProfile {
        configuration.profile(id: AudienceProfile.colleagues.id) ?? .colleagues
    }

    private func run(_ direction: Direction) {
        guard let snapshot else { return }
        stop()
        self.direction = direction
        text = ""
        warnings = []
        message = nil
        phase = .translating

        let stream = translator.translate(snapshot.text, direction: direction, profile: profile)
        let timeout = configuration.timeoutSeconds

        // Both tasks inherit the main actor, so they touch `self` directly.
        let consumer = Task { [weak self] in
            do {
                for try await event in stream { self?.apply(event) }
            } catch {
                // A cancelled request can surface as a URL error rather than
                // CancellationError; either way the reason was set by
                // whoever cancelled.
                guard !Task.isCancelled else { return }
                self?.phase = .failed(Self.describe(error))
            }
            self?.watchdog?.cancel()
        }
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.phase == .translating else { return }
            consumer.cancel()
            self.phase = .failed(
                ResultCustody.afterCancellation(.timedOut).message ?? "Timed out.")
        }
        self.consumer = consumer
    }

    private func apply(_ event: TranslationEvent) {
        switch event {
        case .started(let direction):
            self.direction = direction
        case .preview(let partial):
            text = partial.value
        case .finished(let result):
            text = result.text.value
            warnings = result.warnings
            phase = .finished
        }
    }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TranslationError, failure == .emptyResponse {
            return "Nothing came back from the model."
        }
        return "Ollama could not be reached. Is it running?"
    }
}
```

- [ ] **Step 2: `Sources/BabelOtterApp/PopupView.swift`**

```swift
import BabelOtterKit
import SwiftUI

struct PopupView: View {

    @Bindable var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            ForEach(model.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            actions
        }
        .padding(14)
        .frame(width: 440)
    }

    private var header: some View {
        HStack {
            Text("\u{1F9A6} babelOtter").font(.headline)
            Spacer()
            if let direction = model.direction {
                Text("\(model.displayName(direction.source)) \u{2192} \(model.displayName(direction.target))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Swap", systemImage: "arrow.left.arrow.right") { model.swap() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(model.phase == .capturing)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .capturing:
            ProgressView("Reading the selection...").controlSize(.small)
        case .choosingDirection(let candidates):
            Text("Translate into:")
            HStack {
                ForEach(candidates, id: \.self) { code in
                    Button(model.displayName(code)) { model.choose(target: code) }
                }
            }
        case .translating, .finished:
            ScrollView {
                Text(model.text.isEmpty ? " " : model.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 40, maxHeight: 320)
            if model.phase == .translating {
                ProgressView().controlSize(.small)
            }
        case .failed(let reason):
            Text(reason).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button("Copy") { model.copy() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.phase != .finished)
            Spacer()
            Button("Dismiss") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
```

- [ ] **Step 3: Replace the capture-only popup in `AppDelegate.translateSelection()`**

```swift
        let model = PopupModel(environment: environment) { [weak self] in self?.panel.dismiss() }
        currentModel = model
        panel.show(PopupView(model: model))
        let capturer = SelectionCapturer(configuration: environment.configuration)
        Task {
            let outcome = await Task.detached { capturer.capture(from: source) }.value
            model.begin(with: outcome)
        }
```

with `private var currentModel: PopupModel?` stored on the delegate (so the model
outlives the call). A second hotkey press while a popup is open calls
`currentModel?.dismiss()` first.

- [ ] **Step 4: Manual check** -- `swift test && Tools/make-app.sh --run`:

| Do | Expected |
|---|---|
| Select a German paragraph in TextEdit, Control-Option-T | Swiss Standard German -> English; text streams in; no `\u{27E6}DNT` debris, no JSON |
| Select English, Control-Option-T | English -> Swiss Standard German; no eszett anywhere, preview included |
| Select "Hallo", Control-Option-T | *Translate into:* with two buttons; either one translates |
| Press Swap during or after a translation | the direction flips and it re-runs |
| Press Escape mid-stream | popup closes; `ollama ps` shows the request stopping |
| A bullet list | markers and line structure survive |
| Quit Ollama, Control-Option-T | "Ollama could not be reached" rather than a hang |
| Copy | result on the clipboard, popup closed |

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterApp
git commit -m "feat: stream a translation into the popup, with direction choice and swap"
```

---

### Task 7: Replace, and the prototype is usable

**Files:**
- Modify: `Sources/BabelOtterApp/PopupModel.swift`, `Sources/BabelOtterApp/PopupView.swift`, `Sources/BabelOtterApp/AppDelegate.swift`
- Modify: `README.md` (status block), `docs/HANDOFF.md`, `docs/architecture.md` section 7 (anything the prototype contradicts)

**Interfaces:**
- Consumes: `ClipboardReplacement(pasteboard:keystrokes:settle:)` (Task 1), `ResultCustody.afterReplacement`, `ResultCustody.afterSourceQuit`, `GeneratedResult`.
- Produces: `PopupModel.replace()`; `PopupModel.init` gains `reopen: @escaping @MainActor () -> Void`, called when custody keeps the popup open after a failed replacement.

- [ ] **Step 1: `PopupModel.replace()`**

```swift
    func replace() {
        guard phase == .finished, let snapshot else { return }
        let result = GeneratedResult(
            text: UserText(text), action: .translate,
            capturedViaPasteboard: snapshot.usedPasteboard)
        let pid = snapshot.application.processIdentifier

        guard let source = NSRunningApplication(processIdentifier: pid), !source.isTerminated else {
            settle(ResultCustody.afterSourceQuit(result: result))
            return
        }
        close()                      // the panel must not be key when Command-V is posted
        source.activate()
        let text = self.text
        Task {
            var frontmost = false
            for _ in 0..<50 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    frontmost = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let isFront = frontmost
            let outcome = await Task.detached {
                ClipboardReplacement(
                    pasteboard: SystemPasteboard(), keystrokes: SyntheticKeystrokes(),
                    settle: { Thread.sleep(forTimeInterval: 0.5) }
                ).replace(with: text, activateSource: { isFront })
            }.value
            settle(ResultCustody.afterReplacement(outcome, result: result))
        }
    }

    private func settle(_ custody: Custody) {
        message = custody.message
        guard custody.keepsPopupOpen else { return }
        reopen()
    }
```

Add `private let reopen: @MainActor () -> Void` and the matching `init`
parameter. `AppDelegate` passes `{ [weak self] in guard let self, let model = self.currentModel else { return }; self.panel.show(PopupView(model: model)) }`.

- [ ] **Step 2: The Replace button** -- in `PopupView.actions`, before Copy:

```swift
            Button("Replace") { model.replace() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.phase != .finished)
```

- [ ] **Step 3: Manual check** -- `swift test && Tools/make-app.sh --run`:

| Surface | Expected |
|---|---|
| TextEdit | selection replaced; previous clipboard intact afterwards (Command-V elsewhere) |
| Safari `<textarea>` (`Tools/editable-scratch.html`) | replaced |
| Mail compose, Outlook body | replaced |
| Teams, Word, VS Code | replaced |
| Source app quit before pressing Replace | popup stays, says the app has closed, Copy still works |

Anything that contradicts `docs/architecture.md` section 7 gets recorded there,
plainly.

- [ ] **Step 4: Docs.** README status block: M1a done, Translate prototype usable, how to build (`Tools/make-app.sh --run`) and the signing identity step. HANDOFF: what the prototype does, what it skips (profile control, settings, onboarding, history), and the next slice.

- [ ] **Step 5: Commit, push, and open a PR to `main`**

```bash
git add Sources/BabelOtterApp README.md docs
git commit -m "feat: replace the selection with the translation"
git push -u origin feat/translate-prototype
gh pr create --title "Translate prototype" --body "..."
```

---

## Self-review

**Spec coverage (M1b, cut to Translate).** Hotkeys -> Task 5 (one, fixed). Menu bar -> Task 4. Permissions -> Task 4 (prompt and status; full onboarding is M3's FR-ONB-01). Non-activating popup -> Task 5. Streaming render -> Tasks 2, 3, 6. Direction swap -> Task 6. End-to-end Translate -> Tasks 3, 6, 7. **Deliberately not here:** profile control (fixed to Colleagues; #58's UI half), per-invocation style note, Regenerate, configurable hotkeys, settings window, history. Each is a small follow-up once the prototype is in daily use.

**Placeholder scan.** None. App tasks carry full code and a manual check table instead of tests, per the rigour-by-layer constraint.

**Type consistency.** `Direction`, `TranslationEvent`, `TranslationResult`, `TranslationError`, `ChatStreaming` are defined in Task 3 and used unchanged in Task 6. `CaptureOutcome` is defined in Task 5 and consumed in Task 6. `ClipboardReplacement`'s `settle:` is defined in Task 1 and used in Task 7. `PopupModel.init` gains `reopen:` in Task 7; `AppDelegate`'s construction is updated in the same task.
