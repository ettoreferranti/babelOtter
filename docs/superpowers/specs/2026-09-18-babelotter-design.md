# babelOtter — Design Specification

| | |
|---|---|
| **Date** | 2026-09-18 |
| **Status** | Proposed — awaiting approval |
| **Author** | Ettore Ferranti (with Claude) |
| **Diagrams** | [`docs/architecture.md`](../../architecture.md) |
| **Privacy model** | [`PRIVACY.md`](../../../PRIVACY.md) |

---

## 1. Purpose

A macOS agent that translates and tutors between English and Swiss Standard
German at work, driven from anywhere in the OS, running entirely on a local
LLM. It exists to remove the friction of switching to a browser
translator, and — for German — to make the user measurably better at writing it
rather than merely producing correct output for them.

## 2. Scope

**In scope for v1**

- System-wide capture of the current selection, triggered by global hotkey or menu bar
- Four actions: Translate, Correct, Explain, Re-pitch
- Non-destructive preview popup with live streaming, then Replace / Copy / Regenerate / Dismiss
- Audience profiles with inference and one-click override, plus per-invocation style notes
- Configurable languages (EN + de-CH enabled), glossary, do-not-translate list
- Searchable local history
- Guided onboarding, Ollama health management, Privacy panel
- Offline model evaluation harness
- TDD, mutation testing gating CI at ≥80% on the core package

**Out of scope for v1** — tracked as M4 backlog

- Strict AX-only privacy mode and Universal Clipboard investigation
- Persistent mistake log, recurring-error analysis, CEFR estimation, drills
- Rich text (bold/italic/links) round-tripping
- Auto-popup on selection without a hotkey
- Scratchpad window
- Additional languages beyond configuration (French, Italian)
- Signing, notarization, distribution

## 3. Definitions

| Term | Meaning |
|---|---|
| **Action** | One of Translate, Correct, Explain, Re-pitch |
| **Audience profile** | Named bundle of register, tone guidance and glossary bias (e.g. *Students*, *Colleagues*, *Administration*, *Informal*) |
| **Style note** | Free-text, per-invocation instruction appended to the prompt |
| **DNT** | Do-not-translate term, masked to a sentinel before generation |
| **Skeleton** | Extracted paragraph structure: line breaks, blank lines, list markers, indentation |
| **Block** | One prose unit within the skeleton |
| **de-CH** | Swiss Standard German orthography — `ß` never appears, always `ss` |

## 4. Functional requirements

### 4.1 Capture and replace — `FR-CAP`

- **FR-CAP-01** Capture the current selection from the frontmost application via the Accessibility API, recording text, `AXUIElement`, selected range, PID and bundle identifier at trigger time.
- **FR-CAP-02** Where the Accessibility API cannot supply the selection, fall back to simulating ⌘C, saving and restoring the prior clipboard contents around the operation.
- **FR-CAP-03** Replace the original selection with the result on explicit user action, re-activating the source application first.
- **FR-CAP-04** Where AX write is unsupported, fall back to ⌘V with clipboard save/restore.
- **FR-CAP-05** Never discard a generated result: if replacement fails for any reason, surface the failure and offer Copy.
- **FR-CAP-06** Operate on an empty selection by reporting it clearly rather than invoking the model.

### 4.2 Translate — `FR-TRN`

- **FR-TRN-01** Detect the source language of the selection and resolve the target as the other enabled language in the configured pair.
- **FR-TRN-02** Display the detected direction in the popup with a one-click swap that re-runs generation.
- **FR-TRN-03** Where detection confidence falls below a configurable floor, or the selection is shorter than a configurable minimum, present an explicit language picker instead of guessing silently.
- **FR-TRN-04** Preserve paragraph structure: line breaks, blank lines, list markers and leading indentation survive the round trip.
- **FR-TRN-05** Emit de-CH orthography when German is the target — `ß` must never appear in output.

### 4.3 Correct and tutor — `FR-COR`

- **FR-COR-01** Correct a German selection while preserving the author's intent, structure and voice — correcting the language, not rewriting the message.
- **FR-COR-02** Return an itemised list of changes, each with the original fragment, the correction, a category, and an English explanation of the underlying rule.
- **FR-COR-03** Categorise each error as one of: case, word order, gender, agreement, false friend, spelling, register, preposition, other.
- **FR-COR-04** Render an inline word-level diff of original versus corrected text in the popup.
- **FR-COR-05** Distinguish outright errors from stylistic suggestions by severity.
- **FR-COR-06** Report explicitly when the text contains no errors, rather than inventing changes.

