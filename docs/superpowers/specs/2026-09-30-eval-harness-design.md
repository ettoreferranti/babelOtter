# Evaluation harness — design

**Status:** approved in conversation 2026-09-30, pending review of this document.
**Milestone:** M3 (pulled forward). **Covers:** #74, #75, #76 (epic #14).
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md` §4.14 (`FR-EVL-01`..`04`), `NFR-P8`.

## 1. Why now

Correct works end to end, but on a real learner text the default model fixed
three errors and missed four ("ich" at the start, "eine Sätze", "in Deutsch",
"probiere … um … zu"). Every prompt change so far has been checked on one or
two sentences by hand. The harness replaces that with a fixed, synthetic set of
cases scored the same way every time. Prompt and model changes can then be
measured rather than guessed.

## 2. Decisions

| Question | Decision |
|---|---|
| Scope of the first version | Correction **and** translation, on shared machinery |
| How a correction is scored | Expected fixes (with alternatives) plus must-not guards; no single-reference similarity |
| Where cases come from | Synthetic cases written for this repo (public: `NFR-P8`), reviewed by the user before commit. Real texts are inspiration only, rewritten so nothing personal or institutional remains |
| Where scoring lives | In `BabelOtterKit`: pure, TDD, mutation-gated. The CLI is a thin runner |
| Prompt variants inside one run | Out of scope. Commit a change, re-run, and compare against the saved result |

## 3. Golden set — `evals/golden/`

Two JSON files in the repo. Both are scanned by the fixture content guard
(`FixtureContentGuardTests`), which already scans `evals/`.

### 3.1 `correction.json`

```json
[
  {
    "id": "learner-jetz",
    "text": "Ich habe heute viel gemacht, und bin ich jetz sehr müde.",
    "profile": "colleagues",
    "fixes": [
      { "wrong": "jetz", "right": ["jetzt"], "category": "spelling" },
      { "wrong": "und bin ich jetz", "right": ["und bin jetzt", "und ich bin jetzt"], "category": "word order" }
    ],
    "mustNot": [],
    "clean": false
  }
]
```

- `profile` is optional (default `colleagues`). A register case sets it, for example `administration` for Sie.
- `terms` is optional (default none): do-not-translate terms for the case, which must occur in `text`.
- `right` lists acceptable alternatives. A fix counts if the text now contains *any* of them *and* no longer contains `wrong`.
- Matching is on whole words: `wrong` must not touch a letter or digit on a side where it begins or ends with one. Otherwise the correct `jetzt` would still contain the wrong `jetz`.
- `mustNot` lists strings that must not appear in the output (meaning guards, such as `"Kollegin"`).
- `clean: true` marks an error-free text (with `fixes: []`), used to measure over-correction.
- Target: about 30 cases. They cover every `ErrorCategory` at least twice, include multi-paragraph learner texts, a protected term inside a text, a Swiss ß case, and at least 5 clean texts.

### 3.2 `translation.json`

```json
[
  {
    "id": "en-de-meeting",
    "text": "Could we move Thursday's meeting to 3 pm?",
    "direction": "en-de-ch",
    "terms": ["Otterbach"],
    "reference": "Können wir das Meeting vom Donnerstag auf 15 Uhr verschieben?"
  }
]
```

- `direction` is `en-de-ch` or `de-ch-en`.
- `terms` are added to the configuration's do-not-translate list for that case.
- `profile` is optional (default `colleagues`), so translation cases can mix registers.
- Target: about 20 cases in both directions. They mix registers and lengths, and include bullet lists, multi-paragraph texts, protected terms, and de-CH targets where ß would naturally occur.

## 4. Kit — `Sources/BabelOtterKit/Eval/` (pure, TDD)

### 4.1 Case types
`CorrectionCase`, `ExpectedFix`, `TranslationCase` (all `Codable`, `Sendable`, `Equatable`). `GoldenSet.load(correction:translation:)` decodes both files and validates them. An invalid case fails loudly, naming the case id and field. Validation rules:

- ids are unique;
- every `wrong` occurs in its case's `text`;
- `right` is non-empty;
- `category` is a known `ErrorCategory` raw value;
- a clean case has no fixes;
- `direction` is known;
- every term occurs in its text;
- every `mustNot` is absent from the text;
- no `right` alternative contains `wrong` as whole words;
- a case that is not clean has at least one fix or one `mustNot`;
- the profile is a shipped profile id;
- every translation term also occurs in `reference`, and `reference` is non-empty.

### 4.2 `CorrectionScorer`
A pure function of the case plus the correction outcome (a `CorrectionResult`, or a failure).

- **Parse:** a failure is recorded with its kind (`unreadableReply`, `structureLost`, timeout, other). Recall is then 0, reported separately.
- **Recall:** the share of `fixes` where the corrected text contains none of `wrong` and at least one `right` alternative. Comparison is on the corrected text after post-processing.
- **Over-correction:** walk `WordDiff(original, corrected)`, tracking the position in the original text.
  - A `removed` segment covers a range of the original.
  - An `added` segment sits at a single point: the position where it is inserted.
  - A fix span is every occurrence of an expected fix's `wrong` in the original, widened by one character on each side, so an insertion right at its edge counts as inside.
  - Count the words (runs of letters or digits) in removed and added segments whose range or point meets no fix span.

  Reported as a count, and as the share of the original's words.
- **Guards:** each `mustNot` string present in the corrected text is a violation.
- **Categories:** for each found fix, whether some listed error item whose `original` overlaps the fix's `wrong` has the expected category. A found fix with no overlapping item is *unexplained*.
- **Clean cases:** pass only when `hasNoErrors` and `corrected == original`.
- **Warnings:** the count of `CorrectionResult.warnings`.

### 4.3 `TranslationScorer`
A pure function of the case plus the translation outcome.

- **ß absence:** a de-CH target must contain no `ß` (pass or fail).
- **Terms:** every term is present verbatim, and no sentinel bracket (`\u{27E6}`, `\u{27E7}`) remains.
- **Structure:** `StructureExtractor.extract` on the source and on the output gives the same block count and the same skeleton markers.
- **Similarity:** chrF (character n-gram F-score, n = 1…6, β = 2) of the output against `reference`, from 0 to 100. Implemented in the kit, and pinned by tests against hand-computed values.

### 4.4 `EvalSummary`
Aggregates per model. For correction:

- mean recall;
- total over-correction and its rate;
- guard violations;
- category accuracy;
- clean-case pass rate;
- parse failures by kind;
- warnings.

For translation: the ß, term and structure pass rates, and mean chrF. For both: latency median and max. `EvalSummary.delta(from:)` gives per-metric changes against an earlier summary.

## 5. CLI — `Sources/babelotter-eval/main.swift`

```
swift run babelotter-eval [--models a,b] [--only correct|translate|<case-id>,...]
                          [--repeat N] [--compare evals/results/<file>.json]
