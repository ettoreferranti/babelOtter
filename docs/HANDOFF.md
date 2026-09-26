# Handoff — state as of 2026-09-25

Read this first if you are picking babelOtter up in a new session.

## Update 2026-09-25: testing stops, prototyping starts

**M1a is merged to `main` and closed.** The shell's remaining manual
measurements (Task 14, Steps 2-4) are deferred, not done, and recorded as open
in `docs/architecture.md` section 7. The clipboard is accepted as the conduit
wherever it is needed, Universal Clipboard exposure included.

**The Translate prototype is built**, a thin slice of M1b, on
`feat/translate-prototype` (not yet merged to `main`): a menu bar app, a
global hotkey (Control-Option-T, fixed), selection capture through the
three-tier ladder (Accessibility first, then the clipboard), a
non-activating streaming popup near the cursor, direction auto-detection
with a manual choice and a swap when it can't tell, and Replace (paste back
through the clipboard, the user's own clipboard restored afterwards) / Copy.
Plan: `docs/superpowers/plans/2026-09-25-translate-prototype.md`; its seven
tasks are all done.

**Deliberately not in this slice** -- each a small, separate follow-up once
the prototype has seen daily use:

- **Audience profile control.** Every translation runs against the fixed
  Colleagues profile. There is no picker, and no per-invocation style note
  ("shorter", "more encouraging").