### 4.4 Explain — `FR-EXP`

- **FR-EXP-01** Explain a German selection in English: overall meaning plus notes on individual tricky phrases, idioms and grammatical constructions.

### 4.5 Re-pitch — `FR-RPT`

- **FR-RPT-01** Re-aim text at a different audience profile without changing its language, preserving factual content while adjusting register and tone.

### 4.6 Audience profiles and tone — `FR-PRO`

- **FR-PRO-01** Support user-defined named profiles, each with register (Sie/du), tone guidance, and optional glossary bias.
- **FR-PRO-02** Ship sensible defaults: Students, Colleagues, Administration, Informal.
- **FR-PRO-03** Infer the applicable profile from the source text and return it with the generation result.
- **FR-PRO-04** Display the inferred profile prominently in the popup as a control that switches and re-runs in one click.
- **FR-PRO-05** Accept a free-text style note per invocation, appended to the prompt.
- **FR-PRO-06** Remember the last profile used per source application.

### 4.7 Languages — `FR-LNG`

- **FR-LNG-01** Treat languages as configuration, with no language hardcoded in logic.
- **FR-LNG-02** Attach per-language locale rules as data — de-CH's `ß`→`ss` being the first instance.
- **FR-LNG-03** Enable English and de-CH by default; adding a language must require no code change.

### 4.8 Terminology — `FR-GLO`

- **FR-GLO-01** Maintain a user-editable bidirectional glossary injected into prompts to force consistent renderings.
- **FR-GLO-02** Maintain a do-not-translate list whose terms are masked to sentinels before generation and restored afterwards, verbatim.
- **FR-GLO-03** Guarantee locale rules never rewrite the interior of a restored DNT token.

### 4.9 Interface — `FR-UI`

- **FR-UI-01** Provide configurable global hotkeys per action, registered without requiring the Input Monitoring permission.
- **FR-UI-02** Provide a menu bar item exposing every action plus Settings, History, Privacy and Quit.
- **FR-UI-03** Reflect readiness in the menu bar icon: ready, degraded, blocked.
- **FR-UI-04** Present results in a popup positioned near the selection that does not steal focus from the source application.
- **FR-UI-05** Stream generation into the popup token by token.
- **FR-UI-06** Offer Replace, Copy, Regenerate and Dismiss; keep Replace disabled until post-processing has completed.
- **FR-UI-07** Dismiss on Escape and cancel any in-flight generation.

### 4.10 History — `FR-HIS`

- **FR-HIS-01** Record every completed action locally: source, result, action, languages, profile, model, timestamp.
- **FR-HIS-02** Provide a searchable history window with re-copy.
- **FR-HIS-03** Provide configurable retention and an unconditional Clear All control.
- **FR-HIS-04** Store history exclusively under `~/Library/Application Support/ch.babelotter/`, never in an iCloud-synced location.

### 4.11 Configuration — `FR-CFG`

- **FR-CFG-01** Provide a settings window covering languages, profiles, glossary, DNT list, hotkeys, models per action, timeouts and retention.
- **FR-CFG-02** Allow a different model per action.
- **FR-CFG-03** Persist configuration as human-readable, hand-editable files.

### 4.12 Onboarding and diagnostics — `FR-ONB`

- **FR-ONB-01** Guide first launch through: grant Accessibility → verify Ollama → select model → set hotkeys → live test, each step self-verifying before advancing.
- **FR-ONB-02** Re-present the relevant step when a permission is later revoked.
- **FR-ONB-03** Provide a Privacy panel reporting live status: resolved endpoint, Ollama listening interface, history location, iCloud exposure of that path, dependency count.
- **FR-ONB-04** Warn when the Ollama daemon is bound to a non-loopback interface.

### 4.13 Ollama lifecycle — `FR-OLL`

- **FR-OLL-01** Health-check Ollama at launch and before each request.
- **FR-OLL-02** On unavailability, present an actionable diagnostic with a Start Ollama affordance — never fail silently.
- **FR-OLL-03** On a missing model, offer to pull it via the local daemon after explicit confirmation showing name and size, with progress.
- **FR-OLL-04** Stream responses and support cancellation of an in-flight request.

