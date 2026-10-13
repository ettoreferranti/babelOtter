# Configurable Hotkeys and Live Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate and Correct hotkeys are assigned in `config.json` as readable text, resolved through the current keyboard layout, and every saved change to the configuration takes effect without a restart (#26).

**Architecture:** Pure decisions in `BabelOtterKit` (parse a hotkey, resolve it against a layout table, plan the hotkeys keeping what works, decide what a reload keeps), unit-tested and mutation-gated. The app supplies the OS edges: a folder-and-file watcher, a keyboard-layout reader over `UCKeyTranslate`, Carbon registration with explicit unregister, and one apply path in `AppDelegate`. Configuration problems become a readiness cause.

**Tech Stack:** Swift 6 (CI builds with Xcode 16.4, Swift 6.1), SwiftPM, Swift Testing, AppKit, Carbon `RegisterEventHotKey` / `UnregisterEventHotKey`, Text Input Sources (`TIS*`, `UCKeyTranslate`), `DispatchSource` file-system sources.

**Spec:** `docs/superpowers/specs/2026-10-12-configurable-hotkeys-design.md`

## Global Constraints

- Kit sources (`Sources/BabelOtterKit/**`) are ASCII-only (`AsciiSourceTests`): write non-ASCII characters as `\u{...}` escapes.
- The kit imports no UI framework and no Carbon (`NoUIImportsTests`): Carbon constants are written as literals with a comment naming them.
- Every new kit file is added to the PASS1 list in `.github/workflows/mutation.yml` in the same task that creates it; CI fails on an unlisted file.
- muter traps in kit code: no closures (`map`, `filter`, `first { }`), no comma-conjunction conditions (`if a, b`), no ternaries over enums. Use loops, nested `if`, and `switch`.
- Carbon modifier bits: command `0x100`, shift `0x200`, option `0x800`, control `0x1000`.
- Hotkey display names order modifiers Control, Option, Shift, Command, joined with `-`: "Control-Option-T".
- Defaults: Translate `control+option+T`, Correct `control+option+C`. Launch combinations: T = key code `0x11`, C = `0x08`, modifiers `0x1800`.
- Configuration problem wording appended on reload: ` - still using the previous settings`.
- Build gate for app code: `swift build -Xswiftc -warnings-as-errors` must succeed; full suite: `swift test`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A save that writes into the existing file** (VS Code) as well as one that renames a new file over it (TextEdit): both must reload. Covered by the two-source watcher in Task 7 and manual check H9.
2. **Translate and Correct swapped in one save**: both must end up registered, which needs every changed hotkey released before any is registered. Kit side pinned by `HotKeyPlanTests.swapIsNoDuplicate` (Task 4); app ordering by the two loops in Task 8 and manual check H10.
3. **A launch-time problem fixed by a later save** must clear the problem. Pinned by `ConfigurationReloadTests.fixedFileClearsProblems` (Task 5).
4. **A hotkey written as whitespace only, or with an empty part** (`"control++"`): a named problem, never a crash or a silent default. Pinned in `HotKeySpecTests` (Task 2).
5. **A Correct typo whose previous combination Translate has just taken**: Correct must end up with no hotkey rather than a duplicate. Pinned by `HotKeyPlanTests.typoKeepsPreviousOnlyIfFree` (Task 4).

---

### Task 1: `HotKeyBindings` and `Configuration.hotkeys`

**Files:**
- Create: `Sources/BabelOtterKit/Config/HotKeyBindings.swift`
- Modify: `Sources/BabelOtterKit/Config/Configuration.swift` (stored properties, `init`, `Configuration.default`)
- Modify: `.github/workflows/mutation.yml` (PASS1 list)
- Test: `Tests/BabelOtterKitTests/Config/HotKeyBindingsTests.swift`, `Tests/BabelOtterKitTests/Config/ConfigurationStoreTests.swift`

**Interfaces:**
- Produces: `public enum HotKeyBinding { case useDefault, off, text(String) }`; `public struct HotKeyBindings { var translate, correct: HotKeyBinding; init(translate:correct:) (both default .useDefault); static let defaults; static func defaultText(for: Action) -> String?; func binding(for: Action) -> HotKeyBinding }`; `Configuration.hotkeys: HotKeyBindings?`.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Config/HotKeyBindingsTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Hotkey bindings in config.json")
struct HotKeyBindingsTests {

    private func decode(_ json: String) throws -> HotKeyBindings {
        try JSONDecoder().decode(HotKeyBindings.self, from: Data(json.utf8))
    }

    @Test("a string is the text as written; an absent action is its default")
    func textAndAbsent() throws {
        let bindings = try decode(#"{"translate": "control+option+Y"}"#)
        #expect(bindings.translate == .text("control+option+Y"))
        #expect(bindings.correct == .useDefault)
    }

    @Test("null turns a hotkey off")
    func nullIsOff() throws {
        #expect(try decode(#"{"translate": null}"#).translate == .off)
    }

    @Test("an empty object leaves both at their defaults")
    func emptyObject() throws {
        #expect(try decode("{}") == HotKeyBindings())
    }

    @Test("a number where text belongs is a decoding error, not a silent default")
    func wrongType() {
        #expect(throws: DecodingError.self) { try decode(#"{"translate": 5}"#) }
    }

    @Test("off is written as null and a default is left out, so the file round-trips")
    func encoding() throws {
        let bindings = HotKeyBindings(translate: .useDefault, correct: .off)
        let data = try JSONEncoder().encode(bindings)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("translate"))
        #expect(text.contains(#""correct":null"#))
        #expect(try JSONDecoder().decode(HotKeyBindings.self, from: data) == bindings)
    }

    @Test("the defaults are Control-Option-T and Control-Option-C, as text")
    func defaults() {
        #expect(HotKeyBindings.defaults.translate == .text("control+option+T"))
        #expect(HotKeyBindings.defaults.correct == .text("control+option+C"))
        #expect(HotKeyBindings.defaultText(for: .translate) == "control+option+T")
        #expect(HotKeyBindings.defaultText(for: .correct) == "control+option+C")
        #expect(HotKeyBindings.defaultText(for: .explain) == nil)
    }

    @Test("each action reads its own binding; actions without one are off")
    func bindingForAction() {
        let bindings = HotKeyBindings(translate: .text("a"), correct: .text("b"))
        #expect(bindings.binding(for: .translate) == .text("a"))
        #expect(bindings.binding(for: .correct) == .text("b"))
        #expect(bindings.binding(for: .explain) == .off)
        #expect(bindings.binding(for: .repitch) == .off)
    }

