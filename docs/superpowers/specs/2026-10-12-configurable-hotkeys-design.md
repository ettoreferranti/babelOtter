# Configurable hotkeys and live configuration — design

**Status:** approved in conversation 2026-10-12, pending review of this document.
**Milestone:** M1b Translate UX. **Covers:** #26 (epic #3): Translate and Correct each get an assignable hotkey that takes effect without a restart.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, sections 4.9 (`FR-UI-01`) and 4.11 (`FR-CFG-01`, `FR-CFG-03`). Builds on `2026-10-06-readiness-design.md`.

## 1. What it does

- **Hotkeys are set in `config.json`**, as text you can read: `"translate": "control+option+T"`. `null` turns one off.
- **Every saved change takes effect within about half a second**, without a restart: hotkeys, models, timeout, languages, profiles, glossary, do-not-translate list. A popup that is already open finishes with the settings it started with.
- **The letter you write is the key you press** on the keyboard layout you are using. On Swiss German, `Z` is the key labelled Z, not the US Y position. Switching layout re-registers the hotkeys.
- **A mistake never costs what was working.** A file that cannot be read keeps the settings in use; a hotkey that cannot be read keeps that action's hotkey in use. Each problem is named in the menu, with **Show config.json in Finder** under it, and the icon shows degraded until it is fixed.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Where hotkeys are assigned | `config.json`, field `hotkeys` | Matches how everything else is configured in M1b. The settings window (#61, M3) later writes the same field |
| What reloads | The whole configuration, not only hotkeys | The watcher is the cost, and it is paid either way. Popups already copy the configuration when they open, so swapping it is safe |
| Unreadable file on reload | Keep the settings in use, report file and field | `ConfigurationStore.load()` is all-or-nothing: one wrong value falls back to defaults for everything. Mid-session that would throw away a working glossary over a missing comma. At launch, with nothing to keep, defaults apply as today |
| Unreadable hotkey | That action keeps the hotkey in use, and the problem is reported | Same rule as the file. A typo does not take the hotkey away |
| Key mapping | Through the current keyboard layout | Carbon registers key positions. US positions would put `Z`, `Y` and all punctuation on the wrong key on a Swiss German keyboard |
| Hotkeys in older files | `hotkeys` is optional; absent means Control-Option-T and Control-Option-C | Every field is required today, so a new required field would make every existing file fall back to defaults |
| Where problems show | A readiness cause, `configurationProblem` | Same pattern as the other causes: a header and the command that helps. Replaces the plain configuration line in the menu |

## 3. The file

```json
"hotkeys" : {
  "correct" : "control+option+C",
  "translate" : "control+option+T"
}
```

- **Format:** modifiers and one key, joined by `+`, in any order, case-insensitive, whitespace around parts ignored.
- **Modifiers:** `control` / `ctrl`, `option` / `alt`, `command` / `cmd`, `shift`. At least one of control, option or command is required: shift alone with a key would fire on every capital.
- **Key:** a single character (letter, digit, punctuation, or a letter such as `ü` on layouts that have it), or a named key: `f1`–`f20`, `space`, `return`, `tab`, `escape`, `delete`, `left`, `right`, `up`, `down`. `+` itself cannot be the key.
- **`null`** turns the hotkey off; the menu item then shows no combination.
- **Absent action or absent `hotkeys`:** the default for that action.
- `Configuration.default` writes both defaults out, so a first-launch file shows the field.

## 4. Kit (`BabelOtterKit`) — pure, test-first, mutation-gated

All new files go into the mutation workflow's PASS1 list. ASCII-only sources, no UI or Carbon imports, no closures, comma-conjunctions or ternaries over enums (muter traps).

### 4.1 `HotKeyBindings` — `Sources/BabelOtterKit/Config/HotKeyBindings.swift`

The raw text from the file, per action.

