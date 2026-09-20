# Handoff — state as of 2026-09-20

Read this first if you are picking babelOtter up in a new session.

## Where things stand

**M0 Foundations is merged to `main` and closed.** The 27 commits landed as a
single `--no-ff` merge, so the milestone reads as one unit with every commit
intact. `main` is green.

**M1a's pure core is merged to `main`.** It is the whole translation pipeline
except the parts that touch the outside world: no Accessibility, no clipboard,
no network, no UI. All of it runs in CI.

| | |
|---|---|
| Branch | `feat/m1a-core`, merged to `main` 2026-09-20 |
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

   **#77 needs rewriting.** "Strict Accessibility-only mode" now means "cannot
   replace anywhere except TextEdit", which is not a product. It is still worth
   having as an opt-in for someone who wants the guarantee absolute, but its
   cost is now known and its description is out of date.

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
