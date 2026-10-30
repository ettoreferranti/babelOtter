# Progress: recurring mistakes over time — design

**Status:** approved in conversation 2026-10-30.
**Milestone:** M4. **Covers:** #78 (epic #15), in one PR. **Builds on:** History (#67, #68, #69) and Correct's error categories (`FR-COR-02`). Privacy NFRs (`NFR-P1`–`P7`) apply unchanged: everything is computed on the Mac, from the History file.

## 1. What it does

A **Progress…** window shows which kinds of mistakes Correct keeps finding in your writing, how often per 100 words, whether that is going down, and concrete examples. It turns History's corrections into something to work on.

Decided in conversation (2026-10-30): keep each error **with its fragments**, tied to its History record; a **Progress…** menu item with its own window; frequency **per 100 words**; **errors only** (not suggestions), **per language**.

Only corrections made from this version on count: History has never stored the errors, and re-deriving them would mean running the model again. The window says so while there is little data.

## 2. What is kept

For every Correct result recorded in History (popup and scratchpad alike), and only when History records at all:

- on the record: the **number of words** corrected (the original text, split on whitespace, counting pieces with a letter or digit);
- one **mistake** per item Correct marked as an error: its category, the fragment before and after ("der Kollege" → "dem Kollegen"), and its explanation. Suggestions are not kept.

Mistakes live and die with their record: retention, Clear All and History off apply to them exactly as to the record's text. Nothing new leaves the History file.

**Schema 2** (`history.sqlite`, now `user_version = 2`):

- `records` gains `word_count INTEGER` (NULL for everything but Correct).
- a new table `mistakes (id, record_id, category, original, corrected, explanation)`, with an index on `record_id`, and a trigger that deletes a record's mistakes when the record is deleted, so the existing `DELETE`s (retention, Clear All) cover them; `secure_delete` and Clear All's `VACUUM` already apply to the whole file.
- A version 1 file is migrated in place on open (one transaction: the column, the table, the index, the trigger, the version). A file from a newer build is refused as today.
- **Going back:** v1.1.0 refuses a version 2 file (History shows its existing "made by a newer lingoSwen" problem) until the newer build is run again. Nothing is lost.

## 3. The window

```
┌ Progress ────────────────────────────────────────────────────────────┐
│ Language [Swiss Standard German ▾]   Period [Last 30 days ▾]          │
│ 4,210 words corrected · 3.1 errors per 100 words (↓ from 3.8)        │
├──────────────────────────────────────────────────────────────────────┤
│ Case            41  · 1.0 per 100 words  ↓ from 1.4   ▂▄▃▂▁          │
│   "mit der Kollege" → "mit dem Kollegen": mit takes the dative …     │
│   "für dem Projekt" → "für das Projekt": für takes the accusative …  │
│ Gender          18  · 0.4 per 100 words  → steady     ▁▂▁▂▁          │
│ Word order      11  · 0.3 per 100 words  ↑ from 0.1   ▁▁▂▂▃          │
│ …                                                                     │
└──────────────────────────────────────────────────────────────────────┘
```

- **Opened** from **Progress…** in the menu, after History…. One window, rebuilt from the file each time it opens and when a record is saved while it is open.
- **Language:** the languages with corrections in the file, the most corrected first; remembered between openings.
- **Period:** Last 7 days, Last 30 days (default), Last 90 days. The trend compares it with the period of the same length just before it.
- **Summary line:** words corrected in the period, errors per 100 words, and the trend.
- **One row per category** with at least one error in the period, most frequent first: the count, the rate per 100 words, the trend against the previous period, and a small chart of the rate per week (per day for 7 days). Under it, the **three most recent examples** (fragment before → after, and the explanation); **Show more** lists up to 20.
- **Trend words:** "↓ from 1.4" when the rate fell by at least 20 % and at least 0.1; "↑ from 0.1" when it rose by as much; "→ steady" otherwise; nothing when the previous period had under 300 words corrected.
- **Too little data:** under 300 words corrected in the period, the rows still show but the summary says "Not enough text yet for a reliable rate" and no trend is shown.
- **Empty:** with History off, "Progress needs History. Turn it on in Settings › General."; with no corrections yet, "Correct a few texts and your patterns appear here. Corrections from before this version are not counted."
- Categories are shown by name (Case, Word order, Gender, Agreement, False friend, Spelling, Register, Preposition, Other).

## 4. Structure

- **Kit** (mutation-tested, in `mutation.yml` PASS1):
  - `WordCount`: words in a text, as above.
  - `HistoryRecord` gains `wordCount: Int?` and `mistakes: [Mistake]`, filled by `init(correction:)` from the errors only; other initialisers leave them empty.
  - `HistoryStore` gains `corrections(since:)`: every Correct record from a date on, with its language, date, word count and mistakes (no source or result text). `SQLiteHistoryStore` writes and reads the new columns and table, and migrates version 1; `InMemoryHistoryStore` follows.
  - `ProgressReport`: from those corrections, a language, a period and a date, the summary, the rows, the trends, the chart series and the examples. Pure, so every rule above is a unit test.
- **App:** `ProgressWindow` (an `AppWindow` with an `NSHostingController`, like History), `ProgressModel`, and a `Progress…` menu item; `HistoryRecorder` tells it when a record is saved. Charts with Swift Charts (system framework, no dependency).
- PRIVACY.md and the Privacy panel's History line say that History also keeps the errors Correct found, with their fragments, under the same retention and Clear All.

## 5. Out of scope

- Exercises or a level estimate (#79).
- Counting corrections from before this version.
- Suggestions, Translate or Re-pitch results.
- Exporting the report.

## 6. Tests and manual checks

- Unit tests: `WordCount`; the record's mistakes are errors only; schema 2 round-trips mistakes, migrates a version 1 file with its records intact, and the trigger removes mistakes with retention and Clear All (raw file read, as #69's test does); `ProgressReport`: rates, periods, the trend thresholds, the 300-word floor, ordering, examples, per-week series, language filter, empty input.
- Manual checks, in HANDOFF: correct a few German texts with known mistakes, open Progress, see the categories and examples; switch language and period; Clear All empties Progress; History off shows the empty state; v1.1.0's History (if installed) after running this build shows the newer-file problem, and this build again restores it.