- `public enum HotKeyBinding: Sendable, Equatable { case useDefault, off, text(String) }`.
- `public struct HotKeyBindings: Sendable, Equatable, Codable` holding `translate` and `correct` as `HotKeyBinding`. Custom coding: a missing key decodes as `.useDefault`, JSON `null` as `.off`, a string as `.text`. Encoding writes `.off` as `null`, `.text` as the string, and omits `.useDefault`.
- `public static let defaults` = `.text("control+option+T")`, `.text("control+option+C")`.
- `Configuration` gains `public var hotkeys: HotKeyBindings?`. Optional, so the synthesized decoding accepts a file without it; `nil` means `.useDefault` for both. `Configuration.default` sets `HotKeyBindings.defaults`.

### 4.2 `HotKeySpec` — `Sources/BabelOtterKit/Hotkeys/HotKeySpec.swift`

`HotKeySpec.parse(_ text: String) -> Result<HotKeySpec, HotKeyProblem>`.

- `HotKeySpec { modifiers: UInt32; key: HotKeyKey }`, modifiers as Carbon bits written as literals: command `0x100`, shift `0x200`, option `0x800`, control `0x1000`.
- `HotKeyKey`: `.character(String)` (lowercased, one extended grapheme) or `.named(NamedKey)`. Each `NamedKey` carries its fixed virtual key code (`kVK_F1` `0x7A` … `kVK_F20` `0x5A`, space `0x31`, return `0x24`, tab `0x30`, escape `0x35`, delete `0x33`, left `0x7B`, right `0x7C`, down `0x7D`, up `0x7E`), written as literals.
- `HotKeyProblem`, each with a `detail` worded for the menu:
  - `.empty` — "is empty";
  - `.unknownPart(String)` — "unknown key or modifier "contrl"";
  - `.noKey` — "names no key";
  - `.severalKeys` — "names more than one key";
  - `.needsModifier` — "needs control, option or command";
  - `.notOnLayout(String)` — ""ü" can't be typed on the current keyboard layout" (raised by 4.3);
  - `.sharedWith(Action)` — "is also the Translate hotkey" (raised by 4.4).
- `displayName(keyLabel:)` orders modifiers as macOS does — Control, Option, Shift, Command — joined with `-`: "Control-Option-Z", "Control-Shift-F5".

### 4.3 `KeyLayout` — `Sources/BabelOtterKit/Hotkeys/KeyLayout.swift`

- `public struct KeyLayout { public init(characters: [UInt32: String]) }`: what each virtual key code types with no modifiers, as the app reads it from macOS.
- `resolve(_ spec: HotKeySpec) -> Result<HotKeyCombination, HotKeyProblem>`. Named keys use their fixed code. A character is matched case-insensitively against the table; if several codes type it, the lowest code wins, so the result is deterministic. No match is `.notOnLayout`.
- The display name uses the uppercased character, or the named key's label ("F5", "Space").

### 4.4 `HotKeyPlan` — `Sources/BabelOtterKit/Hotkeys/HotKeyPlan.swift`

`HotKeyPlan.make(bindings: HotKeyBindings?, previous: [Action: HotKeyCombination], layout: KeyLayout) -> HotKeyPlan`, with `combinations: [Action: HotKeyCombination]` (an action absent from it has no hotkey) and `problems: [HotKeyIssue]` (`action` + `HotKeyProblem` + the text as written).

For Translate, then Correct:

1. `.off` → no hotkey, no problem.
2. `.useDefault` → the default text; `.text(t)` → `t`.
3. Parse, then resolve. On any failure: keep `previous[action]` (none if there was none) and record the problem.
4. Duplicate: if Correct resolves to Translate's combination, Correct keeps its previous combination and records `.sharedWith(.translate)`. If that previous combination is also Translate's, Correct has none.

At launch `previous` is Control-Option-T (`0x11`, `0x1800`) and Control-Option-C (`0x08`, `0x1800`), the values registered today. A layout change re-runs `make` with the same bindings and the current combinations as `previous`.

### 4.5 `ConfigurationReload` — `Sources/BabelOtterKit/Config/ConfigurationReload.swift`

`ConfigurationReload.apply(previous: Configuration, loaded: LoadedConfiguration, fileExists: Bool, isLaunch: Bool) -> (configuration: Configuration, problems: [ConfigurationProblem])`. `fileExists` is needed because `ConfigurationStore.load()` returns defaults with no problem for a missing file, which is right at first launch and wrong on reload.

