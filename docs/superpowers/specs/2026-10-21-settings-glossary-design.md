# Settings: the Glossary tab and a concept glossary — design addendum

**Status:** approved in conversation 2026-10-21, pending review of this document.
**Covers:** the third settings PR of #61 (epic #11), and #59 (`FR-GLO-01`, `FR-GLO-02`). **Builds on:** `2026-10-20-settings-window-design.md`; everything there applies (the file stays the truth, refusals under the control, read-only while the file is broken, closures rather than method references in views).

## 1. Why the glossary changes shape

Today a glossary entry is one direction: `module -> Modul` for English to Swiss Standard German says nothing about the reverse. With two languages that is two rows per term. With N languages it is up to N x (N - 1) rows per term, each kept consistent by hand: adding French would triple the work, and nothing ties `module` (en), `Modul` (de-CH) and `module` (fr) together as one term.

So the glossary becomes a **concept glossary**, as translation term bases are: one row per concept, one term per language. Translating from A to B uses every concept that has a term in both A and B. Adding a language adds a column, not rows. Direction-specific renderings ("Modul" into English as "course unit", but "module" into German as "Modul") are given up; they are rare, and a concept could later carry an "only when translating into X" limit if one is ever needed.

The rest of the app's two-language assumptions (Explain, Correct, picking a source, Swap, the golden set) are recorded as acceptance criteria on #81 and are not part of this PR.

## 2. What it does

- A fifth tab, **Glossary**, after Audiences, with two tables.
- **Terms (the glossary):** one column per configured language, by display name, in configuration order; one row per concept. Cells are edited in place and written when left. **+** adds an empty row, focused on its first cell; **-** at the end of a row deletes it. A row is written once it has a term in it; clearing its last term deletes it. A footnote: "A row is used when translating between two languages it has terms for."
- **Do not translate:** one term per row, edited in place; + and -. A footnote: "Matched exactly, capitals included: NORDA protects NORDA, not Norda."
- **Refusals** (under the table): a term longer than 80 characters; a term already in another row for the same language, ignoring case ("Modul is already in another row for Swiss Standard German."); more than 200 rows; a do-not-translate term already listed (exactly), longer than 80 characters, shorter than two characters ("a" would protect every "a"), containing the masking brackets ⟦ or ⟧, or past 100 terms. A refused value goes back to the saved one when the field is left; the reason stays shown.
- **Hidden languages kept:** a concept's term for a language that is not configured (say `fr`, written by hand) is not shown but is kept when the row is edited.

## 3. The file

```json
"glossary" : {
  "concepts" : [
    { "de-ch" : "Modul", "en" : "module" },
    { "de-ch" : "Leistungsnachweis", "en" : "credit" }
  ]
}
```

- Each concept is an object from language code to term; keys sorted, as the encoder already sorts.
- **The old format still loads.** A file with `"glossary" : { "entries" : [ { "source", "target", "pair" } ] }` is read entry by entry: an entry sharing a term (same language, ignoring case) with an earlier one is merged into that concept, filling only languages it lacks; otherwise it becomes a new concept. The old format needed one entry per direction, so `module -> Modul` and `Modul -> module` become one concept, not two identical ones. Where entries disagree (`Modul` into English as `module`, then as `course unit`), the first wins and the later rendering is dropped: direction-specific renderings are what the concept model gives up. An entry within one language (source and target the same) is dropped. Entries then apply in both directions; this affects only entries written by hand before this PR (the window never wrote any). The next save writes `concepts`.
- A file with both `concepts` and `entries` reads `concepts` and ignores `entries`; `"concepts" : null` is a problem, not a fall back.
- Two spellings of one language code in a concept (`de-CH`, `de-ch`) keep the first in sorted order, the same on every launch.
- **Hand edits are not held to the window's limits** (term length, row count, uniqueness). So that two rows giving one source term never put two renderings into a prompt, `entries(for:)` keeps the first row for each source term (ignoring case).

## 4. The kit

### 4.1 `Glossary` (`Config/Glossary.swift`)

