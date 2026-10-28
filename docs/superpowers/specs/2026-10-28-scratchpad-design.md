# Scratchpad window — design

**Status:** approved in conversation 2026-10-28.
**Milestone:** M4. **Covers:** #84 (epic #15), in one PR. **Parent spec:** `2026-09-18-babelotter-design.md`; the privacy NFRs (`NFR-P1`–`P4`) and the built-in server gate (#126) apply unchanged.

## 1. What it does

A window where you type or paste a text, choose an action, and read the result beside it, without a host application. It is for longer passages and for iterating: change the audience or the style note, run again, compare.

Decided in conversation (2026-10-28): runs on a **Run** button, never while typing; long texts are **chunked by paragraphs**; opened from the **menu only**; **every finished run** is one History record.

## 2. The window

```
┌ Scratchpad ─────────────────────────────────────────────────────────┐
│ [Translate ▾]  German → English ⇄   Audience [Colleague ▾]          │
│ Style note [ shorter, no jargon                         ]  [Run ⌘↩] │
├──────────────────────────────────┬──────────────────────────────────┤
│ source (editable)                │ result (read-only, selectable)   │
│                                  │                                  │
│                                  │                                  │
├──────────────────────────────────┴──────────────────────────────────┤
│ Chunk 2 of 4…                         [Stop]              [Copy]    │
└─────────────────────────────────────────────────────────────────────┘
```

- **Opened** from a new menu-bar item **Scratchpad…**, placed after the four actions. One window; opening it again brings it to the front. Resizable, frame remembered.
- **Action picker:** Translate, Correct, Explain, Re-pitch. Each shows the same controls the popup shows for it:
  - Translate: direction (detected from the source, swap, and the target menu with three or more languages), audience (inferred or chosen), style note.
  - Re-pitch: audience, style note.
  - Correct: audience, style note; the result shows the corrected text with the popup's diff, then the errors and suggestions.
  - Explain: style note; the result is the explanation, in my language.
  - When detection is unsure or the language is off, the popup's questions appear in the bar above the panes instead of in a popup.
- **Run** (button, Cmd-Return) is the only thing that sends text. Changing the action, direction, audience, style note or the source never runs by itself; the old result stays until the next run, and is marked **Out of date** once anything it depends on changed.
- **Stop** cancels a run. Chunks already done stay visible, marked as partial, and **Run** becomes **Continue** (section 3).
- **Copy** copies the whole result (for Correct, the corrected text; for Explain, the popup's copy text). There is **no Replace**: there is no host app to paste into.
- **No capture, no Accessibility.** The text comes from the window only, so the scratchpad works before Accessibility is granted.
- **Server gate:** as for hotkeys, Run is disabled until the readiness check passes (built-in server running, model present); the bar says why and offers the readiness remedy.
- **Text is kept while lingoSwen runs** (closing hides the window) and **never written to disk**, except through History as below. Quitting clears it.

## 3. Long texts: chunks

Today a text goes to the model in one request. For the scratchpad, the source is split into **chunks** and run chunk by chunk.

- **Splitting** (`ChunkPlanner`, kit, pure): the text is cut only at blank lines, so a paragraph is never split. Paragraphs are packed in order into chunks of at most **1,500 characters**; a single paragraph longer than that is a chunk of its own. The blank lines between chunks are kept verbatim and put back when the results are joined, so the result has the source's paragraph structure. Inside a chunk, today's block structure (lines, lists, indents) applies as it does now.
- **Order:** chunks run one after another, never in parallel (one model, one machine). Each chunk's result appears as soon as it is done; the bar says "Chunk 2 of 4…".
- **One decision per run, not per chunk:**
  - Translate: the direction is detected once on the whole text. With an inferred audience, the first chunk infers it and the remaining chunks use that profile as fixed, so the whole text has one register. The bar shows the inferred audience as the popup does.
  - Re-pitch, Correct: the language is resolved once on the whole text; the audience is the one chosen.
  - Correct: errors and suggestions of all chunks are listed together, in text order; the diff is joined chunk by chunk.
- **Explain is not chunked:** an explanation of chunk 3 alone would lose the text's point. Explain runs on the whole text up to **6,000 characters**; above that, Run is disabled and the bar says to shorten the text or explain a part of it.
- **Timeout:** the popup's idle watchdog applies per chunk (no event for `timeoutSeconds` fails that chunk).
- **A chunk fails** (timeout, structure lost, server error): the chunks before it stay, the bar shows the popup's message for that failure, and **Run** becomes **Continue**, which runs from the failed chunk on with the same settings. Changing anything turns it back into Run, from the start.
- Short texts are one chunk, so they behave exactly like the popup.

## 4. History

- Each run that finishes (all chunks) is **one record**: the whole source and the whole result, with the action, languages, profile and model, as the popup records them. Stopped or failed runs record nothing.
- The app column says **Scratchpad** (no bundle ID). History's search and retention treat it like any other record; with History off, nothing is recorded.

## 5. Structure

- **Kit** (mutation-tested, listed in `mutation.yml` PASS1):
  - `ChunkPlanner`: split into chunks with their separators, and join results back.
  - `ChunkedRun`: drives one action over the chunks through the existing `Translator`, `Corrector` and `Explainer` entry points (which already take a `UserText`, no capture), fixing the audience after the first chunk, merging Correct's results, and resuming from a failed chunk. It emits per-chunk events for the window.
  - `ScratchpadPolicy`: what Run, Continue, Stop and Copy allow in each state, the Explain cap, and when a result is out of date.
  - `HistoryRecord` gains a scratchpad source (app name "Scratchpad", no bundle ID).
- **App:** `ScratchpadWindow` (an `AppWindow` with an `NSHostingController`, like History) and `ScratchpadModel`, which reuses the popup's controls and its error wording (`PopupModel.describe…`, moved where both can use them), and the readiness gate from `AppDelegate`.
- The popup itself does not change.

## 6. Out of scope

- Opening the scratchpad with the current selection, or by hotkey (can follow if colleagues ask).
- Saving or loading scratchpad texts as files.
- Editing the result in place, or Replace.
- Chunking in the popup (selections stay one request, as today).
- Raising the model's context window (`num_ctx`): chunks keep each request near the size the popup already handles.

## 7. Tests and manual checks

- Unit tests for `ChunkPlanner` (blank-line splitting, packing, an over-long paragraph, separators round-trip byte for byte, CRLF, leading/trailing blank lines), `ChunkedRun` (audience fixed after chunk 1, Correct merge order, resume from the failed chunk, Stop), `ScratchpadPolicy` (every state × button, the Explain cap, out of date) and the History record.
- Manual checks, in HANDOFF, with the real model: a one-paragraph text per action; a ~5,000-character German text translated to English (several chunks, one audience, paragraphs kept); Stop mid-run; a Continue after stopping the server mid-run; Run disabled while the built-in server starts; History shows Scratchpad records; the window works with Accessibility off.

## 8. Changed while building

- The Into menu shows only with three or more languages, as in the popup; with two, the direction is detected and Swap reverses it. A Swap holds until the source text changes.
- A Run that sends nothing ("This is already in English.") says so in the bar and leaves the result on screen as it was.
- Return in the style note does not run; only Run and Cmd-Return do.
- Continue reuses the configuration the run started with, so one text never mixes two models, and its History record names that model.
- Stop pressed after the last chunk is in does nothing: the joined result is already on its way.