- **A settings window.** Configuration is hand-edited JSON only (see the
  README's status block for the path).
- **Onboarding.** The Accessibility prompt is the bare system one; there is
  no guided setup, and no re-prompt if a grant is later revoked (#71).
- **History.** Nothing is written to disk. A result lives only in the popup
  until Replace, Copy, or Dismiss.
- **Regenerate.** A translation that came back wrong has to be re-triggered
  from scratch -- dismiss, reselect if needed, hotkey again. There is no
  in-popup retry.
- **Configurable hotkeys.** Control-Option-T is the one hotkey, and it is
  hardcoded.

**Rigour is now split by layer.** `BabelOtterKit` keeps TDD and the mutation
gate. `Sources/BabelOtterApp` is AppKit glue and is built for speed, verified
by using it. Mutation testing moved to `.github/workflows/mutation.yml` and only
runs when the kit or its tests change; its timeout went from 60 to 150 minutes
after three runs were cancelled at the hour.

**Default model:** `mistral-small3.2:24b`, pulled locally.

**Watchdog budget.** The 60s timeout (`timeoutSeconds`) budgets the *whole*
translation -- including the one retry on a bad block count, and Ollama
loading the 24B model from disk if it is not already resident. A first
translation right after a reboot, or after Ollama has unloaded the model from
being idle, can plausibly hit that budget while the model is still loading and
show as a timeout rather than a slow success. If that happens often, raise
`timeoutSeconds` in `config.json`; this is a known, accepted trade-off, not a
bug to fix here.

### Outstanding manual checks (yours -- nothing here can be pressed or watched from a coding session)

`swift test && Tools/make-app.sh --run`, grant Accessibility when prompted
(menu bar icon shows the status; *Check Again* rereads it), then work
through these. They come from tasks 5, 6 and 7 of the prototype plan and
none of them have been run yet.

**Capture** -- select text in each app, then press Control-Option-T:

| App | Expected |
|---|---|
| TextEdit | `via accessibilityText` |
| Safari (page text) | `via textMarkerRange` |
| VS Code, Teams, Word | `via clipboard`; your previous clipboard is still there afterwards |
| Any app, nothing selected | the *nothing selected* message |

The panel must appear near the pointer without the source app losing its
active title bar. If Control-Option-T does nothing at all, check the menu
bar icon's first item -- it reads "Control-Option-T is taken by another
app" if registration lost to something else already holding that
combination.

**Translation:**

| Do | Expected |
|---|---|
| Select a German paragraph in TextEdit, Control-Option-T | Swiss Standard German -> English; text streams in; no `⟦DNT` debris, no JSON |
| Select English, Control-Option-T | English -> Swiss Standard German; no eszett anywhere, preview included |
| Select "Hallo", Control-Option-T | *Translate into:* with two buttons; either one translates |
| Press Swap during or after a translation | the direction flips and it re-runs |
| Press Escape mid-stream | popup closes; the `ollama serve` terminal (or Activity Monitor's CPU/GPU column for the `ollama` process) drops back to idle within a second or two, rather than keeps generating -- `ollama ps` only lists loaded models, not in-flight requests, so it will not show this |
| A bullet list | markers and line structure survive |
| Quit Ollama, Control-Option-T | "Ollama could not be reached" rather than a hang |
| Copy | result on the clipboard, popup closed |
| Press Control-Option-T in VS Code, then Escape before the popup shows a result | popup closes; the `ollama serve` terminal shows no new generation starting (or Activity Monitor's `ollama` process never spikes) |
| Press the hotkey again while a popup from a previous selection is still open/streaming | the first one closes (and its in-flight request stops) before the second one starts |

**Replace:**

| Surface | Expected |
|---|---|
| TextEdit | selection replaced; previous clipboard intact afterwards (Command-V elsewhere) |
| Safari `<textarea>` (`Tools/editable-scratch.html`) | replaced |
| Mail compose, Outlook body | replaced |
| Teams, Word, VS Code | replaced |
| Source app quit before pressing Replace | popup stays, says the application has closed, Copy still works |
| Press the hotkey again while a Replace is still settling (right after the popup closes, before the source app's title bar has fully returned) | the press is ignored, the same as during a capture; watch the `ollama serve` terminal (or Activity Monitor's `ollama` process) and Console for a second, overlapping capture rather than a clean no-op -- `ollama ps` will not show this either, for the same reason as above |

Watch for one more failure shape on every Replace row above, not its own
row: **the user's old clipboard content appears in the document instead of
the translation.** That means the settle time between Command-V and the
restore (0.8s, matching what `Tools/clipboard-probe.swift` measured) was too
short for that application to read the pasteboard before babelOtter put the
old clipboard back -- worth a note of which app and how much text, since the
fix is a longer, possibly per-app, settle time.

Anything any of these contradicts in `docs/architecture.md` section 7 belongs
there, plainly, once it is actually measured -- that document is measured
reality, not a place to record an expectation nobody has confirmed.

Everything below is the 2026-09-20 state, kept for its reasoning.

## Where things stand

**M0 Foundations is merged to `main` and closed.** The 27 commits landed as a
single `--no-ff` merge, so the milestone reads as one unit with every commit
intact. `main` is green.

**M1a's shell is on `feat/m1a-shell`, not merged.** Tasks 1-13 of
`docs/superpowers/plans/2026-09-20-m1a-shell.md` are done: the whole Ollama
client, the capture ladder, clipboard capture and replacement, strict mode,
result custody and the empty-selection gate. Task 14 is the integration suite,
which needs a granted Accessibility permission and real applications, so it is
yours to run rather than mine.

What is deliberately *not* covered by tests is small and named: three files in
`Sources/BabelOtterApp` -- `AccessibilityReader`, `SystemPasteboard`,
`SyntheticKeystrokes` -- which cannot be unit-tested at all. Everything that
decides anything is pure and lives in the kit.

**M1a's pure core is merged to `main`.** It is the whole translation pipeline
except the parts that touch the outside world: no Accessibility, no clipboard,
no network, no UI. All of it runs in CI.

| | |
|---|---|
| Branches | `feat/m1a-core` merged 2026-09-20; `feat/m1a-shell` open |
| Tests | 255 in 25 suites, green from a clean build |
| Mutation | 42/49 = **85.7%**, gating CI at ≥80%, no unmeasured mutants |
| CI | green — build+test and the mutation job both pass |
| Dependencies | still zero, enforced by test |
| Local toolchain | Xcode 27 / Swift 6.4 — two majors ahead of CI, so CI is the binding check |

Issues #16–#25 and #30 are closed; the M0 milestone is closed with nothing open
in it. Epic #1 is closed as fully delivered. Epic #2 moved to M1a, where its one
remaining child #77 now lives. Milestones: M1a Pipeline (29), M1b Translate UX
(13), M2 (5), M3 (17), M4 (8).

## What M1a Core delivered

Fifteen new source files under `Sources/BabelOtterKit`, each with its own suite.
Implements #36, #37, #38, #39, #42, #43, #44, #53, #55, #56, #57, and the model
half of #58, #59 and #60.

| Area | Files |
|---|---|
| Configuration | `LanguageConfig`, `AudienceProfile`, `Glossary`, `Configuration`, `ConfigurationStore` |
| Text | `StructureExtractor`, `TokenProtector`, `LocaleRuleApplier`, `PostProcessor`, `LanguageDetector`, `TargetLanguageResolver` |
| LLM-facing | `ResponseContracts`, `PromptBuilder`, `ResponseParser`, `BlockCountPolicy` |

`Tests/BabelOtterKitTests/PipelineTests.swift` drives the whole path end to end
with a canned response — structure out, terms masked, prompt built, response
parsed, block count checked, post-processing applied, structure back on — so the
seams between components are covered, not only the components.

**The plans:** `docs/superpowers/plans/2026-09-19-m1a-core.md` (executed) and
`docs/superpowers/plans/2026-09-20-m1a-shell.md` (written, not started).

## The thing to understand before touching mutation testing

**muter mis-measures any file containing a non-ASCII character, and one of the
two ways it does so is silent.**

muter locates a mutation by UTF-8 byte offset and then splices the replacement
by character index. Those agree only while the file is ASCII. One three-byte
character earlier in the file shifts every later splice by two:

- **Loud.** The mutant does not compile — `best.value >= floor` became
  `best.value >=<= oor`, eating two characters of `floor`. Every mutant for a
  file compiles into one binary, so a single bad splice makes the whole file
  unmeasurable.
- **Quiet, and worse.** The mutant compiles but changes something inert, and
  muter reports it as a **survivor**. The score drops for a mutation that was
  never really applied.

The first measured run of this core scored 66% with eighteen survivors and two
build errors. **Every one was an artefact.** Hand-planting the same mutations
showed the existing tests already killed them. Roughly an hour went into writing
tests for defects that had never been introduced.

`Tests/BabelOtterKitTests/Architecture/AsciiSourceTests.swift` now enforces
ASCII-only sources in `BabelOtterKit`, with a parameterised test proving the
scanner detects what it claims to. Characters the code genuinely needs are
escapes — `"\u{27E6}"` for the sentinel bracket, `"\u{00DF}"` for the eszett —
which produce identical strings from an ASCII file.

**Two further muter traps, both now avoided in this package:**

- A `while` condition that is a comma-conjunction containing a relational
  operator (`while a < b, predicate`). Already recorded in `muter.conf.yml` for
  `StorageLocator`, which still needs the pass-2 workaround.
- A ternary whose condition ends in an enum member.
- A `guard ... else { ...; return }` inside a `do` block inside a `Task`
  closure. muter replaced the whole `do` body with a bare `return`, so the
  *unmutated* baseline did nothing, and `OllamaClient.pull`'s tests hung. That
  hang is why every Mutation run from the M1a shell until 2026-09-26 was
  cancelled at its time limit instead of scored. Put such bodies in a named
  function (see `OllamaClient.relayPull`). The stream suites now also carry a
  one-minute `.timeLimit`, so a hang fails loudly instead of stalling CI.

**The intermittent `buildError` is nondeterministic, and chasing it is a trap.**
This document used to record it as "observed once on CI, never reproduced
locally". It is now understood: on 2026-09-20 `main` went red four times, each
on a single mutant that failed to build, a different line each time. Each red
was chased by restructuring whichever construct had failed. Then the same job
was re-run on the *same commit with no code change* and passed with zero
unmeasured mutants.

So the line it names is not the cause, and restructuring it fixes nothing. The
mutation passes in `ci.yml` now retry once on a `buildError`, and only a
persistent one fails the build — a mutant that genuinely cannot be measured
still stops CI, because nothing was learned about it.

The restructuring it prompted was kept, because the code is better for it:
`TokenProtector` walks a shrinking `Substring` instead of comparing indices
against `endIndex`, and `OllamaEndpoint` asks `!inner.isEmpty` rather than
`count > 2`. Fewer comparisons also means fewer mutants — 51 down to 44 — which
is a smaller denominator, not worse coverage.

**Local runs need a clean working copy.** muter reuses `../babelOtter_mutated`
between runs and will measure stale tests against fresh sources — which is what
made the first round of new tests appear to kill nothing. Run
`rm -rf ../babelOtter_mutated` before every local run. CI is unaffected; its
workspace is always fresh.

Worth reporting all of this upstream before M1b leans on it further.

## Settled, and worth not re-litigating

1. **Defaults are settled for now.** `defaultModel` is
   `mistral-small3.2:24b` — European-language coverage, Apache 2.0 so it does
   not block distribution (#82), and 3.2's instruction-following matters because
   this pipeline demands strict JSON, exact block counts and untouched DNT
   sentinels. 15GB at Q4_K_M, comfortable on the 48GB M4 Pro. #74–#76's eval
   harness is still what should decide this properly.
   `detectionConfidenceFloor = 0.65`, `minimumLengthForDetection = 12`
   (non-whitespace characters), `timeoutSeconds = 60`, `retentionDays = 90` are
   to be revisited once there are manual tests behind them.

2. **DNT matching is case-sensitive.** A term is a proper noun, so `otterbach` does
   not match `Otterbach`. Defensible either way; say if you want it case-insensitive.

3. **Seven surviving mutants, all in sort comparators**, look like equivalent
   mutants — `>` replaced by `>=` in a comparator that still orders the same list
   identically. The gate passes at 86.3% with them. Killing them means
   restructuring comparators to suit the tool, so they are left alone.

4. **The mutation threshold question is resolved by growth.** At 51 measured
   mutants the small-population rule (`total < 20`) no longer applies, so the
   plain 80% gate is doing the work now.

5. **The clipboard is an accepted conduit, decided 2026-09-20.** NFR-P1 now
   reads: *"babelOtter never transmits your content. The clipboard path can
   expose it to Universal Clipboard if Handoff is enabled."* The first sentence
   is absolute and enforced by test; the second is macOS doing something
   babelOtter neither asks for nor can observe.

   The alternative was a product that does not work where people write:
   Accessibility cannot capture in Teams, Word, OneNote or VS Code, and cannot
   replace anywhere except native AppKit text. Restated in the spec
   (`NFR-P1`, `NFR-P1a`, `NFR-P9`), `PRIVACY.md` and `README.md`.

   **#77 is rewritten** as capture-only strict mode: refuse the clipboard for
   reading, accept it for writing. Its spike is fully answered and recorded in
   the issue.

## What is next

`docs/superpowers/plans/2026-09-20-m1a-shell.md` — capture, replacement and the
Ollama client, in 15 tasks. It is built on `docs/architecture.md` §7, which is
measured reality and supersedes §2–3.

**M1b's premise is confirmed.** Measured 2026-09-20 on the managed work Mac:
`AXIsProcessTrusted()` returns YES after granting Accessibility through System
Settings, despite DEP enrolment and several vendor PPPC payloads. Those
payloads pre-authorise specific vendor tools; they do not stop the user
granting Accessibility to something of their own. Local admin was needed, and a
policy refresh could revoke it, which makes #71 real rather than hypothetical.
Full detail in `docs/architecture.md` §7.

**Per-app tiers are measured.** Tier 1: TextEdit, Preview, Outlook. Tier 2:
Safari. **Tier 3, clipboard-only: Teams, Word, OneNote, VS Code.** Full table
and caveats in `docs/architecture.md` section 7.

That last row is the finding that matters. The clipboard is not a fallback for
edge cases -- for the apps a working day is actually spent in, it is the only
path. #77's strict mode would make babelOtter refuse to operate in Teams, Word
and OneNote entirely, which makes its default a product decision rather than a
detail.

**Architecture, decided 2026-09-20: Accessibility reads, the clipboard
writes.** Capture uses the tier ladder; replacement always uses the clipboard.
The asymmetry follows the evidence in each direction, and it removed three
planned tasks: the Accessibility write path, the read-back verifier that
existed only because the write API lies, and `AXManualAccessibility` arming,
which measured as `attributeUnsupported` on the apps it was meant to help.

Reading through Accessibility is kept because it is worth keeping: it works in
Outlook and Mail, and since exposure is bounded by pasteboard dwell time, an
Accessibility read means *no* exposure for the most sensitive text rather than
a small one.

**Replacement is measured, and it is worse than reading.** AX write works in
TextEdit and nowhere else tried. Four web surfaces accepted a write, returned
`.success`, and changed nothing -- including a plain editable `<textarea>` in
Safari that reads 129 characters cleanly on tier 1. A TextEdit control passed
in the same run, so this is the surfaces, not the probe.

Two consequences worth carrying into M1a's shell work:

- **Read and write have different tier maps.** An app can be tier 1 for reading
  and tier 3 for writing. The ladder must be evaluated per direction, and a
  capability probe done during capture says nothing about replacement.
- **The clipboard is the only way to put a result back** into any web surface or
  Electron app. That is a wider set than reading needs, and it makes #77's
  strict mode more expensive again: strict mode would leave babelOtter able to
  *read* in Safari, Mail and Outlook but unable to *replace* anywhere except
  native AppKit text.

Still unmeasured: Chrome, the focus-taking panel variant (#52), and writes into
Outlook's message body -- the one work-critical surface that reads as a native
`AXTextArea` and might therefore accept an AX write.

## What M1a must carry from spike #30

Measured against real applications. Full detail in `docs/architecture.md` §7 and
issue #30.

1. **Capture is three tiers** — `AXSelectedText`, then WebKit's
   `AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange`, then clipboard.
2. **`AXUIElementSetAttributeValue` returns `.success` for writes that do
   nothing.** Read back and compare; report success only on a verified match.
3. **Attribute presence is not capability.** VS Code advertises every selection
   attribute and returns empty. Detect by attempting a capture.
4. **Electron needs `AXManualAccessibility` set ahead of time**; the first
   capture after enabling is expected to fail.
5. **The clipboard path is not rare.** It is the only path for Electron and for
   replacement into web content, which is why #77 was pulled into v1.

## The one thing to understand about this codebase

**Guards are verified by making them fail.** Twelve times during M0 a guard
shipped that looked protective and silently was not. That did not stop with M0:

- The inside-a-word test in `TokenProtector` used `"Item"` against the term
  `"IT"`, which passes on case-sensitivity alone — deleting the boundary check
  entirely left it green. Replaced with `"ITem"`/`"bIT"`, which now fail 4 and 2
  tests when either boundary check is removed.
- Issue #39 asks that swapping the two post-processing steps fails a test. With
  only a `ß`→`ss` rule that is not achievable: masking hides the term either way,
  so the swap is invisible. It took a rule whose pattern occurs inside the
  sentinel to make the order observable.

Every invariant added this round was checked by planting the defect and watching
the test fail. A green suite is not evidence. Neither, it turns out, is a
mutation score.
