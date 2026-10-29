# Spanish — design

**Status:** approved in conversation 2026-10-29.
**Milestone:** M4. **Covers:** #132 (epic #15), in one PR. **Follows:** `2026-10-23-more-languages-design.md` (#81), which shipped French and Italian the same way.

## 1. What it does

Spanish ships as a fifth language, switched off, beside French and Italian. Switching it on in Settings › General is all a user does; nothing else changes. A Spanish entry added to `config.json` by hand already works today (tried 2026-10-29), because languages are data (`FR-LNG-03`); this ships one with the details a hand-written entry lacks.

Decided in conversation (2026-10-29): **neutral Spanish**, with no regional writing note, like French and Italian; **manual checks only**, no golden set.

## 2. The language

`LanguageConfig.spanish`, appended to `shippedDefaults` after Italian:

| Field | Value |
|---|---|
| `code` | `es` |
| `displayName` | Spanish |
| `localeRules` | none |
| `enabled` | false |
| `addressForms` | formal *usted*, informal *tú* (escaped in the Swift source, which is ASCII-only) |
| `correctionNotes` | below |
| `writingNotes` | none: the model writes its standard Spanish, and Correct does not flag Spain or Latin American usage as errors |

**Correction notes**, in the shape of French's and Italian's (what to check, then an English example explanation):

> Check written accents on stressed syllables and on words they tell apart: *el* or *él*, *tu* or *tú*, *si* or *sí*, *mas* or *más*; and on question words when they ask or exclaim (*qué*, *cómo*, *dónde*), never on *que* as a conjunction or relative. Check opening question and exclamation marks, gender and number agreement of articles and adjectives, *ser* or *estar*, and the subjunctive after expressions of wish, doubt or purpose ("quiero que vienes" becomes "quiero que vengas"). Usage of Spain and of Latin America are both correct. Example explanation: "querer que takes the subjunctive, so vienes becomes vengas".

## 3. Existing files

- A file without Spanish gains it switched off at load, after its own languages (`addingMissingShippedLanguages`), as French and Italian were added in #81.
- A file that already has Spanish under any `es` code (`es`, `es-ES`, `es-419`) is left as it is: it counts as present by base code.
- A hand-written entry without `correctionNotes` takes the shipped notes from now on, because an absent field takes the shipped value for the same base code. So the maintainer's own entry gains them with no edit; its `enabled` and `addressForms` stay as written.

## 4. Out of scope

- An editable languages list in Settings (add or remove any language): a separate story if wanted.
- A Spanish golden set and evaluation.
- Regional variants.

## 5. Tests and manual checks

- Unit tests: Spanish ships off with *usted*/*tú*, no rules, no writing notes, and notes that name the subjunctive; `shippedDefaults` is en, de-CH, fr, it, es; a file without Spanish gains it off; an `es-419` entry keeps Spanish out; a hand-written `es` entry without notes takes the shipped ones and keeps its own `enabled`.
- Manual checks, in HANDOFF, with the real model and Spanish switched on: translate an English and a German text into Spanish and back; formal and informal audiences give *usted* and *tú*; Correct a Spanish text with a missing accent and a wrong subjunctive; Explain a Spanish text with English as my language; Re-pitch a Spanish text; the scratchpad on a long Spanish text.