- No problems in `loaded`: use `loaded.configuration`.
- Problems, at launch: use `loaded.configuration` (the defaults), report the problems — today's behaviour.
- Problems, on reload: keep `previous`, report the problems with " - still using the previous settings" appended to each detail.
- `fileExists == false` on reload is a problem ("config.json is missing - still using the previous settings"), not a first launch. The file is not recreated while running.

### 4.6 Readiness

- `ReadinessCause.configurationProblem(String)`: `.degraded`; `header` is "config.json: " + the text (the field and detail, or the hotkey issue: "translate hotkey "contrl+option+T": unknown key or modifier "contrl""); `detail` is the same text; `remedy` is `.showConfiguration`.
- `ReadinessRemedy.showConfiguration`, titled "Show config.json in Finder".
- `ReadinessFacts` gains `configurationProblems: [String]`. `ReadinessPolicy` orders causes: Accessibility, configuration problems, daemon, models, hotkeys.

## 5. App (`BabelOtterApp`) — checked by use

### 5.1 `ConfigurationWatcher` — `Sources/BabelOtterApp/ConfigurationWatcher.swift`

- Two `DispatchSource` file-system sources (`O_EVTONLY`): one on the configuration **folder** (`.write`), which sees a save that writes a new file and renames it over the old one (TextEdit, most macOS editors); and one on **`config.json` itself** (`.write`, `.extend`, `.delete`, `.rename`), which sees a save that writes into the existing file (VS Code, vim with some settings) and leaves the folder untouched. The file source is re-armed after every settled change, because a rename-over save leaves it watching the old, unlinked file.
- Debounced: a change starts a 300 ms timer; further changes restart it. Then it reads `config.json`'s bytes and calls `onChange` only if they differ from the last bytes seen. The launch load seeds those bytes, so babelOtter's own first-launch save does not trigger a reload.
- If the folder cannot be opened, it reports that once, as the configuration problem "changes need a restart: the folder can't be watched".

### 5.2 `KeyboardLayoutReader` — `Sources/BabelOtterApp/KeyboardLayoutReader.swift`

- `current() -> KeyLayout`: `TISCopyCurrentKeyboardLayoutInputSource`, falling back to `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` when the source has no `kTISPropertyUnicodeKeyLayoutData` (Japanese or Chinese input methods). For key codes 0–127, `UCKeyTranslate` with no modifiers and `kUCKeyActionDisplay`; empty results and dead keys are left out.
- Observes `kTISNotifySelectedKeyboardInputSourceChanged` through `DistributedNotificationCenter` and calls `onChange`.

### 5.3 `HotKey`

- Gains `unregister()`, calling `UnregisterEventHotKey` and removing its entry from `actions`. Today a registration is never released, so a changed hotkey would keep firing under its old combination. An explicit call rather than `deinit`: a `deinit` cannot reach main-actor state under Swift 6.1, which CI builds with, and `isolated deinit` needs 6.2.

### 5.4 `ConfigurationSource` — `Sources/BabelOtterApp/ConfigurationSource.swift`

Takes over the loading `AppEnvironment.load()` does today: the store, the first-launch save, the storage-location notes. It holds the configuration in use and its problems as summaries (`"retentionDays: expected Int, found something else"`), and `reload()` runs `ConfigurationReload.apply` against the configuration in use. `AppEnvironment` shrinks to the configuration and the client built from it.

### 5.5 `AppDelegate`

One method, `apply(configuration:problems:plan:)`, used at launch, on a save and on a layout change:

1. `environment` becomes a new `AppEnvironment` with the configuration and a client built with its timeout. Popups take `environment` when they open, so an open popup is unaffected.
2. For the actions whose combination changed: release all their old `HotKey`s first, then register the new ones, so a combination never collides with a registration it is replacing, including when Translate and Correct swap combinations in one save. Unchanged ones are left alone.
3. The Translate and Correct menu items are retitled ("Translate Selection (Control-Option-Z)", or "Translate Selection" with no hotkey).
4. `ReadinessMonitor.update(models:hotKeys:configurationProblems:)` replaces what it copied at launch, then `refresh()` runs.