```

- **Models:** with no `--models`, every installed model is used. A model that isn't installed is skipped, with a note in the table. If Ollama can't be reached, the tool prints a clear message and exits non-zero.
- **Runs:** each case goes through the real `Corrector` or `Translator` with `Configuration.default` (plus the case's terms and profile). The idle timeout is generous (180 s). Each call is timed.
- **Progress:** one line per case (model, case id, seconds, pass/miss).
- **Output:**
  - a comparison table, one row per model, with the §4.4 metrics (and deltas under `--compare`);
  - then the misses only, one line each: missed fix, guard violated, mangled term, broken structure, parse failure;
  - `evals/results/<yyyy-MM-dd-HHmm>-<short-commit>.json` (git-ignored), with every case, output, score and latency.
- **Isolation:** never run in CI. Only the kit's scorer tests and the golden-file validation test run there.

## 6. Testing

- **Scorers, test-first**, with planted defects:
  - recall with alternatives;
  - the "wrong gone *and* right present" rule;
  - over-correction counting inside and outside fix spans;
  - guards;
  - category matching by overlap;
  - clean cases;
  - ß, terms, sentinels and structure;
  - chrF against hand-computed values;
  - summary aggregation and deltas.
- **Golden files:** a test loads both real files through `GoldenSet.load` and requires them valid. The content guard scans them.
- **CLI:** checked by one real run on the user's machine, with its output recorded in the plan's report.

## 7. Out of scope

- Comparing prompt variants within one run.
- LLM-as-judge scoring.
- A GUI.
- Running models in CI.
- Explain and Re-pitch cases, until those actions exist.