### 4.14 Evaluation harness — `FR-EVL`

- **FR-EVL-01** Provide a CLI scoring candidate models against a synthetic golden set for translation and correction.
- **FR-EVL-02** Score at minimum: `ß` absence, DNT token fidelity, structure preservation, block-count fidelity, and reference similarity.
- **FR-EVL-03** Emit a comparison table across models.
- **FR-EVL-04** Use exclusively synthetic fixtures — no real correspondence.

## 5. Non-functional requirements

### 5.1 Privacy — `NFR-P`

- **NFR-P1** babelOtter never transmits user content. No telemetry, analytics, crash reporting, remote configuration or update checks exist, and the only socket it opens is loopback. *Inviolable, and enforced by test.*
- **NFR-P1a** The clipboard path can expose content to Universal Clipboard if Handoff is enabled. macOS does that, not babelOtter, and babelOtter cannot detect whether it is on. Accepted as the cost of working in applications the Accessibility API cannot reach or cannot write to.
- **NFR-P2** babelOtter opens no non-loopback connections. Model downloads are delegated to the local Ollama daemon after explicit confirmation.
- **NFR-P3** The endpoint type accepts loopback hosts only and deliberately ignores `OLLAMA_HOST`.
- **NFR-P4** Exactly one file in the codebase may reference networking APIs; asserted by an architecture test.
- **NFR-P5** User content cannot reach a logging API without passing through a type-enforced redactor.
- **NFR-P6** All runtime dependencies appear on a reviewed allowlist checked in CI; none may perform networking.
- **NFR-P7** Local storage is `0600`, excluded from backup, and outside any iCloud-synced tree; the path resolver refuses otherwise.
- **NFR-P8** This repository is public: fixtures, eval cases, glossary defaults and screenshots must be synthetic, enforced by a CI content guard. Integration tests run locally only.
- **NFR-P9** The clipboard is an accepted conduit, not a deferred risk. It is the only capture path for Electron apps and the only replacement path for everything except native AppKit text, so it is load-bearing rather than a fallback. Its exposure is stated in `PRIVACY.md` and the user is told, per action, when it was used.
- **NFR-P10** Pasteboard dwell time is minimised, and the previous contents are restored as soon as the operation completes, on every path including failures. Universal Clipboard transfers at paste time rather than at copy time, so the restore is what ends the exposure — it is a privacy mechanism, not a courtesy.

### 5.2 Quality — `NFR-Q`

- **NFR-Q1** Test-driven development throughout: no implementation without a failing test first.
- **NFR-Q2** Mutation testing on `BabelOtterKit` gates CI at ≥80%.
- **NFR-Q3** The core package imports no AppKit, SwiftUI or UI framework.
- **NFR-Q4** External effects sit behind protocols, permitting tests without Ollama, database or UI.
- **NFR-Q5** CI runs build, tests, architecture guards, mutation testing and the content guard on every push.

### 5.3 Performance — `NFR-PERF`

- **NFR-PERF-1** First token reaches the popup within 2s of trigger for a typical paragraph on the reference model.
- **NFR-PERF-2** The popup appears within 150ms of trigger, before generation begins.
- **NFR-PERF-3** Requests time out at a configurable default of 60s, offering retry or a smaller model.
- **NFR-PERF-4** The app is idle-quiet: no polling of the selection, no background inference.

### 5.4 Reliability — `NFR-REL`

- **NFR-REL-1** A malformed model response degrades gracefully and never corrupts the user's text.
- **NFR-REL-2** A block-count mismatch triggers exactly one whole-text retry before degrading.
- **NFR-REL-3** No failure path silently discards a generated result.

## 6. Data model

```
Config
  languages: [LanguageConfig { code, displayName, localeRules, enabled }]
  profiles:  [AudienceProfile { id, name, register, toneGuidance, glossaryBias }]
  glossary:  [GlossaryEntry { source, target, languagePair }]
  dnt:       [String]
  hotkeys:   [Action: KeyCombo]
  models:    [Action: ModelID]
  timeouts, retentionDays, detectionConfidenceFloor, minimumLengthForDetection

HistoryRecord
  id, timestamp, action, sourceLanguage, targetLanguage, profileID, model,
  sourceText, resultText, errors: [CorrectionError]?, sourceAppBundleID
```

