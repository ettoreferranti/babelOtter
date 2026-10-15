# Audience inferred from the text, remembered per app — design

**Status:** approved in conversation 2026-10-15, pending review of this document.
**Milestone:** M1b Translate UX. **Covers:** #52 (epic #7), the last M1b story: the audience profile shown in the popup is inferred from the source text, clearly marked as a guess, switchable in one click, and remembered per application; a style note applies to the next generation only.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.6 (`FR-PRO-03` to `FR-PRO-06`) and section 7 (the response contract's `detected_audience`).

## 1. What it does

- **Translate starts from the audience the text addresses.** "Dear students, …" is translated for Students; "Hi Anna, the PR is merged …" for Colleagues. When the text gives no sign, it starts from the audience last chosen in this application, then the one last chosen anywhere, then Colleagues.
- **A guess always looks like a guess.** Beside the audience picker the popup says where the audience came from: "detecting…", "✦ guessed from the text — change if wrong", "last used in Mail", or "default". An audience you picked yourself carries no note.
- **One click fixes a wrong guess.** Choosing another audience re-runs the translation with it, and that choice is remembered for this application.
- **The style note is for this popup only.** The instruction field (placeholder "Style note, e.g. shorter, more encouraging") reaches the prompt on the next generation and is gone when the popup closes. This is already true today.
- **Correct does not guess.** It starts from the per-app memory, because inferring from your own German would read your *du* or *Sie* as the answer and hide the register error Correct exists to catch.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| What decides the starting audience | The text first; then this app's last choice, the last choice anywhere, Colleagues | One app (Outlook, Mail) is used for students and colleagues alike, so the app alone is often wrong; the text usually says who it is for |
| Which actions infer | Translate only | Correct would infer from the very du/Sie it should be checking. Re-pitch is not built yet |
| How the inference runs | In the same request as the translation | No extra round trip: the first words still arrive in about 2 s on the 24B default model. A separate classification request would re-read the text first. Local rules (greetings, names) are brittle and cannot tell user-defined audiences apart |
| What is remembered | Only an audience chosen in the picker, per application bundle ID, as its id | A guess is a suggestion, not a choice. Ids only, never text (`NFR-P3`) |
| After the audience is known | It is fixed for every later run in this popup: the translator's own retry, Regenerate, a style note, Swap | The label must never change under the user. Re-inferring on Regenerate could flip it |
| An answer that names no configured audience | The fallback, labelled as the fallback | #52: "the closest or default profile is selected and not presented as certain" |
| Where the logic lives | In the kit, as `AudienceSession`; the popup only displays it | So every rule above is a unit test under the mutation gate, not a manual check |

## 3. The prompt

With a fixed audience the prompt is unchanged: `Audience:`, `Address the reader as`, `Tone:`, the glossary bias.

When inferring, the audience section instead lists every configured audience, one per line, with its id, name, register and tone guidance, and says:

> Decide which of these audiences the text addresses and write for it. Put its id in `detected_audience`. If the text gives no clear sign, put `"unclear"` and write for `<fallback id>`.

The reply schema is unchanged: `{"detected_source": "…", "detected_audience": "…", "blocks": ["…"]}`. `detected_audience` comes before `blocks`, so it arrives early in the stream.

## 4. Components

### Kit (`BabelOtterKit`, test-first, every file in the mutation PASS1 list)