The configuration line in the menu is removed; its content is now a readiness cause. `HotKeyCombination` constants in `AppDelegate` are replaced by the plan's combinations.

## 6. Errors and edge cases

| Situation | Result | Shown as |
|---|---|---|
| Invalid JSON or a wrong type, on reload | Previous settings kept | config.json: `<field>`: `<detail>` - still using the previous settings |
| The same, at launch | Defaults, as today | config.json: `<field>`: `<detail>` |
| Hotkey typo | That action keeps its hotkey | config.json: translate hotkey "contrl+option+T": unknown key or modifier "contrl" |
| No control, option or command | That action keeps its hotkey | …needs control, option or command |
| Both on one combination | Correct keeps its previous one | …correct hotkey "control+option+T" is also the Translate hotkey |
| Character not on the current layout | That action keeps its hotkey | …"ü" can't be typed on the current keyboard layout |
| `null` | No hotkey; menu item without a combination | Nothing |
| Carbon refuses the registration | No hotkey for that action | Existing `hotKeyNotRegistered` |
| Clash with a system shortcut | Registered | Existing `hotKeyClashesWithSystem`, from the new combination |
| `config.json` deleted | Previous settings kept; not recreated | config.json is missing - still using the previous settings |
| Folder cannot be watched | Settings stay as at launch | config.json: changes need a restart: the folder can't be watched |
| Save during a capture or replacement | The environment swaps; the running action keeps its own copy | Nothing |
| Several saves within 300 ms | One reload, of the last content | Nothing |

Problems clear on the next save or layout change that removes their cause.

## 7. Testing

**Kit, unit tests:**

- `HotKeyBindingsTests`: absent key is `.useDefault`, `null` is `.off`, a string is `.text`; round trip; a `config.json` without `hotkeys` loads with no problems (added to `ConfigurationStoreTests`).
- `HotKeySpecTests`: every modifier spelling and order; case and whitespace; named keys and their codes; each `HotKeyProblem`; display order Control, Option, Shift, Command.
- `KeyLayoutTests`: a US table and a Swiss German table (Z at code `0x10`, Y at `0x06`); lowest code wins; `.notOnLayout`; named keys ignore the table.
- `HotKeyPlanTests`: defaults; `.off`; a typo keeps the previous combination; a typo with no previous gives none; duplicate keeps Correct's previous, or none; a layout change moves a character key.
- `ConfigurationReloadTests`: clean load replaces; problems at launch give defaults; problems on reload keep the previous configuration and append the note; missing file on reload.
- `ReadinessPolicyTests`: the new cause's readiness, header, detail and remedy; its position in the order.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| H1 | Change `translate` to `control+option+Y` and save | Within a second the menu reads "Translate Selection (Control-Option-Y)"; Control-Option-Y translates; Control-Option-T no longer does |
| H2 | Save `config.json` with a missing comma | Triangle; header "config.json: … still using the previous settings" with "Show config.json in Finder"; translating still works with the old settings. Fix it: ready |
| H3 | Set `translate` to `contrl+option+T` | Triangle; the header names "contrl"; Control-Option-T still translates |
| H4 | With the Swiss German layout, set `translate` to `control+option+Z`; press the key labelled Z. Switch to the US layout; press the key labelled Z | It translates both times |
| H5 | Set `correct` to `null` | The menu item reads "Correct Selection"; Control-Option-C does nothing |
| H6 | Set both to `control+option+T` | Header "…is also the Translate hotkey"; Control-Option-C still corrects |
| H7 | Change `models.translate` to a model that is not installed | Within a second, triangle and "Translate: … isn't installed" |
| H8 | Move `config.json` to the Desktop, then move it back | Header "config.json is missing…", then ready again |

## 8. Out of scope

- The settings window and a shortcut recorder (#61).
- Hotkeys for Explain (#65) and Re-pitch (#66): `HotKeyBindings` gains their fields with those stories.
- Rewriting `models` as a JSON object instead of the flat array the synthesized coding writes today.