## 7. Response contracts

```jsonc
// translate / re-pitch
{ "detected_source": "en", "detected_audience": "colleagues", "blocks": ["…"] }

// correct
{ "corrected_blocks": ["…"],
  "errors": [{ "original": "…", "corrected": "…", "category": "case",
               "explanation_en": "…", "severity": "error" }] }

// explain
{ "summary_en": "…", "notes": [{ "phrase": "…", "explanation_en": "…" }] }
```

Block arrays make structure misalignment detectable rather than silently
corrupting output. Parsing is tolerant: strip code fences, locate the outermost
JSON object, decode; on failure, degrade per NFR-REL-1.

## 8. Post-processing order

Sentinel restoration **precedes** locale rules; locale rules **must not** rewrite
restored DNT spans. Both are explicit, separately tested invariants.

## 9. Testing strategy

| Layer | Runs in CI | Mutation-tested |
|---|---|---|
| Unit — pure core | ✅ | ✅ ≥80% |
| Contract — recorded NDJSON | ✅ | — |
| Architecture guards | ✅ | — |
| Integration — real Ollama | ❌ local only | — |
| Eval harness | ❌ local only | — |
| Manual UI smoke | ❌ | — |

Highest-value mutation targets: block-index arithmetic in `StructureExtractor`,
the post-processing order chain, detection confidence thresholds, sentinel
matching in `TokenProtector`, and loopback validation in `OllamaEndpoint`.

## 10. Milestones

| Milestone | Contents |
|---|---|
| **M0 Foundations** | Package structure, CI, muter spike (#18), focus-loss spike (#30), privacy enforcement guards |
| **M1a Pipeline** | Capture/replace, detection, structure, DNT, prompts, streaming client, parser, locale rules, configuration model — no UI |
| **M1b Translate UX** | Hotkeys, menu bar, permissions, non-activating popup, streaming render, direction swap, profile control, end-to-end Translate |
| **M2 Correct & Tutor** | Correction pipeline, error taxonomy, explanations, inline diff |
| **M3 Explain, Re-pitch & Polish** | Remaining actions, history, settings, onboarding, Privacy panel, eval harness |
| **M4 Post-v1** | Strict privacy mode, mistake tracking, CEFR drills, rich text, more languages, distribution |

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Focus loss drops the selection when the popup appears | App feels broken | Capture `AXUIElement` + PID at trigger; non-activating panel; **M0 spike** |
| `muter` unusable on Swift 6.4 / macOS 27 | Mutation gate unachievable | **M0 spike**; fallback SwiftSyntax harness; last resort report-only, reported not assumed |
| Models mangle DNT sentinels | Protected terms corrupted | Validate across models in the eval harness; choose sentinel empirically |
| Local model German quality insufficient | Core value undermined | Eval harness scores candidates before committing to a default |
| Universal Clipboard sync via fallback | Privacy violation | **Accepted for v1**, documented; M4 investigation |

## 12. Decision log

| # | Decision | Rationale |
|---|---|---|
| 1 | Native Swift app, not Electron/Tauri | Full Xcode available; best OS integration and Accessibility access |
| 2 | Pure core + thin shell + eval CLI | Testability and provable privacy invariants without IPC complexity |
| 3 | Hotkey + menu bar, no auto-popup | Avoids continuous accessibility polling and its battery cost |
| 4 | Preview before replace, always | Non-destructive by default |
| 5 | AX first, clipboard fallback | Coverage across Electron apps and browsers; risk accepted for v1 |
| 6 | Paragraph structure only, not rich text | Covers real writing without RTF complexity |
| 7 | Profiles + style note, not a formality slider | Register must differ per audience; a three-way toggle cannot express it |
| 8 | Auto-detect direction with visible override | One hotkey, recoverable when wrong |
| 9 | Fully generic language config | Adding French/Italian must not require code changes |
| 10 | Stream raw, post-process on completion | Perceived speed without sacrificing correctness |
| 11 | Delegate model pulls to the Ollama daemon | Preserves the loopback-only invariant intact |
| 12 | Mutation gate ≥80% on core only | UI-glue mutants are noise |
| 13 | Repo stays public, synthetic fixtures only | Openness without exposing real correspondence |