    @Test("a fresh configuration writes both defaults out, so the field is discoverable")
    func defaultConfigurationHasThem() {
        #expect(Configuration.default.hotkeys == HotKeyBindings.defaults)
    }
}
```

Append to `ConfigurationStoreTests` (before its closing brace):

```swift
    @Test("a file written before hotkeys existed still loads, with no problems")
    func fileWithoutHotkeys() throws {
        let store = ConfigurationStore(directory: try temporaryDirectory())
        try store.save(.default)
        let data = try Data(contentsOf: store.fileURL)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["hotkeys"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.problems.isEmpty)
        #expect(loaded.configuration.hotkeys == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "HotKeyBindingsTests|ConfigurationStoreTests" 2>&1 | tail -5`
Expected: build failure, "cannot find 'HotKeyBindings' in scope".

- [ ] **Step 3: Write `HotKeyBindings.swift`**

```swift
import Foundation

/// One action's hotkey as written in config.json (#26).
public enum HotKeyBinding: Sendable, Equatable {
    /// The action is not in the file: its default applies.
    case useDefault
    /// JSON null: no hotkey, the menu only.
    case off
    /// As written, parsed later by `HotKeySpec`.
    case text(String)
}

/// The `hotkeys` object in config.json.
///
/// Text rather than key codes, parsed by `HotKeySpec` and resolved against
/// the keyboard layout by `KeyLayout`, so a typo in a hotkey is reported on
/// its own and never costs the rest of the file.
public struct HotKeyBindings: Sendable, Equatable, Codable {
    public var translate: HotKeyBinding
    public var correct: HotKeyBinding

    public init(translate: HotKeyBinding = .useDefault, correct: HotKeyBinding = .useDefault) {
        self.translate = translate
        self.correct = correct
    }

    public static let defaults = HotKeyBindings(
        translate: .text("control+option+T"), correct: .text("control+option+C"))

    /// Nil for actions that have no hotkey yet (Explain #65, Re-pitch #66).
    public static func defaultText(for action: Action) -> String? {
        switch action {
        case .translate:
            return "control+option+T"
        case .correct:
            return "control+option+C"
        case .explain, .repitch:
            return nil
        }
    }

    public func binding(for action: Action) -> HotKeyBinding {
        switch action {
        case .translate:
            return translate
        case .correct:
            return correct
        case .explain, .repitch:
            return .off
        }
    }

    private enum CodingKeys: String, CodingKey {
        case translate
        case correct
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translate = try Self.decode(.translate, in: container)
        correct = try Self.decode(.correct, in: container)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(translate, as: .translate, in: &container)
        try Self.encode(correct, as: .correct, in: &container)
    }

    /// Absent and null are different answers: absent is the default, null
    /// is "no hotkey".
    private static func decode(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HotKeyBinding {
        if !container.contains(key) {
            return .useDefault
        }
        if try container.decodeNil(forKey: key) {
            return .off
        }
        return .text(try container.decode(String.self, forKey: key))
    }

    private static func encode(
        _ binding: HotKeyBinding, as key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch binding {
        case .useDefault:
            return
        case .off:
            try container.encodeNil(forKey: key)
        case .text(let text):
            try container.encode(text, forKey: key)
        }
    }
}
```

- [ ] **Step 4: Add the field to `Configuration`**

In `Configuration.swift`, after `public var strictCaptureOnly: Bool`:

```swift
    /// Optional so a file written before #26 still loads: nil means each
    /// action's default.
    public var hotkeys: HotKeyBindings?
```

Add the parameter `hotkeys: HotKeyBindings? = nil` after `strictCaptureOnly: Bool = false` in `init`, and `self.hotkeys = hotkeys` after `self.strictCaptureOnly = strictCaptureOnly`. In `Configuration.default`, after `strictCaptureOnly: false` add `,` and `hotkeys: HotKeyBindings.defaults`.

In `.github/workflows/mutation.yml`, insert `          Sources/BabelOtterKit/Config/HotKeyBindings.swift` after the line `          Sources/BabelOtterKit/Config/Glossary.swift`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "HotKeyBindingsTests|ConfigurationStoreTests|AsciiSource" 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterKit/Config Tests/BabelOtterKitTests/Config .github/workflows/mutation.yml
git commit -m "feat(config): hotkeys as text in config.json, optional for older files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `HotKeySpec`

**Files:**
- Create: `Sources/BabelOtterKit/Hotkeys/HotKeySpec.swift`
- Modify: `.github/workflows/mutation.yml`
- Test: `Tests/BabelOtterKitTests/Hotkeys/HotKeySpecTests.swift`

**Interfaces:**
- Consumes: `Action.displayName` (exists).
- Produces: `public enum NamedKey: String, CaseIterable { f1...f20, space, returnKey = "return", tab, escape, delete, left, right, up, down; var keyCode: UInt32; var label: String }`; `public enum HotKeyKey: Equatable { case character(String), named(NamedKey) }`; `public enum HotKeyProblem: Error, Equatable { empty, emptyPart, unknownPart(String), noKey, severalKeys, needsModifier, notOnLayout(String), sharedWith(Action); var detail: String }`; `public struct HotKeySpec { let modifiers: UInt32; let key: HotKeyKey; static let command/shift/option/control: UInt32; static func parse(_:) -> Result<HotKeySpec, HotKeyProblem>; static func displayName(modifiers:keyLabel:) -> String }`.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Hotkeys/HotKeySpecTests.swift`:

```swift
import Testing

@testable import BabelOtterKit

@Suite("Hotkey text is parsed into modifiers and a key")
struct HotKeySpecTests {

    private func parse(_ text: String) -> HotKeySpec? {
        try? HotKeySpec.parse(text).get()
    }

    private func problem(_ text: String) -> HotKeyProblem? {
        switch HotKeySpec.parse(text) {
        case .success:
            return nil
        case .failure(let problem):
            return problem
        }
    }

    @Test("the default is control and option with the letter t")
    func controlOptionT() {
        #expect(parse("control+option+T") == HotKeySpec(modifiers: 0x1800, key: .character("t")))
    }

    @Test("short spellings, any order, any case, spaces around parts")
    func spellings() {
        let expected = HotKeySpec(modifiers: 0x1800, key: .character("t"))
        #expect(parse(" Ctrl + Alt + t ") == expected)
        #expect(parse("t+option+CONTROL") == expected)
        #expect(parse("cmd+shift+a") == HotKeySpec(modifiers: 0x300, key: .character("a")))
        #expect(parse("command+option+a")?.modifiers == 0x900)
    }

    @Test("named keys carry their fixed key codes")
    func namedKeys() {
        #expect(parse("control+F5") == HotKeySpec(modifiers: 0x1000, key: .named(.f5)))
        #expect(NamedKey.f1.keyCode == 0x7A)
        #expect(NamedKey.f5.keyCode == 0x60)
        #expect(NamedKey.f12.keyCode == 0x6F)
        #expect(NamedKey.f20.keyCode == 0x5A)
        #expect(NamedKey.space.keyCode == 0x31)
        #expect(NamedKey.returnKey.keyCode == 0x24)
        #expect(NamedKey.tab.keyCode == 0x30)
        #expect(NamedKey.escape.keyCode == 0x35)
        #expect(NamedKey.delete.keyCode == 0x33)
        #expect(NamedKey.left.keyCode == 0x7B)
        #expect(NamedKey.right.keyCode == 0x7C)
        #expect(NamedKey.down.keyCode == 0x7D)
        #expect(NamedKey.up.keyCode == 0x7E)
        #expect(parse("option+return")?.key == .named(.returnKey))
        #expect(NamedKey.returnKey.label == "Return")
        #expect(NamedKey.f12.label == "F12")
    }

    @Test("every F key from 1 to 20 is named, each with its own code")
    func allFunctionKeys() {
        var codes: Set<UInt32> = []
        for number in 1...20 {
            let key = NamedKey(rawValue: "f\(number)")
            #expect(key != nil)
            if let key {
                codes.insert(key.keyCode)
            }
        }
        #expect(codes.count == 20)
    }

    @Test("a letter outside ASCII is a character key")
    func nonASCIICharacter() {
        #expect(parse("control+option+\u{FC}")?.key == .character("\u{FC}"))
    }

    @Test("each mistake has its own problem")
    func problems() {
        #expect(problem("") == .empty)
        #expect(problem("   ") == .empty)
        #expect(problem("control++") == .emptyPart)
        #expect(problem("contrl+option+T") == .unknownPart("contrl"))
        #expect(problem("control+option") == .noKey)
        #expect(problem("control+T+C") == .severalKeys)
        #expect(problem("shift+T") == .needsModifier)
        #expect(problem("T") == .needsModifier)
    }

    @Test("problems are worded for the menu")
    func details() {
        #expect(HotKeyProblem.empty.detail == "is empty")
        #expect(HotKeyProblem.emptyPart.detail == "has an empty part (\"+\" cannot be the key)")
        #expect(HotKeyProblem.unknownPart("contrl").detail == "unknown key or modifier \"contrl\"")
        #expect(HotKeyProblem.noKey.detail == "names no key")
        #expect(HotKeyProblem.severalKeys.detail == "names more than one key")
        #expect(HotKeyProblem.needsModifier.detail == "needs control, option or command")
        #expect(HotKeyProblem.notOnLayout("\u{FC}").detail
            == "\"\u{FC}\" can't be typed on the current keyboard layout")
        #expect(HotKeyProblem.sharedWith(.translate).detail == "is also the Translate hotkey")
    }

    @Test("display names order modifiers as macOS does")
    func displayOrder() {
        #expect(HotKeySpec.displayName(modifiers: 0x1B00, keyLabel: "Z")
            == "Control-Option-Shift-Command-Z")
        #expect(HotKeySpec.displayName(modifiers: 0x1800, keyLabel: "T") == "Control-Option-T")
        #expect(HotKeySpec.displayName(modifiers: 0x100, keyLabel: "F5") == "Command-F5")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HotKeySpecTests 2>&1 | tail -5`
Expected: build failure, "cannot find 'HotKeySpec' in scope".

- [ ] **Step 3: Write `HotKeySpec.swift`**

```swift
import Foundation

/// A key whose position is the same on every layout, with its virtual key
/// code (`kVK_*` from Carbon's Events.h, written as literals because the kit
/// cannot import Carbon).
public enum NamedKey: String, Sendable, Equatable, CaseIterable {
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    case space
    case returnKey = "return"
    case tab, escape, delete, left, right, up, down

    public var keyCode: UInt32 {
        switch self {
        case .f1: return 0x7A
        case .f2: return 0x78
        case .f3: return 0x63
        case .f4: return 0x76
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F
        case .f13: return 0x69
        case .f14: return 0x6B
        case .f15: return 0x71
        case .f16: return 0x6A
        case .f17: return 0x40
        case .f18: return 0x4F
        case .f19: return 0x50
        case .f20: return 0x5A
        case .space: return 0x31
        case .returnKey: return 0x24
        case .tab: return 0x30
        case .escape: return 0x35
        case .delete: return 0x33
        case .left: return 0x7B
        case .right: return 0x7C
        case .down: return 0x7D
        case .up: return 0x7E
        }
    }

    /// "F5", "Space", "Return".
    public var label: String {
        rawValue.capitalized
    }
}

public enum HotKeyKey: Sendable, Equatable {
    /// One character, lowercased; resolved through the keyboard layout.
    case character(String)
    case named(NamedKey)
}

/// Why a hotkey from config.json is not used. `detail` follows the hotkey's
/// text in the menu: `translate hotkey "contrl+option+T": <detail>`.
public enum HotKeyProblem: Error, Sendable, Equatable {
    case empty
    case emptyPart
    case unknownPart(String)
    case noKey
    case severalKeys
    case needsModifier
    case notOnLayout(String)
    case sharedWith(Action)

    public var detail: String {
        switch self {
        case .empty:
            return "is empty"
        case .emptyPart:
            return "has an empty part (\"+\" cannot be the key)"
        case .unknownPart(let part):
            return "unknown key or modifier \"\(part)\""
        case .noKey:
            return "names no key"
        case .severalKeys:
            return "names more than one key"
        case .needsModifier:
            return "needs control, option or command"
        case .notOnLayout(let character):
            return "\"\(character)\" can't be typed on the current keyboard layout"
        case .sharedWith(let action):
            return "is also the \(action.displayName) hotkey"
        }
    }
}

/// A hotkey as written, parsed but not yet tied to a key position.
public struct HotKeySpec: Sendable, Equatable {
    /// Carbon modifier bits.
    public let modifiers: UInt32
    public let key: HotKeyKey

    public init(modifiers: UInt32, key: HotKeyKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Carbon's `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    /// "control+option+T": modifiers and one key joined by "+", in any order
    /// and case. Shift alone is refused: it would fire on every capital.
    public static func parse(_ text: String) -> Result<HotKeySpec, HotKeyProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .failure(.empty)
        }
        var modifiers: UInt32 = 0
        var key: HotKeyKey?
        for rawPart in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let part = rawPart.trimmingCharacters(in: .whitespaces).lowercased()
            if part.isEmpty {
                return .failure(.emptyPart)
            }
            if let bit = modifierBit(part) {
                modifiers |= bit
                continue
            }
            guard let parsed = keyFor(part) else {
                return .failure(.unknownPart(part))
            }
            if key != nil {
                return .failure(.severalKeys)
            }
            key = parsed
        }
        guard let key else {
            return .failure(.noKey)
        }
        if modifiers & (command | option | control) == 0 {
            return .failure(.needsModifier)
        }
        return .success(HotKeySpec(modifiers: modifiers, key: key))
    }

    /// "Control-Option-Shift-Command-Z": macOS's modifier order.
    public static func displayName(modifiers: UInt32, keyLabel: String) -> String {
        var name = ""
        if modifiers & control != 0 {
            name += "Control-"
        }
        if modifiers & option != 0 {
            name += "Option-"
        }
        if modifiers & shift != 0 {
            name += "Shift-"
        }
        if modifiers & command != 0 {
            name += "Command-"
        }
        return name + keyLabel
    }

    private static func modifierBit(_ part: String) -> UInt32? {
        switch part {
        case "control", "ctrl":
            return control
        case "option", "alt":
            return option
        case "command", "cmd":
            return command
        case "shift":
            return shift
        default:
            return nil
        }
    }

    private static func keyFor(_ part: String) -> HotKeyKey? {
        if let named = NamedKey(rawValue: part) {
            return .named(named)
        }
        if part.count == 1 {
            return .character(part)
        }
        return nil
    }
}
```

Insert `          Sources/BabelOtterKit/Hotkeys/HotKeySpec.swift` into the PASS1 list in `.github/workflows/mutation.yml`, after the `Config/LanguageConfig.swift` line.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "HotKeySpecTests|AsciiSource|NoUIImports" 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Hotkeys Tests/BabelOtterKitTests/Hotkeys .github/workflows/mutation.yml
git commit -m "feat(hotkeys): parse hotkey text into modifiers and a key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `KeyLayout`

**Files:**
- Create: `Sources/BabelOtterKit/Hotkeys/KeyLayout.swift`
- Modify: `.github/workflows/mutation.yml`
- Test: `Tests/BabelOtterKitTests/Hotkeys/KeyLayoutTests.swift`

**Interfaces:**
- Consumes: `HotKeySpec`, `HotKeyKey`, `NamedKey`, `HotKeyProblem` (Task 2); `HotKeyCombination(keyCode:modifiers:displayName:)` (exists, `ReadinessPolicy.swift`).
- Produces: `public struct KeyLayout { init(characters: [UInt32: String]); func resolve(_ spec: HotKeySpec) -> Result<HotKeyCombination, HotKeyProblem>; static let usANSI: KeyLayout }`; `extension HotKeyCombination { func sameKeys(as: HotKeyCombination) -> Bool }`.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Hotkeys/KeyLayoutTests.swift`:

```swift
import Testing

@testable import BabelOtterKit

@Suite("A hotkey's character is found on the current keyboard layout")
struct KeyLayoutTests {

    /// Key codes are positions: on Swiss German, Z sits where US has Y
    /// (kVK_ANSI_Y, 0x10) and Y where US has Z (kVK_ANSI_Z, 0x06).
    static let us = KeyLayout(characters: [0x06: "z", 0x08: "c", 0x10: "y", 0x11: "t", 0x12: "1"])
    static let swissGerman = KeyLayout(characters: [
        0x06: "y", 0x08: "c", 0x10: "z", 0x11: "t", 0x12: "1", 0x21: "\u{FC}",
    ])

    private func spec(_ text: String) -> HotKeySpec {
        switch HotKeySpec.parse(text) {
        case .success(let spec):
            return spec
        case .failure(let problem):
            Issue.record("could not parse \(text): \(problem)")
            return HotKeySpec(modifiers: 0, key: .character("?"))
        }
    }

    @Test("Z is the key labelled Z on each layout")
    func zFollowsTheLayout() throws {
        let z = spec("control+option+Z")
        #expect(try Self.us.resolve(z).get().keyCode == 0x06)
        #expect(try Self.swissGerman.resolve(z).get().keyCode == 0x10)
    }

    @Test("the combination keeps the modifiers and names the key in capitals")
    func combination() throws {
        let combination = try Self.swissGerman.resolve(spec("control+option+Z")).get()
        #expect(combination == HotKeyCombination(
            keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Z"))
    }

    @Test("a character the layout cannot type is reported")
    func notOnLayout() {
        let result = Self.us.resolve(spec("control+option+\u{FC}"))
        #expect(throws: HotKeyProblem.notOnLayout("\u{FC}")) { try result.get() }
        #expect(throws: Never.self) { try Self.swissGerman.resolve(spec("control+option+\u{FC}")).get() }
    }

    @Test("when two keys type the same character, the lowest code wins")
    func lowestCodeWins() throws {
        let layout = KeyLayout(characters: [0x32: "<", 0x0A: "<"])
        #expect(try layout.resolve(spec("control+<")).get().keyCode == 0x0A)
    }

    @Test("matching ignores case in the table too")
    func caseInsensitive() throws {
        let layout = KeyLayout(characters: [0x11: "T"])
        #expect(try layout.resolve(spec("control+t")).get().keyCode == 0x11)
    }

    @Test("named keys ignore the table")
    func namedKeys() throws {
        let combination = try KeyLayout(characters: [:]).resolve(spec("command+F5")).get()
        #expect(combination == HotKeyCombination(keyCode: 0x60, modifiers: 0x100, displayName: "Command-F5"))
    }

    @Test("the US table places the default keys where babelOtter registered them before #26")
    func usTable() throws {
        #expect(try KeyLayout.usANSI.resolve(spec("control+option+T")).get().keyCode == 0x11)
        #expect(try KeyLayout.usANSI.resolve(spec("control+option+C")).get().keyCode == 0x08)
    }

    @Test("same keys ignores the display name")
    func sameKeys() {
        let a = HotKeyCombination(keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Z")
        let b = HotKeyCombination(keyCode: 0x10, modifiers: 0x1800, displayName: "Control-Option-Y")
        let c = HotKeyCombination(keyCode: 0x10, modifiers: 0x1000, displayName: "Control-Z")
        let d = HotKeyCombination(keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-Z")
        #expect(a.sameKeys(as: b))
        #expect(!a.sameKeys(as: c))
        #expect(!a.sameKeys(as: d))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter KeyLayoutTests 2>&1 | tail -5`
