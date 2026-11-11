# Learning goal: a weekly goal, a streak and milestones — design

**Status:** approved in conversation 2026-11-11.
**Milestone:** M4. **Covers:** #136 (epic #15), in one PR. **Builds on:** Progress (#78), History (#67–#69), my language (#81). Privacy NFRs (`NFR-P1`–`P7`) apply unchanged: everything is computed and kept on the Mac.

## 1. What it does

lingoSwen makes it easy to translate without learning anything. This feature rewards the two actions that teach: **Correct** (you wrote it yourself) and **Explain** (you read it yourself). It adds a weekly goal with a streak, a few milestones that stand for real progress, and a quiet hint on Translate.

Decided in conversation (2026-11-11): a **weekly goal and streak** plus **milestones tied to real progress** (no points, no levels); a **quiet hint** in the Translate popup, never blocking; shown in the **Progress window and as one popup line**; **on by default, with a switch**.

## 2. The rules

**A learning day** is a calendar day with at least one learning action:

- a **Correct** of at least 10 words in a language other than my language, or
- an **Explain** (which already refuses text in my language).

From the popup and the scratchpad alike. Translate and Re-pitch never count.

**The weekly goal:** learning days in the calendar week (the Mac's own calendar, so Monday to Sunday in Switzerland). Default **3 days**, settable from 1 to 7.

**The streak:** consecutive weeks in which the goal was met, counting back from this week if it is already met, else from last week. A week still running never breaks the streak. The weeks are judged against the goal as it is set now.

**Milestones**, each earned once and kept with its date:

| Milestone | Earned when |
|---|---|
| First steps | the first learning action |
| 1,000 / 5,000 / 10,000 words | that many words corrected in total (learning actions only) |
| 10 / 50 explanations | that many Explains |
| Clean text | a Correct of 100 words or more with no errors |
| *Category* tamed (*language*) | Progress's 30-day report for the language just corrected shows that category "↓" with its rate at least halved, and it had 5 or more errors in the 30 days before. Once per category and language. |
| 4 / 12 weeks in a row | the streak reaches that length |

"Clean text" and "tamed" trust the model: a correction that misses errors can earn them. They are framed as encouragement, not as a certificate (as #79 will have to be).

**The hint on Translate**, one line under the result, at most **one a day** (either kind), only for texts of 5 words or more:

- from my language into another: "Next time, try writing it in *German* yourself, then press Correct (*hotkey*)."
- from another language into mine: "Want to see how this text works? Try Explain (*hotkey*)."
- between two languages that are both not mine: no hint.

**The popup line** after a Correct or Explain, only when something moved; one line, the first that applies:

1. a milestone: "Milestone: Case tamed in German"
2. the goal just met: "Weekly goal met · 4 weeks in a row"
3. the first learning action of the day: "Learning day 2 of 3 this week"

Otherwise nothing. The line never delays or replaces the result, and is not recorded in History.

A popup saves its History record when it closes, so the line is a **preview**: the same rules applied to the log as it is when the result arrives. The log itself changes only when the record is saved (and so not at all if the popup's result is never kept, e.g. History was cleared meanwhile).

## 3. What is kept, and where

A small **learning log** in the app's preferences (where the audience and target memories already live), never in `config.json` and not in `history.sqlite`:

- the dates of the learning days (day only, no time; at most the 400 most recent, which caps the streak shown at 57 weeks for a 7-day goal and more for a smaller one),
- two totals: words corrected and explanations,
- the milestones earned, each with its date (a "tamed" one names its category and language),
- the day the last hint was shown.

**No text, no fragments, no app names.** No schema change: `history.sqlite` stays at version 2, so v1.2.0 can still open it.

- **History off:** nothing is added to the log (as Progress, the game needs History; the Progress window says so). What was earned stays.
- **The switch off:** nothing is added, no hint and no popup line are shown, and the Learning section is hidden. What was earned stays and returns when it is switched on.
- **Clear All** (History) does not clear the log: it holds none of the user's text, and the option chosen was that earned milestones stay. A **Reset…** button in the Learning section clears the log after a confirmation.
- **Retention** shorter than 60 days: "tamed" cannot be earned (Progress has no earlier period to compare with); everything else works, since the log does not depend on old records.
- Starts empty: actions from before this version are not counted.

## 4. Where it shows

**Progress window**, a Learning section above the language and period pickers:

```
┌ Progress ────────────────────────────────────────────────────────────┐
│ This week   ● ● ○   2 of 3 learning days        4 weeks in a row      │
│ Milestones  First steps · 1,000 words · Clean text · Case tamed (de)  │
│             Next: 5,000 words (3,120 so far)                [Reset…]  │
├──────────────────────────────────────────────────────────────────────┤
│ Language [Swiss Standard German ▾]   Period [Last 30 days ▾]          │
│ …                                                                     │
```

- Shown even when there are no corrections yet (an Explain alone can start a week), with "Correct or Explain a text to start your week" while the log is empty.
- "Next:" names the nearest count milestone not yet earned.
- Hovering a milestone shows the date it was earned.

**Popup:** the line of section 2 under a Correct or Explain result; the hint under a Translate result. Both in the secondary text style of the existing warnings, without an icon.

**Settings › General:** "Weekly learning goal" switch, and "Learning days a week" (1–7) beside it. In `config.json`:

```json
"learning": { "enabled": true, "daysPerWeek": 3 }
```

Optional: a file without it means on, 3 days, and is not rewritten until Settings saves. `daysPerWeek` outside 1–7 is a configuration problem, reported like the others.

**Privacy panel and PRIVACY.md:** one line saying that lingoSwen keeps the days on which you corrected or explained a text, two totals and the milestones earned, in its preferences, with no text; and how to reset it.

## 5. Structure

- **Kit** (mutation-tested; every new file in `mutation.yml` PASS1):
  - `LearningSettings`: `enabled`, `daysPerWeek`, the defaults and the validation; `Configuration.learning` (optional) and `Configuration.learningSettings`.
  - `LearningLog`: the Codable state of section 3, with the 400-day bound.
  - `LearningRules`: pure functions. Whether a `HistoryRecord` is a learning action; the log after it; the week's days and the streak for a log, a goal, a date and a `Calendar`; the milestones a record newly earns (given the log, and for "tamed" the `ProgressReport` for the record's language); the popup line; the next count milestone.
  - `Milestone`: the kinds above and their display names.
  - `TranslateHint`: which hint, if any, for a direction, my language, a word count, the log's last hint day and today.
  - `SettingsEditor` gains the switch and the days.
- **App** (thin):
  - `LearningTracker`: the log in `UserDefaults`, as JSON under one key; the preview for the popup, and the log's update when `HistoryRecorder` reports a saved record (`onSaved`, so only while History records). For a Correct it reads `corrections(since:)` for the "tamed" check, as Progress does.
  - `PopupModel` / `PopupView`: the line and the hint (one per popup and direction: Regenerate keeps it, Swap does not show a hint about the other direction). `ScratchpadModel` records through the same recorder, so its actions count; the scratchpad shows no line and no hint.
  - `ProgressReportView`: the Learning section; `ProgressModel` reads the log and reloads on `onRecord`.
  - `GeneralSettingsView`, `PrivacyWindow`.

## 6. Out of scope

- Points, levels, leaderboards, anything shared between people.
- Notifications, menu-bar badges, the mascot celebrating, sounds.
- A "try it yourself first" mode on Translate (two model calls, a new popup state); a candidate for its own story.
- A level estimate and drills (#79).
- A line or hint in the scratchpad window.
- Counting actions from before this version.

## 7. Tests and manual checks

- Unit tests: what counts as a learning action (action, my language, the 10-word floor); one day counted once; week boundaries with a Monday-first and a Sunday-first calendar, and across a year end; the streak (this week met, this week running, a gap, a changed goal); every milestone's threshold and that each is earned once; "tamed" from a `ProgressReport` (halved, not halved, under 5 before, unreliable); the popup line's precedence; the hint's directions, word floor and once-a-day rule; the log's 400-day bound and JSON round trip; `learning` absent, valid and invalid in `config.json`.
- Manual checks, in HANDOFF: Explain a text and see "Learning day 1 of 3"; a second action the same day shows nothing; Correct a 100-word clean text and see the milestone; translate from my language and see the hint once, not twice; the Progress section and Reset…; the switch off hides everything and on brings the milestones back; History off adds nothing; Clear All leaves the log. The checks add to the real learning log; Reset… is the way back.
