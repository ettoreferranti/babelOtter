# Formality per target language — design addendum

**Status:** approved in conversation 2026-10-21, pending review of this document.
**Covers:** #110 (epic #11). **Builds on:** `2026-10-21-settings-audiences-design.md` and the parent spec's `FR-PRO-01` (audiences carry register) and `FR-LNG-01`/`FR-LNG-03` (languages are data).

## 1. What changes

- **An audience says only formal or informal.** `register` in `config.json` holds `"formal"` or `"informal"`. The old values `"Sie"` and `"du"` (any case) still load, as formal and informal; the next save writes the new ones.
- **A language says how it expresses that**, as data: `"addressForms" : {"formal" : "Sie", "informal" : "du"}` on Swiss Standard German. English has none. Italian (Lei/tu) or French (vous/tu) are then one line each in `config.json`, with no code change.
- **Prompts follow the target language.**
  - With address forms: `Address the reader as "Sie".` (as today).
  - Without (English): `Write in a formal register.` or `Write in an informal register.` English still has formal and informal writing; the audience's tone guidance applies on top, as before.
  - The audience list for inference: `- students: Students, formal ("Sie"). <tone>` with forms, `- students: Students, formal. <tone>` without; its header reads `(id: name, formality, tone)`.
  - Correct: with forms, as today (`... who should be addressed as "Sie". A mismatch is a register error.`); without, `... which should be written in a formal register. A mismatch is a register error.`
- **The popup's audience picker** shows `Students (Sie)` for a target with forms and `Students (formal)` for one without.
- **The Audiences tab** offers Formal / Informal, with a hint under it listing each enabled language that has forms: `Sie / du in Swiss Standard German`.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Where the pronoun lives | On the language, as `addressForms` | `FR-LNG-03`: a language is data; the audience stays the same whichever language it is written in |
| A target without forms | The register in words | Formality still matters in English; saying nothing would leave it to the tone text alone |
| An existing de-CH without `addressForms` | Gets the shipped forms when the key is **absent**; JSON `null` means "this language has none" | Existing files must keep Sie/du without an edit; the forms come from the shipped language data by code, so no language is named in logic (`FR-LNG-01`) |
| The JSON key | Stays `register` | Hand-edited files and the `UserDefaults`/history ids are unaffected; only the value changes |
| More than two levels (Japanese) | Out of scope | Two values cover the languages in view |
| Going back to an older build | Not supported once this build has saved | A pre-#110 build reads `"formal"` as an error and falls back to the defaults for the whole file; noted in HANDOFF |

## 3. The kit

- `Register` (`Config/AudienceProfile.swift`): raw values `formal` and `informal`; a custom `init(from:)` accepting `formal`, `informal`, `sie`, `du` (trimmed, any case), refusing anything else with `expected "formal" or "informal"`.
- `AddressForms` (`Config/LanguageConfig.swift`): `public struct AddressForms: Sendable, Equatable, Codable { public let formal: String; public let informal: String; public func form(for register: Register) -> String }`, both non-empty after trimming.
- `LanguageConfig.addressForms: AddressForms?`, a new `init` parameter defaulting to nil; `swissGerman` ships `Sie`/`du`, `english` none. Custom decoding: key absent gives the shipped language's forms for the same code, else for the same base code (`de`, `de-de`, `de-at` take de-ch's, as `Configuration.germanLanguage` matches German), from `LanguageConfig.shippedDefaults`; `null` gives none; a value is used as written. Encoding writes the key always (`null` for none), so the file shows the choice.
- `PromptBuilder`: one helper, `formality(_ register: Register, in language: LanguageConfig) -> String`, used by the translate, inference and correct lines as in section 1. The target for Translate and Re-pitch is `request.target`; for Correct, the text's language.
- `Register.word`: `"formal"` / `"informal"`, for the register-in-words lines and the popup.

## 4. The app

- `PopupView`: the picker label uses the current target's forms (`model`'s direction target, or the text's language for Re-pitch and Correct).
- `AudiencesSettingsView`: the segmented control reads Formal / Informal; under it, one line per enabled language with forms.

## 5. Testing

- **`RegisterTests`**: `formal`, `informal`, `Sie`, ` du `, `SIE` decode; `vous`, `""`, `null`, `1` refused with the message; encoding gives `formal`/`informal`.
- **`LanguageConfigTests`**: de-CH without the key gets Sie/du; with `null` gets none; with Lei/tu (an invented `it` entry) uses them; English without the key gets none; a language not shipped gets none; round trip writes the key.
- **`PromptBuilderTests`**: English to German says `Address the reader as "Sie".`; German to English says `Write in a formal register.` and contains no `Sie`; informal says `informal register` / `"du"`; the inference list and the Correct line in both cases; an invented `it` with Lei/tu says `"Lei"`.
- **Integration** (local model, `BABELOTTER_INTEGRATION=1`): the existing English to German checks still use Sie/du.

### Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| F1 | Rebuild and start; look at `config.json` | Your audiences still load; after any settings change, `register` reads `"formal"`/`"informal"` and de-ch has `"addressForms"` with Sie/du |
| F2 | Translate an English email to "Students" into German | Uses Sie, as before; the picker shows "Students (Sie)" |
| F3 | Translate a German text into English with Administration; then with Informal | The picker shows "Administration (formal)"; the English is formal, then casual |
| F4 | Open Settings, Audiences | Formal / Informal, with "Sie / du in Swiss Standard German" under it |
| F5 | Correct a German du-text addressed to Students (formal) | The register error is reported as before |