- **`AudienceRequest`**, what a translation is told: `.fixed(AudienceProfile)` or `.infer(profiles: [AudienceProfile], fallback: AudienceProfile)`. `PromptRequest` carries it in place of a bare profile; Correct always passes `.fixed`.
- **`AudienceInference.match(_ detected: String?, in profiles: [AudienceProfile]) -> AudienceProfile?`**: an exact id, the id in another case, or a profile name (case-insensitive) matches; `"unclear"`, nil, empty or an unknown name returns nil, meaning "use the fallback".
- **`PartialField.string(named:in:) -> String?`**: the value of a top-level string field once its closing quote has arrived, with escapes decoded; nil while it is still arriving. Same approach as `PartialBlocks`.
- **`TranslationEvent.audience(AudienceProfile, inferred: Bool)`**: emitted once per run, before `finished`, as soon as the field is complete (or, if it never is, from the final parse). A fixed audience emits it too, with `inferred: false`. `TranslationResult` gains `audience` and `audienceInferred`.
- **The translator's retry** (a wrong block count) re-sends with `.fixed` the audience the first attempt reported.
- **`AudienceOrigin`**: `chosen`, `inferred`, `rememberedForApp`, `rememberedAnywhere`, `standard`.
- **`AudienceMemory`** protocol: the id last chosen for a bundle ID, the id last chosen anywhere, and `remember(id, forApp:)`. The app implements it over `UserDefaults` (one dictionary key plus the existing `lastProfileID`); tests use an in-memory fake.
- **`AudienceSession`**, one per popup, created with the configured audiences, the source application (bundle ID and name), the action and the memory:
  - `starting`: the fallback chain's audience and origin (app, anywhere, Colleagues, then the first configured audience); a remembered id that no longer exists is skipped.
  - `request`: what the next run should be told. Translate's first run is `.infer` with the fallback; every later run, and every Correct run, is `.fixed` with the audience shown.
  - `apply(event)`: records an `.audience` event, setting origin to `inferred` for a match or keeping the fallback's origin otherwise.
  - `choose(id)`: sets the audience and origin `chosen`, remembers it for this app and anywhere, and reports that a re-run is needed. Choosing the audience already shown does nothing.
  - `note`: the text beside the picker for the current origin, including the application's name for `rememberedForApp`.

### App (`BabelOtterApp`)

- **`PopupModel`** creates an `AudienceSession` when it opens, passes `session.request` to the translator or corrector, forwards `.audience` events to it, and calls `choose` from the picker. The old `initialProfileID` / `lastProfileKey` logic moves into the session and the `UserDefaults` memory.
- **`PopupView`** shows `session.note` beside the picker (a ✦ symbol for `inferred`, "detecting…" until the event arrives on an inferring run) and the new placeholder in the instruction field.
- **`UserDefaultsAudienceMemory`** implements `AudienceMemory`.

## 5. Errors

| Case | Result |
|---|---|
| No `detected_audience`, an empty one, or one that never completes in the stream | The fallback, with its origin's note |
| A name not configured | Same as above |
| The reply fails to parse and is retried | The retry runs with the audience already reported, fixed; if none was, with the fallback, fixed |
| Every audience removed from `config.json` | The chain ends at Colleagues, as `initialProfileID` does today |
| A remembered id no longer configured | That step of the chain is skipped |

None of these affects the translation text; the worst case is a fallback audience, labelled as such.

## 6. Testing

**Unit (kit):**
- Prompt: inferring lists every audience and the fallback id and asks for an id or `"unclear"`; fixed is unchanged (the existing prompt tests pin it); Correct is always fixed.
- `AudienceInference.match`: exact id, other case, name, `"unclear"`, nil, empty, unknown name.
- `PartialField`: complete value, value cut off, escaped quote inside, field absent, field after `blocks`.
- Translator with a fake chat: `.audience` before `.finished`; inferred and fallback cases; the retry sends `.fixed` with the reported audience; a fixed request emits `.audience(…, inferred: false)`.
- `AudienceSession`: each step of the fallback chain and a stale id; first Translate run infers and later runs are fixed; Correct never infers; `choose` remembers for this app and not another, and re-running is reported; a guess is never remembered; a new session has no style note and starts from memory; every `note`.

**Integration (local only, `BABELOTTER_INTEGRATION=1`, never in CI):** synthetic texts against the configured model: an English email to students infers `students`; a chat message to a colleague with team jargon infers `colleagues`; a neutral sentence returns `"unclear"`. Each runs three times and must give the expected answer in at least two, since the model is not deterministic; a case that flaps is a finding about the prompt.

**Manual (one look):** the note beside the picker reads "detecting…" then "✦ guessed from the text"; choosing another audience re-runs the translation.

## 7. Not in scope

- Measuring inference accuracy across a golden set (the eval harness, M3).
- Inference for Correct; Re-pitch, which is not built.
- Editing audiences anywhere but `config.json` (the settings window, #61).