Expected: build failure, "cannot find 'KeyLayout' in scope".

- [ ] **Step 3: Write `KeyLayout.swift`**

```swift
import Foundation

/// What each key types on the current keyboard layout, with no modifiers.
///
/// Carbon registers key positions, not characters. The app reads this table
/// from macOS (`UCKeyTranslate`) so that "control+option+Z" is the key
/// labelled Z on the layout in use, which on Swiss German is not the US Z.
public struct KeyLayout: Sendable, Equatable {
    public let characters: [UInt32: String]

    public init(characters: [UInt32: String]) {
        self.characters = characters
    }

    /// The letters A to Z on a US keyboard, by `kVK_ANSI_*` code. Used when
    /// macOS reports no layout at all.
    public static let usANSI = KeyLayout(characters: [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g",
        0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n",
        0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t", 0x20: "u",
        0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y", 0x06: "z",
    ])

    public func resolve(_ spec: HotKeySpec) -> Result<HotKeyCombination, HotKeyProblem> {
        switch spec.key {
        case .named(let named):
            return .success(HotKeyCombination(
                keyCode: named.keyCode, modifiers: spec.modifiers,
                displayName: HotKeySpec.displayName(modifiers: spec.modifiers, keyLabel: named.label)))
        case .character(let character):
            guard let code = keyCode(typing: character) else {
                return .failure(.notOnLayout(character))
            }
            return .success(HotKeyCombination(
                keyCode: code, modifiers: spec.modifiers,
                displayName: HotKeySpec.displayName(
                    modifiers: spec.modifiers, keyLabel: character.uppercased())))
        }
    }

    /// The lowest code that types it, so the answer never depends on
    /// dictionary order (an ISO keyboard has two keys typing "<").
    private func keyCode(typing character: String) -> UInt32? {
        var best: UInt32?
        for (code, typed) in characters where typed.lowercased() == character {
            if let current = best {
                if code < current {
                    best = code
                }
            } else {
                best = code
            }
        }
        return best
    }
}

extension HotKeyCombination {
    /// The same key and modifiers, whatever each is called.
    public func sameKeys(as other: HotKeyCombination) -> Bool {
        if keyCode != other.keyCode {
            return false
        }
        return modifiers == other.modifiers
    }
}
```

Insert `          Sources/BabelOtterKit/Hotkeys/KeyLayout.swift` into the PASS1 list after `Hotkeys/HotKeySpec.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "KeyLayoutTests|AsciiSource" 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Hotkeys Tests/BabelOtterKitTests/Hotkeys .github/workflows/mutation.yml
git commit -m "feat(hotkeys): find a hotkey's key on the current keyboard layout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `HotKeyPlan`

**Files:**
- Create: `Sources/BabelOtterKit/Hotkeys/HotKeyPlan.swift`
- Modify: `.github/workflows/mutation.yml`
- Test: `Tests/BabelOtterKitTests/Hotkeys/HotKeyPlanTests.swift`

**Interfaces:**
- Consumes: `HotKeyBindings` (Task 1), `HotKeySpec`, `HotKeyProblem` (Task 2), `KeyLayout`, `sameKeys(as:)` (Task 3).
- Produces: `public struct HotKeyIssue { let action: Action; let text: String; let problem: HotKeyProblem; var description: String }`; `public struct HotKeyPlan { let combinations: [Action: HotKeyCombination]; let issues: [HotKeyIssue]; static let actions: [Action]; static let launchCombinations: [Action: HotKeyCombination]; static func make(bindings: HotKeyBindings?, previous: [Action: HotKeyCombination], layout: KeyLayout) -> HotKeyPlan }`.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Hotkeys/HotKeyPlanTests.swift`:

```swift
import Testing

@testable import BabelOtterKit

@Suite("The hotkeys to register, keeping what works")
struct HotKeyPlanTests {

    private let launch = HotKeyPlan.launchCombinations
    private let us = KeyLayoutTests.us
    private let swiss = KeyLayoutTests.swissGerman

    private func plan(
        _ translate: HotKeyBinding = .useDefault, _ correct: HotKeyBinding = .useDefault,
        previous: [Action: HotKeyCombination]? = nil, layout: KeyLayout? = nil
    ) -> HotKeyPlan {
        HotKeyPlan.make(
            bindings: HotKeyBindings(translate: translate, correct: correct),
            previous: previous ?? launch, layout: layout ?? us)
    }

    @Test("the launch combinations are the ones registered before #26")
    func launchCombinations() {
        #expect(launch[.translate] == HotKeyCombination(
            keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-T"))
        #expect(launch[.correct] == HotKeyCombination(
            keyCode: 0x08, modifiers: 0x1800, displayName: "Control-Option-C"))
        #expect(HotKeyPlan.actions == [.translate, .correct])
    }

    @Test("no hotkeys field gives both defaults and no issues")
    func noField() {
        let result = HotKeyPlan.make(bindings: nil, previous: [:], layout: us)
        #expect(result.combinations == launch)
        #expect(result.issues.isEmpty)
    }

    @Test("off leaves that action without a hotkey, and is no issue")
    func off() {
        let result = plan(.useDefault, .off)
        #expect(result.combinations[.correct] == nil)
        #expect(result.combinations[.translate] != nil)
        #expect(result.issues.isEmpty)
    }

    @Test("a typo keeps the previous hotkey and names the problem")
    func typoKeepsPrevious() {
        let result = plan(.text("contrl+option+T"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.issues == [HotKeyIssue(
            action: .translate, text: "contrl+option+T", problem: .unknownPart("contrl"))])
        #expect(result.issues[0].description
            == "translate hotkey \"contrl+option+T\": unknown key or modifier \"contrl\"")
    }

    @Test("a typo with nothing previous leaves no hotkey")
    func typoWithoutPrevious() {
        let result = plan(.text("contrl+option+T"), previous: [:])
        #expect(result.combinations[.translate] == nil)
        #expect(result.issues.count == 1)
    }

    @Test("a character missing from the layout keeps the previous hotkey")
    func notOnLayoutKeepsPrevious() {
        let result = plan(.text("control+option+\u{FC}"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.issues[0].problem == .notOnLayout("\u{FC}"))
    }

    @Test("both on one combination: Translate gets it, Correct keeps its previous one")
    func duplicate() {
        let result = plan(.text("control+option+T"), .text("control+option+T"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.combinations[.correct] == launch[.correct])
        #expect(result.issues == [HotKeyIssue(
            action: .correct, text: "control+option+T", problem: .sharedWith(.translate))])
        #expect(result.issues[0].description
            == "correct hotkey \"control+option+T\": is also the Translate hotkey")
    }

    @Test("a duplicate whose previous combination Translate has taken leaves Correct with none")
    func duplicateOfPrevious() {
        let result = plan(.text("control+option+C"), .text("control+option+C"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct] == nil)
    }

    @Test("a Correct typo keeps its previous combination only if Translate has not taken it")
    func typoKeepsPreviousOnlyIfFree() {
        let result = plan(.text("control+option+C"), .text("contrl+option+X"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct] == nil)
        #expect(result.issues.count == 1)
    }

    @Test("swapping the two combinations in one save is no duplicate")
    func swapIsNoDuplicate() {
        let result = plan(.text("control+option+C"), .text("control+option+T"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct]?.keyCode == 0x11)
        #expect(result.issues.isEmpty)
    }

    @Test("a layout change moves a character key to where the layout types it")
    func layoutChange() {
        let onUS = plan(.text("control+option+Z"))
        let onSwiss = plan(.text("control+option+Z"), previous: onUS.combinations, layout: swiss)
        #expect(onUS.combinations[.translate]?.keyCode == 0x06)
        #expect(onSwiss.combinations[.translate]?.keyCode == 0x10)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HotKeyPlanTests 2>&1 | tail -5`
