# Settings: the Audiences tab — design addendum

**Status:** approved in conversation 2026-10-21, pending review of this document.
**Covers:** the second settings PR of #61 (epic #11): editing the audience profiles (`FR-PRO-01`, `FR-PRO-02`). **Builds on:** `2026-10-20-settings-window-design.md`; everything there (the file stays the truth, refusals under the control, read-only while the file is broken) applies.

## 1. What it does

- A fourth tab, **Audiences**, between Models and Hotkeys: the audiences on the left in file order, the selected one on the right.
- **Fields:** Name; Register (Sie / du); Tone guidance (several lines); Preferred terms (one per line; blank lines dropped). A text field is written when you leave it or press Return (Command-Return in the multi-line ones), not on every keystroke. The audience's id is shown small and grey under the name.
- **Add (+):** a new audience named "New audience" (then "New audience 2", ...), Sie, with empty guidance and no terms, selected with its name ready to type over. Its id is made from the name it was created with.
- **Delete...:** asks "Delete <name>? Its tone guidance is lost." with Delete (destructive) and Cancel. The last audience cannot be deleted (the button is disabled).
- **Restore shipped audiences:** adds back, at the end, each of the four shipped audiences (Students, Colleagues, Administration, Informal) whose id is missing; your own audiences and edited shipped ones are not touched. Disabled when none is missing. A shipped audience whose name is now used by another audience is not restored, and the window says which.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| The id | Made once from the first name: lowercased, accents dropped, `ss` for an eszett, anything else not a-z or 0-9 becomes `-`; `audience` if nothing is left; `-2`, `-3`, ... if taken. Never changes on rename | App memory (`UserDefaults`) and history records refer to it; a readable id keeps `config.json` hand-editable (`FR-CFG-03`) |
| Names | Trimmed, not empty, at most 40 characters, unique ignoring case | Inference matches a model's answer by id and by name; two "Students" would be ambiguous |
| Deleting | Confirmation; never the last one; Restore brings back shipped ones | The guidance text is the work; an empty list leaves Translate without an audience to pick |
| What a deletion leaves behind | Nothing to clean up | An app's remembered audience that no longer exists is already skipped (`AudienceSession`); history shows a deleted audience by its id; with Colleagues gone the fallback is the first audience |
| Limits | Tone guidance at most 2,000 characters; at most 50 terms of at most 80 characters | Both go into every prompt for that audience; a local model's context is not free |

## 3. The kit

`SettingsEditor` gains, each refusing as before and leaving the configuration unchanged on refusal:

```swift
public mutating func addAudience(named name: String) throws -> String        // the new id
public mutating func renameAudience(_ id: String, to name: String) throws
public mutating func setRegister(_ register: Register, forAudience id: String) throws
public mutating func setToneGuidance(_ text: String, forAudience id: String) throws
public mutating func setPreferredTerms(_ lines: String, forAudience id: String) throws
public mutating func deleteAudience(_ id: String) throws
/// The shipped audiences added back, and those skipped for a name in use.
public mutating func restoreShippedAudiences() -> (restored: [String], skipped: [String])
```

New refusals: `.noSuchAudience(String)`, `.emptyName`, `.nameTooLong` ("At most 40 characters"), `.nameInUse(String)` ("Another audience is called <name>."), `.lastAudience` ("At least one audience stays."), and `.outOfRange` for the guidance and term limits.

`AudienceID.make(from name: String, taken: Set<String>) -> String` holds the id rule. As in the first PR, every accepted edit is checked to round-trip through the file encoding.

## 4. The app

- `AudiencesSettingsView` in `Sources/BabelOtterApp/Settings/`: a `List` with selection, + and Delete... under it, Restore shipped audiences below; the detail as a `Form`. Drafts for the text fields, written on leaving the field; a draft being typed is not reset by a reload (as in General).
- `SettingsField.audience(String, AudienceField)` for refusals per field.
- The Delete confirmation is a SwiftUI `.alert` on the tab.

## 5. Testing

- **`SettingsAudienceTests`**: add (default name, numbering, id from name, id collision, id stable after rename); rename (empty, 40 and 41 characters, a name in use in another case, its own name in another case allowed); register; guidance at 2,000 and 2,001 characters; terms (blank lines dropped, trimmed, 50 and 51 terms, an 81-character term); delete (unknown id, the last one); restore (nothing missing, two missing, one skipped for its name); every accepted edit round-trips.
- **`AudienceIDTests`**: "Students" gives `students`; "Behörden" gives `behorden`; "Straße" gives `strasse`; "Ü-Prüfung 2" gives `u-prufung-2`; "   " and "!!!" give `audience`; taken ids get `-2`, then `-3`.

### Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| A1 | Open Settings, Audiences | The four audiences in file order; Students selected shows its name, Sie, guidance and id `students` |
| A2 | Press +; type "Behörden", Return; set du; write two lines of guidance and leave the box | `config.json` has an audience with id `behorden`, name "Behörden", register "du" and the guidance |
| A3 | Rename "Behörden" to "Students"; then to "Ämter" | The first is refused ("Another audience is called Students."); the second is written and the id stays `behorden` |
| A4 | Translate an English text and pick the new audience in the popup | The translation uses the du register |
| A5 | Delete Students (confirm); then Restore shipped audiences | Students is gone from the popup's picker; Restore brings it back at the end |
| A6 | Delete audiences until one is left | Delete... is disabled for the last one |