```swift
public struct GlossaryConcept: Sendable, Equatable, Codable {
    /// Trimmed, non-empty terms by language.
    public var terms: [LanguageCode: String]
    public init(terms: [LanguageCode: String])
}

public struct Glossary: Sendable, Equatable, Codable {
    public var concepts: [GlossaryConcept]
    public init(concepts: [GlossaryConcept] = [])
    /// Unchanged signature: the directed entries for this pair, in concept
    /// order, from every concept with a term in both languages.
    public func entries(for pair: LanguagePair) -> [GlossaryEntry]
}
```

`GlossaryEntry` and `LanguagePair` stay as they are; `PromptBuilder` and `Translator` do not change. Language keys are matched as `LanguageCode` values (already lowercased).

### 4.2 `SettingsEditor`

```swift
public mutating func setTerm(_ term: String, for language: LanguageCode, inConcept index: Int) throws
public mutating func deleteConcepts(at indexes: IndexSet) throws
public mutating func addDoNotTranslate(_ term: String) throws
public mutating func setDoNotTranslate(_ term: String, at index: Int) throws
public mutating func deleteDoNotTranslate(at indexes: IndexSet) throws
```

- `setTerm` trims; an empty term removes that language from the concept, and a concept left with no terms is removed. `index == concepts.count` appends a new concept (how + is written: the view shows an empty row and the first term saves it, so no empty concept is ever stored). An index beyond that is `.noSuchRow`.
- Refusals: `.termTooLong` ("At most 80 characters."), `.termInUse(String, String)` ("<term> is already in another row for <language>."), `.tooManyRows` ("At most 200 rows."), `.dntInUse(String)`, `.tooManyTerms` ("At most 100 terms."), `.noSuchRow`.
- Every accepted edit round-trips through the file encoding, as before.

### 4.3 Mutation gate

`Glossary.swift` is already in PASS1. The constraints apply: ASCII only, no comma-joined conditions, no ternary ending in an enum member, no UI import, no lock, loops bounded.

## 5. The app

- `GlossarySettingsView` as a `Grid` (a header row of language names, then a `TextField` per cell and a - button per row) and a list below it. Not a `Table`: a column per language needs `TableColumnForEach`, which is macOS 14.4, and lingoSwen supports 14.0. Each cell keeps a draft, written on leaving or Return; a row being typed in is not reset by a reload. Rows are identified by position, so a field whose row changed under it while typed in (a row above was deleted) drops its draft rather than writing it into another row.
- **+** on the terms table adds an empty row in the view only; the first term typed into it is written with `setTerm(..., inConcept: concepts.count)`, so no empty concept is ever saved.
- Refusals per table, under it, as on the other tabs.

## 6. Testing

- **`GlossaryTests`** (rewritten): `entries(for:)` gives one entry per concept with both languages, in order, with the right source and target; a concept missing either language is skipped; a third language (`fr`) works with no code change; an empty glossary.
- **`GlossaryCodingTests`**: the new format round-trips with sorted keys; the old `entries` format loads as concepts (source and target under their languages); both present reads `concepts`; an empty or whitespace term is dropped at load, and a concept left empty with it; an unknown language code is kept.
- **`SettingsGlossaryTests`**: set, trim, clear one language, clear the last term (row removed), append via `index == count`, duplicate term per language ignoring case refused, the same term in another language allowed, 80/81 characters, 200/201 rows, delete rows, a hidden language kept through an edit; do-not-translate add, edit, duplicate exactly refused but another case allowed, 80/81, 100/101, delete; every accepted edit round-trips.

### Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| G1 | Open Settings, Glossary | Two tables; the terms table has English and Swiss Standard German columns; your existing entry shows as a row |
| G2 | Press + in Terms; type "module" under English and "Modul" under Swiss Standard German | `config.json` has `{"de-ch":"Modul","en":"module"}` under `glossary.concepts` |
| G3 | Translate "Please register for the module." into German; then translate the result back into English | The German uses "Modul"; the English uses "module" |
| G4 | Add another row with "Modul" under Swiss Standard German | Refused: "Modul is already in another row for Swiss Standard German." |
| G5 | Add "NORDA" to Do not translate; translate "Die NORDA bietet Module an." into English | "NORDA" is unchanged in the result |
| G6 | Clear both cells of the module row | The row disappears from the table and from `config.json` |