Expected: build failure, "cannot find 'HotKeyPlan' in scope".

- [ ] **Step 3: Write `HotKeyPlan.swift`**

```swift
import Foundation

/// A hotkey from config.json that is not used as written.
public struct HotKeyIssue: Sendable, Equatable {
    public let action: Action
    /// As written in the file.
    public let text: String
    public let problem: HotKeyProblem

    public init(action: Action, text: String, problem: HotKeyProblem) {
        self.action = action
        self.text = text
        self.problem = problem
    }

    /// `translate hotkey "contrl+option+T": unknown key or modifier "contrl"`,
    /// shown after "config.json: " in the menu.
    public var description: String {
        "\(action.rawValue) hotkey \"\(text)\": \(problem.detail)"
    }
}

/// Which combination each action gets, decided from the file, what is in
/// use, and the keyboard layout (#26).
///
/// A hotkey that cannot be used as written keeps the one in use, so a typo
/// never takes a working hotkey away. Written as loops and switches rather
/// than closures: muter drops mutants inside closures.
public struct HotKeyPlan: Sendable, Equatable {
    /// An action absent here has no hotkey.
    public let combinations: [Action: HotKeyCombination]
    public let issues: [HotKeyIssue]

    /// The actions with hotkeys, in the order they are decided: Translate
    /// first, so it wins a duplicate.
    public static let actions: [Action] = [.translate, .correct]

    /// What babelOtter registered before #26, and what is in use before the
    /// first plan: kVK_ANSI_T and kVK_ANSI_C with controlKey | optionKey.
    public static let launchCombinations: [Action: HotKeyCombination] = [
        .translate: HotKeyCombination(keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-T"),
        .correct: HotKeyCombination(keyCode: 0x08, modifiers: 0x1800, displayName: "Control-Option-C"),
    ]

    public static func make(
        bindings: HotKeyBindings?, previous: [Action: HotKeyCombination], layout: KeyLayout
    ) -> HotKeyPlan {
        let written = bindings ?? HotKeyBindings()
        var combinations: [Action: HotKeyCombination] = [:]
        var issues: [HotKeyIssue] = []
        for action in actions {
            guard let text = text(for: written.binding(for: action), action: action) else {
                continue
            }
            switch resolve(text, layout: layout) {
            case .success(let combination):
                if let owner = owner(of: combination, in: combinations) {
                    issues += [HotKeyIssue(action: action, text: text, problem: .sharedWith(owner))]
                    keepPrevious(for: action, from: previous, into: &combinations)
                } else {
                    combinations[action] = combination
                }
            case .failure(let problem):
                issues += [HotKeyIssue(action: action, text: text, problem: problem)]
                keepPrevious(for: action, from: previous, into: &combinations)
            }
        }
        return HotKeyPlan(combinations: combinations, issues: issues)
    }

    /// Nil when the hotkey is off.
    private static func text(for binding: HotKeyBinding, action: Action) -> String? {
        switch binding {
        case .off:
            return nil
        case .useDefault:
            return HotKeyBindings.defaultText(for: action)
        case .text(let text):
            return text
        }
    }

    private static func resolve(_ text: String, layout: KeyLayout) -> Result<HotKeyCombination, HotKeyProblem> {
        switch HotKeySpec.parse(text) {
        case .success(let spec):
            return layout.resolve(spec)
        case .failure(let problem):
            return .failure(problem)
        }
    }

    private static func owner(
        of combination: HotKeyCombination, in combinations: [Action: HotKeyCombination]
    ) -> Action? {
        for action in actions {
            if let taken = combinations[action] {
                if taken.sameKeys(as: combination) {
                    return action
                }
            }
        }
        return nil
    }

    /// The previous combination, unless another action now holds it.
    private static func keepPrevious(
        for action: Action, from previous: [Action: HotKeyCombination],
        into combinations: inout [Action: HotKeyCombination]
    ) {
        guard let kept = previous[action] else { return }
        if owner(of: kept, in: combinations) == nil {
            combinations[action] = kept
        }
    }
}
```

Insert `          Sources/BabelOtterKit/Hotkeys/HotKeyPlan.swift` into the PASS1 list after `Hotkeys/HotKeySpec.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "HotKeyPlanTests|AsciiSource" 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Hotkeys Tests/BabelOtterKitTests/Hotkeys .github/workflows/mutation.yml
git commit -m "feat(hotkeys): plan the hotkeys, keeping the one in use when text fails

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `ConfigurationReload`

**Files:**
- Create: `Sources/BabelOtterKit/Config/ConfigurationReload.swift`
- Modify: `.github/workflows/mutation.yml`
- Test: `Tests/BabelOtterKitTests/Config/ConfigurationReloadTests.swift`

**Interfaces:**
- Consumes: `Configuration`, `LoadedConfiguration`, `ConfigurationProblem`, `ConfigurationStore.fileName` (exist).
- Produces: `public struct ConfigurationReloadResult { let configuration: Configuration; let problems: [ConfigurationProblem] }`; `public enum ConfigurationReload { static let keptNote: String; static func apply(previous:loaded:fileExists:isLaunch:) -> ConfigurationReloadResult }`; `extension ConfigurationProblem { var summary: String }`.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Config/ConfigurationReloadTests.swift`:

```swift
import Testing

@testable import BabelOtterKit

@Suite("A reload keeps what works")
struct ConfigurationReloadTests {

    private let problem = ConfigurationProblem(
        file: "config.json", field: "retentionDays", detail: "expected Int, found something else")

    private var previous: Configuration {
        var configuration = Configuration.default
        configuration.retentionDays = 30
        return configuration
    }

    private var edited: Configuration {
        var configuration = Configuration.default
        configuration.retentionDays = 7
        return configuration
    }

    @Test("a clean file replaces the configuration in use")
    func cleanReplaces() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: edited, problems: []),
            fileExists: true, isLaunch: false)
        #expect(result.configuration == edited)
        #expect(result.problems.isEmpty)
    }

    @Test("at launch a broken file gives the defaults and its problems, as before")
    func brokenAtLaunch() {
        let result = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: true)
        #expect(result.configuration == .default)
        #expect(result.problems == [problem])
    }

    @Test("on reload a broken file keeps the configuration in use and says so")
    func brokenOnReload() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: false)
        #expect(result.configuration == previous)
        #expect(result.problems == [ConfigurationProblem(
            file: "config.json", field: "retentionDays",
            detail: "expected Int, found something else - still using the previous settings")])
    }

    @Test("a fixed file clears the problems a launch reported")
    func fixedFileClearsProblems() {
        let launch = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: true)
        let fixed = ConfigurationReload.apply(
            previous: launch.configuration, loaded: LoadedConfiguration(configuration: edited, problems: []),
            fileExists: true, isLaunch: false)
        #expect(fixed.configuration == edited)
        #expect(fixed.problems.isEmpty)
    }

    @Test("a file deleted while running keeps the configuration in use")
    func missingOnReload() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: .default, problems: []),
            fileExists: false, isLaunch: false)
        #expect(result.configuration == previous)
        #expect(result.problems == [ConfigurationProblem(
            file: "config.json", field: nil,
            detail: "the file is missing - still using the previous settings")])
    }

    @Test("no file at launch is a first launch, not a problem")
    func missingAtLaunch() {
        let result = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: []),
            fileExists: false, isLaunch: true)
        #expect(result.configuration == .default)
        #expect(result.problems.isEmpty)
    }

    @Test("a summary names the field when there is one")
    func summary() {
        #expect(problem.summary == "retentionDays: expected Int, found something else")
        #expect(ConfigurationProblem(file: "config.json", field: nil, detail: "not JSON").summary
            == "not JSON")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigurationReloadTests 2>&1 | tail -5`
Expected: build failure, "cannot find 'ConfigurationReload' in scope".

- [ ] **Step 3: Write `ConfigurationReload.swift`**

```swift
import Foundation

public struct ConfigurationReloadResult: Sendable, Equatable {
    public let configuration: Configuration
    public let problems: [ConfigurationProblem]
}

/// What a load of config.json changes (#26).
///
/// `ConfigurationStore.load()` is all-or-nothing: one wrong value gives the
/// defaults for everything. At launch that is the only option. Mid-session
/// it would throw away a working glossary over a missing comma, so a reload
/// with problems keeps the configuration in use and says so.
public enum ConfigurationReload {

    public static let keptNote = " - still using the previous settings"

    /// `fileExists` because `load()` treats a missing file as a first launch,
    /// which is wrong once babelOtter is running.
    public static func apply(
        previous: Configuration, loaded: LoadedConfiguration, fileExists: Bool, isLaunch: Bool
    ) -> ConfigurationReloadResult {
        if !isLaunch {
            if !fileExists {
                let missing = ConfigurationProblem(
                    file: ConfigurationStore.fileName, field: nil, detail: "the file is missing" + keptNote)
                return ConfigurationReloadResult(configuration: previous, problems: [missing])
            }
        }
        if loaded.problems.isEmpty {
            return ConfigurationReloadResult(configuration: loaded.configuration, problems: [])
        }
        if isLaunch {
            return ConfigurationReloadResult(configuration: loaded.configuration, problems: loaded.problems)
        }
        var kept: [ConfigurationProblem] = []
        for problem in loaded.problems {
            kept += [ConfigurationProblem(
                file: problem.file, field: problem.field, detail: problem.detail + keptNote)]
        }
        return ConfigurationReloadResult(configuration: previous, problems: kept)
    }
}

extension ConfigurationProblem {
    /// "retentionDays: expected Int, found something else", shown after
    /// "config.json: " in the menu.
    public var summary: String {
        if let field {
            return "\(field): \(detail)"
        }
        return detail
    }
}
```

Insert `          Sources/BabelOtterKit/Config/ConfigurationReload.swift` into the PASS1 list after `Config/Configuration.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ConfigurationReloadTests|AsciiSource" 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Config Tests/BabelOtterKitTests/Config .github/workflows/mutation.yml
git commit -m "feat(config): a reload with problems keeps the configuration in use

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Configuration problems as a readiness cause

**Files:**
- Modify: `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift` (`performRemedy`)
- Test: `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift`

**Interfaces:**
- Produces: `ReadinessCause.configurationProblem(String)`; `ReadinessRemedy.showConfiguration`; `ReadinessFacts.configurationProblems: [String]` (init parameter, default `[]`, last).

- [ ] **Step 1: Write the failing tests**

In `ReadinessPolicyTests`, add `configurationProblems: [String] = []` as the last parameter of the private `facts(...)` helper and pass `configurationProblems: configurationProblems` to `ReadinessFacts`. Append before the suite's closing brace:

```swift
    // MARK: - Configuration problems (#26)

    @Test("a configuration problem is degraded, names the file, and offers the file")
    func configurationProblemCause() {
        let cause = ReadinessCause.configurationProblem("retentionDays: expected Int")
        #expect(cause.readiness == .degraded)
        #expect(cause.header == "config.json: retentionDays: expected Int")
        #expect(cause.detail == "config.json: retentionDays: expected Int")
        #expect(cause.remedy == .showConfiguration)
        #expect(ReadinessRemedy.showConfiguration.title == "Show config.json in Finder")
    }

    @Test("configuration problems come after Accessibility and before the daemon, in order")
    func configurationProblemOrder() {
        let report = policy.report(for: facts(
            accessibility: false, probe: .unreachable(detail: "refused"),
            configurationProblems: ["a", "b"]))
        #expect(report.causes == [
            .accessibilityMissing,
            .configurationProblem("a"),
            .configurationProblem("b"),
            .ollamaUnreachable(detail: "refused"),
        ])
    }

    @Test("a configuration problem alone is degraded")
    func configurationProblemAlone() {
        let report = policy.report(for: facts(configurationProblems: ["x"]))
        #expect(report.readiness == .degraded)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReadinessPolicyTests 2>&1 | tail -5`
Expected: build failure, "extra argument 'configurationProblems'" or "has no member 'configurationProblem'".

- [ ] **Step 3: Implement in `ReadinessPolicy.swift`**

`ReadinessFacts`: add the stored property `public let configurationProblems: [String]` with the doc comment `/// What is wrong with config.json, each worded to follow "config.json: ".`, add the parameter `configurationProblems: [String] = []` after `systemShortcuts:` in `init`, and assign it.

`ReadinessCause`: add `case configurationProblem(String)` after `case accessibilityMissing`. In `readiness`, add `.configurationProblem` to the `.degraded` case list. In `detail`, add:

```swift
        case .configurationProblem(let text):
            return "config.json: \(text)"
```

In the `header` extension, add the same:

```swift
        case .configurationProblem(let text):
            return "config.json: \(text)"
```

In `remedy`, add:

```swift
        case .configurationProblem:
            return .showConfiguration
```

`ReadinessRemedy`: add `case showConfiguration` and, in `title`:

```swift
        case .showConfiguration:
            return "Show config.json in Finder"
```

`ReadinessPolicy.report(for:)`: after the Accessibility block, add:

```swift
        for problem in facts.configurationProblems {
            causes += [.configurationProblem(problem)]
        }
```

and update its doc comment to "Order: Accessibility, configuration problems, then the daemon, then each action's model, then each action's hotkey."

- [ ] **Step 4: Handle the remedy in the app**

In `AppDelegate.performRemedy(_:)`, add:

```swift
        case .showConfiguration:
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/ch.babelotter/config.json")
            NSWorkspace.shared.activateFileViewerSelecting([file])
```

- [ ] **Step 5: Run the tests and the build**

Run: `swift test --filter "ReadinessPolicyTests|AsciiSource" 2>&1 | tail -3 && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -2`
Expected: tests pass; "Build complete!".

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(readiness): configuration problems are a cause, with Show config.json in Finder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Live configuration reload in the app

**Files:**
- Create: `Sources/BabelOtterApp/ConfigurationSource.swift`
- Create: `Sources/BabelOtterApp/ConfigurationWatcher.swift`
- Modify: `Sources/BabelOtterApp/AppEnvironment.swift` (replace the whole file)
- Modify: `Sources/BabelOtterApp/ReadinessMonitor.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `ConfigurationReload`, `ConfigurationProblem.summary` (Task 5); `ReadinessFacts.configurationProblems` (Task 6).
- Produces: `ConfigurationSource { configuration; problems: [String]; store: ConfigurationStore?; reload() }`; `ConfigurationWatcher(directory:file:) { onChange; start() -> Bool }`; `AppEnvironment(configuration:)`; `ReadinessMonitor(configuration:)`, `.update(configuration:)`, `.configurationProblems`; `AppDelegate.pushConfigurationProblems()`, `.configurationChanged()`, `.watchProblems`.

The app target has no unit tests; this task's gate is the warnings-as-errors build, the full kit suite, and a launch.

- [ ] **Step 1: Replace `AppEnvironment.swift`**

```swift
import BabelOtterKit
import Foundation

/// The configuration in use and the Ollama client built from it.
///
/// Rebuilt on every reload (#26). A popup takes the environment when it
/// opens and keeps it, so a save never changes a request already running.
struct AppEnvironment: Sendable {
    let configuration: Configuration
    let client: OllamaClient

    init(configuration: Configuration) {
        self.configuration = configuration
        client = OllamaClient.loopback(timeout: configuration.timeoutSeconds)
    }
}
```

In `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift`, change the comment's `AppEnvironment.load()` to `AppEnvironment(configuration:)`.

- [ ] **Step 2: Write `ConfigurationSource.swift`**

```swift
import BabelOtterKit
import Foundation

/// Where the configuration comes from, and what is wrong with it.
///
/// Reads `~/Library/Application Support/ch.babelotter/config.json`, writing
/// the defaults there on first launch so the file can be edited by hand
/// until settings exist (M3). Every failure falls back so the app still
/// starts; `problems` is what makes a fallback visible (NFR-P7, FR-CFG-03).
@MainActor
final class ConfigurationSource {

    private(set) var configuration: Configuration
    /// Each worded to follow "config.json: " in the menu. Empty when nothing
    /// is wrong.
    private(set) var problems: [String]
    /// Nil when the folder could not be prepared: nothing to reload then.
    let store: ConfigurationStore?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // NFR-P7: the directories iCloud Drive can sync on this machine.
        let locator = StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })
        do {
            let store = try ConfigurationStore.inApplicationSupport(locator: locator)
            let exists = FileManager.default.fileExists(atPath: store.fileURL.path)
            let result = ConfigurationReload.apply(
                previous: .default, loaded: store.load(), fileExists: exists, isLaunch: true)
            var problems = Self.summaries(result.problems)
            if !exists {
                do {
                    try store.save(result.configuration)
                } catch {
                    problems += ["using defaults - could not write the file (\(error.localizedDescription))"]
                }
            }
            self.store = store
            self.configuration = result.configuration
            self.problems = problems
        } catch {
            self.store = nil
            self.configuration = .default
            self.problems = ["using defaults - \(Self.describe(error))"]
        }
    }

    /// Re-reads the file. Problems replace the previous ones, so a save that
    /// fixes the file clears them.
    func reload() {
        guard let store else { return }
        let exists = FileManager.default.fileExists(atPath: store.fileURL.path)
        let result = ConfigurationReload.apply(
            previous: configuration, loaded: store.load(), fileExists: exists, isLaunch: false)
        configuration = result.configuration
        problems = Self.summaries(result.problems)
    }

    private static func summaries(_ problems: [ConfigurationProblem]) -> [String] {
        problems.map(\.summary)
    }

    /// "the configuration folder is inside an iCloud-synced location", or the
    /// system's own description for anything else.
    private static func describe(_ error: any Error) -> String {
        if let storageError = error as? StorageLocationError {
            switch storageError {
            case .iCloudSynced:
                return "the configuration folder is inside an iCloud-synced location"
            case .notAbsolute:
                return "the configuration path is not valid"
            }
        }
        return error.localizedDescription
    }
}
```

- [ ] **Step 3: Write `ConfigurationWatcher.swift`**

```swift
import Foundation

/// Calls `onChange` when config.json's content changes on disk (#26).
///
/// Two sources, because editors save two ways: writing a new file and
/// renaming it over the old one changes the folder (TextEdit and most
/// macOS editors); writing into the existing file changes only the file
/// (VS Code). The file source is re-armed after every settled change,
/// because a rename-over save leaves it watching the old, unlinked file.
@MainActor
final class ConfigurationWatcher {

    var onChange: (@MainActor () -> Void)?

    private let directory: URL
    private let file: URL
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pending: Task<Void, Never>?
    /// Seeded at creation, so babelOtter's own first-launch save is not a
    /// change.
    private var lastContents: Data?

    /// An editor's save is several events in a burst; this waits them out.
    private static let settle = Duration.milliseconds(300)

    init(directory: URL, file: URL) {
        self.directory = directory
        self.file = file
        lastContents = FileManager.default.contents(atPath: file.path(percentEncoded: false))
    }

    /// False when the folder cannot be watched: changes then need a restart.
    func start() -> Bool {
        guard let source = makeSource(directory, events: .write) else { return false }
        directorySource = source
        armFile()
        return true
    }

    private func armFile() {
        fileSource?.cancel()
        fileSource = makeSource(file, events: [.write, .extend, .delete, .rename])
    }

    private func makeSource(
        _ url: URL, events: DispatchSource.FileSystemEvent
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    private func settled() {
        armFile()
        let contents = FileManager.default.contents(atPath: file.path(percentEncoded: false))
        guard contents != lastContents else { return }
        lastContents = contents
        onChange?()
    }
}
```

- [ ] **Step 4: Let `ReadinessMonitor` take a new configuration**

In `ReadinessMonitor.swift`:

- Replace `private let models: [Action: String]` with `private var models: [Action: String]`.
- After `var hotKeys: [HotKeyFact] = []`, add:

```swift
    /// Set by `AppDelegate` at launch and on every reload.
    var configurationProblems: [String] = []
```

- Replace the `init(environment:)` with:

```swift
    init(configuration: Configuration) {
        client = OllamaClient.loopback(timeout: Self.probeTimeout)
        models = Self.models(for: configuration)
    }

    /// A reload changes the models checked from the next check on (#26).
    func update(configuration: Configuration) {
        models = Self.models(for: configuration)
    }

    /// Only the actions that exist are checked. One without a configured
    /// model falls back to the default, as the pipeline does.
    private static func models(for configuration: Configuration) -> [Action: String] {
        var models: [Action: String] = [:]
        for action in [Action.translate, .correct] {
            models[action] = configuration.models[action] ?? Configuration.defaultModel
        }
        return models
    }
```

- In `check()`, change the `ReadinessFacts(...)` call to pass `configurationProblems: configurationProblems` after `systemShortcuts: Self.systemShortcuts()`.

- [ ] **Step 5: Wire the reload into `AppDelegate`**

- Delete the `configLine` property and its doc comment.
- Replace

```swift
    private(set) var environment = AppEnvironment.load()
    private lazy var monitor = ReadinessMonitor(environment: environment)
```

with

```swift
    private let source = ConfigurationSource()
    private(set) lazy var environment = AppEnvironment(configuration: source.configuration)
    private lazy var monitor = ReadinessMonitor(configuration: source.configuration)
    private lazy var watcher: ConfigurationWatcher? = makeWatcher()
    /// Set once, when the configuration folder cannot be watched.
    private var watchProblems: [String] = []
```

- In `applicationDidFinishLaunching`, after `registerHotKeys()`, add `startWatching()` and `pushConfigurationProblems()`.
- In `buildMenu()`, delete the `if let note = environment.configurationNote { ... } else { ... }` block and the line `menu.addItem(configLine)`.
- Add, after `registerHotKeys()`:

```swift
    // MARK: - Configuration

    private func makeWatcher() -> ConfigurationWatcher? {
        guard let store = source.store else { return nil }
        return ConfigurationWatcher(directory: store.directory, file: store.fileURL)
    }

    private func startWatching() {
        guard let watcher else { return }
        watcher.onChange = { [weak self] in self?.configurationChanged() }
        if !watcher.start() {
            watchProblems = ["changes need a restart: the folder can't be watched"]
        }
    }

    /// Every saved change, applied in one place (#26). A popup already open
    /// keeps the environment it started with.
    private func configurationChanged() {
        source.reload()
        environment = AppEnvironment(configuration: source.configuration)
        monitor.update(configuration: source.configuration)
        pushConfigurationProblems()
        monitor.refresh()
    }

    private func pushConfigurationProblems() {
        monitor.configurationProblems = source.problems + watchProblems
    }
```

- [ ] **Step 6: Build and run the suite**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -2 && swift test 2>&1 | tail -1`
Expected: "Build complete!"; "Test run with N tests in M suites passed".

- [ ] **Step 7: Launch check**

Run: `Tools/make-app.sh >/dev/null && pkill -x babelOtter; open build/babelOtter.app && sleep 3 && pgrep -x babelOtter`
Expected: a process id. Then change `"retentionDays"` in `~/Library/Application Support/ch.babelotter/config.json` to the string `"x"`, wait 2 s, and restore it — only if the user is present to look; otherwise leave it to manual check H2 and say so.

- [ ] **Step 8: Commit**

```bash
git add Sources/BabelOtterApp
git commit -m "feat(app): reload config.json on every save, keeping the settings in use on a bad one

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Hotkeys from the configuration, on the current layout

**Files:**
- Create: `Sources/BabelOtterApp/KeyboardLayoutReader.swift`
- Modify: `Sources/BabelOtterApp/HotKey.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `HotKeyPlan`, `HotKeyIssue` (Task 4); `KeyLayout`, `sameKeys(as:)` (Task 3); `pushConfigurationProblems()`, `configurationChanged()` (Task 7).
- Produces: `KeyboardLayoutReader { onChange; start(); static func current() -> KeyLayout }`; `HotKey.unregister()`.

- [ ] **Step 1: Add `unregister()` to `HotKey`**

Add `private let id: UInt32` below `private var reference: EventHotKeyRef?`; in `init?`, set `self.id = id` as the first statement. Add:

```swift
    /// Releases the registration (#26). Explicit rather than `deinit`: a
    /// deinit cannot reach main-actor state under Swift 6.1, and a hotkey
    /// left registered would keep firing under its old combination.
    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        reference = nil
        Self.actions[id] = nil
    }
```

- [ ] **Step 2: Write `KeyboardLayoutReader.swift`**

```swift
import BabelOtterKit
import Carbon.HIToolbox
import Foundation

/// What each key types on the keyboard layout in use, and when that layout
/// changes (#26).
@MainActor
final class KeyboardLayoutReader {

    var onChange: (@MainActor () -> Void)?
    private var observer: (any NSObjectProtocol)?

    func start() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    /// The current layout; the ASCII-capable one when the current input
    /// source has no key layout (Japanese or Chinese input methods); the US
    /// letters when macOS reports neither.
    static func current() -> KeyLayout {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let characters = characters(of: source) {
                return KeyLayout(characters: characters)
            }
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let characters = characters(of: source) {
                return KeyLayout(characters: characters)
            }
        }
        return KeyLayout.usANSI
    }

    /// Key codes 0-127 with no modifiers. Keys that type nothing visible
    /// (function keys, dead keys) are left out. Read while `source` is alive,
    /// because the layout data belongs to it.
    private static func characters(of source: TISInputSource) -> [UInt32: String]? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var characters: [UInt32: String] = [:]
        for code in UInt16(0)..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                buffer.count, &length, &buffer)
            guard status == noErr, length > 0 else { continue }
            let typed = String(utf16CodeUnits: buffer, count: length)
            let visible = typed.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            guard !visible.isEmpty else { continue }
            characters[UInt32(code)] = typed
        }
        return characters
    }
}
```

- [ ] **Step 3: Replace the fixed hotkeys in `AppDelegate`**

- Delete the `translateCombination` and `correctCombination` static constants and the `hotKey` / `correctHotKey` properties. Add:

```swift
    private var hotKeys: [Action: HotKey] = [:]
    /// The combinations in use; the launch ones until the first plan, so a
    /// typo in the file at launch still leaves Control-Option-T and -C.
    private var combinations = HotKeyPlan.launchCombinations
    private var hotKeyIssues: [HotKeyIssue] = []
    private var actionItems: [Action: NSMenuItem] = [:]
    private let layoutReader = KeyboardLayoutReader()
```

- In `buildMenu()`, replace the two `menu.addItem(action("Translate Selection (...)", ...))` / `menu.addItem(action("Correct Selection (...)", ...))` calls with:

```swift
        let translateItem = action(Self.menuTitle(.translate, nil), #selector(translateSelectionAction))
        let correctItem = action(Self.menuTitle(.correct, nil), #selector(correctSelectionAction))
        actionItems = [.translate: translateItem, .correct: correctItem]
        menu.addItem(translateItem)
        menu.addItem(correctItem)
```

- Replace the whole `registerHotKeys()` method with:

```swift
    /// Registration stays non-exclusive; a failure reaches the menu as a
    /// cause (#26). Every changed hotkey is released before any is
    /// registered, so Translate and Correct can swap combinations in one save.
    private func updateHotKeys() {
        let plan = HotKeyPlan.make(
            bindings: source.configuration.hotkeys, previous: combinations,
            layout: KeyboardLayoutReader.current())
        let changed = changedActions(to: plan.combinations)
        for action in changed {
            hotKeys[action]?.unregister()
            hotKeys[action] = nil
        }
        for action in changed {
            guard let combination = plan.combinations[action] else { continue }
            hotKeys[action] = HotKey(
                keyCode: combination.keyCode, modifiers: combination.modifiers,
                id: Self.hotKeyID(action)
            ) { [weak self] in self?.startAction(action) }
        }
        combinations = plan.combinations
        hotKeyIssues = plan.issues
        for action in HotKeyPlan.actions {
            actionItems[action]?.title = Self.menuTitle(action, combinations[action])
        }
        var facts: [HotKeyFact] = []
        for action in HotKeyPlan.actions {
            if let combination = combinations[action] {
                facts.append(HotKeyFact(
                    action: action, combination: combination, registered: hotKeys[action] != nil))
            }
        }
        monitor.hotKeys = facts
    }

    /// An action whose keys are the same and still registered is left alone;
    /// one whose registration failed is retried.
    private func changedActions(to wanted: [Action: HotKeyCombination]) -> [Action] {
        var changed: [Action] = []
        for action in HotKeyPlan.actions {
            let new = wanted[action]
            if let old = combinations[action], let new, old.sameKeys(as: new), hotKeys[action] != nil {
                continue
            }
            if combinations[action] == nil, new == nil, hotKeys[action] == nil {
                continue
            }
            changed.append(action)
        }
        return changed
    }

    private static func hotKeyID(_ action: Action) -> UInt32 {
        switch action {
        case .translate: return 1
        case .correct: return 2
        case .explain: return 3
        case .repitch: return 4
        }
    }

    /// "Translate Selection (Control-Option-T)", or without the combination
    /// when the hotkey is off.
    private static func menuTitle(_ action: Action, _ combination: HotKeyCombination?) -> String {
        let base = "\(action.displayName) Selection"
        guard let combination else { return base }
        return "\(base) (\(combination.displayName))"
    }

    private func layoutChanged() {
        updateHotKeys()
        pushConfigurationProblems()
        monitor.refresh()
    }
```

- In `applicationDidFinishLaunching`, replace `registerHotKeys()` with `updateHotKeys()`, and after `startWatching()` add:

```swift
        layoutReader.onChange = { [weak self] in self?.layoutChanged() }
        layoutReader.start()
```

- In `configurationChanged()`, add `updateHotKeys()` after `monitor.update(configuration: source.configuration)`.
- In `pushConfigurationProblems()`, include the hotkey issues:

```swift
    private func pushConfigurationProblems() {
        var problems = source.problems + watchProblems
        for issue in hotKeyIssues {
            problems.append(issue.description)
        }
        monitor.configurationProblems = problems
    }
```

- [ ] **Step 4: Build and run the suite**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -2 && swift test 2>&1 | tail -1`
Expected: "Build complete!"; all tests pass.

- [ ] **Step 5: Launch check**

Run: `Tools/make-app.sh >/dev/null && pkill -x babelOtter; open build/babelOtter.app && sleep 3 && pgrep -x babelOtter`
Expected: a process id. The visible behaviour is manual checks H1–H10 (Task 9).

- [ ] **Step 6: Commit**

```bash
git add Sources/BabelOtterApp
git commit -m "feat(app): hotkeys from config.json on the current keyboard layout, applied without a restart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Hand over

**Files:**
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: Add the update and the manual checks**

Insert after the `Read this first...` line, above `## Update 2026-10-12: closing M1b`:

```markdown
## Update 2026-10-12: hotkeys are configurable and config.json reloads live (#26)

Hotkeys are set in `config.json` under `hotkeys` (`"translate": "control+option+T"`, `null` for none) and resolved through the current keyboard layout. Every save to `config.json` applies within about half a second; a broken file or hotkey keeps what was in use and shows as a readiness cause with **Show config.json in Finder**. Design: `docs/superpowers/specs/2026-10-12-configurable-hotkeys-design.md`.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| H1 | Change `translate` to `control+option+Y` and save | Within a second the menu reads "Translate Selection (Control-Option-Y)"; Control-Option-Y translates; Control-Option-T no longer does |
| H2 | Save `config.json` with a missing comma | Triangle; header "config.json: … still using the previous settings" with "Show config.json in Finder"; translating still works. Fix it: ready |
| H3 | Set `translate` to `contrl+option+T` | Triangle; the header names "contrl"; Control-Option-T still translates |
| H4 | On the Swiss German layout, set `translate` to `control+option+Z` and press the key labelled Z; switch to the US layout and press the key labelled Z | It translates both times |
| H5 | Set `correct` to `null` | The menu item reads "Correct Selection"; Control-Option-C does nothing |
| H6 | Set both to `control+option+T` | Header "…is also the Translate hotkey"; Control-Option-C still corrects |
| H7 | Change `models.translate` to a model that is not installed | Within a second, triangle and "Translate: … isn't installed" |
| H8 | Move `config.json` to the Desktop, then back | Header "config.json: the file is missing…", then ready again |
| H9 | Edit `config.json` once in TextEdit and once in VS Code | Both saves apply |
| H10 | Swap the two hotkeys in one save | Control-Option-C translates and Control-Option-T corrects; no "is also" header |
```

- [ ] **Step 2: Commit**

```bash
git add docs/HANDOFF.md
git commit -m "docs: hand over configurable hotkeys, with manual checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
