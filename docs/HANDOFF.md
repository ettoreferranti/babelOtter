# Handoff — state as of 2026-10-23

Read this first if you are picking babelOtter up in a new session.

## Start here: v1.0.1 is released; M4 is under way

**State.** `v1.0.1` is the first signed and notarized build (#82). It is tagged locally on `main` (`0d734d5`) and handed out privately as a DMG, never through GitHub Releases. Milestones M1b, M2 and M3 are closed. M4 so far: #82 is done (`Tools/release.sh`), and #81 part 1 is merged (French and Italian; Translate with three or more languages, #117). `main` is the only branch. What lingoSwen does, in one line each: Translate, Correct, Explain and Re-pitch from a hotkey or the menu, against a local Ollama only; English, Swiss Standard German, French and Italian (the last two off by default); audience inferred from the text, with formality per target language (#110); local SQLite history with search, retention, off and Clear All; a Settings window (General, Models, Audiences, Glossary, Hotkeys); a concept glossary and a do-not-translate list; a Privacy panel; a first-run setup window. 1029 tests; mutation gate 80%.

**Next:** #81 part 2, Correct and Explain beyond German (they still assume German learners and English explanations). Then the rest of M4: #103 standalone app with a built-in MLX model (signing now works), #84 scratchpad window, #83 popup offered on selection, #80 rich-text formatting, #79 CEFR estimate and drills, #78 recurring mistakes.

**Releasing:** `git tag vX.Y.Z && Tools/release.sh` on a clean `main`; README › *Making a release*. **The Developer ID certificate expires 2027-11-22**; a release after that date needs a new one from the team's Account Holder.

**How we work** (the rhythm every feature followed):
1. Design in conversation: the open questions as multiple choice with a recommendation; then a spec in `docs/superpowers/specs/` (a short "addendum" for follow-ups), committed, and approved by the user.
2. A short plan in `docs/superpowers/plans/`, then build task by task on a feature branch, each task `swift build` + `swift test` green and its own commit. Kit logic goes in `Sources/BabelOtterKit` with tests (it is under the mutation gate); the app stays thin.
3. A fresh-context review agent over `git diff main...HEAD`; fix its findings, say plainly which were not fixed and why.
4. Manual checks for the user in this file (a table at the top of the update), with the risks to their real config spelled out and a way back. The user runs them after `Tools/make-app.sh --run`.
5. Push and open a PR only after the checks pass; merge only when the user says so, and only once both CI checks pass on the PR's latest commit. Then tick the issue in its epic. The user deletes branches themselves (`! git branch -d …`, `! git push origin --delete …`).

**Pitfalls learned (they cost a CI round each):**
- **CI is older than this Mac:** Xcode 16.4 / Swift 6.1.2 (mutation in `-c release`) vs local Swift 6.4. A local green build proves little. In SwiftUI views pass closures (`{ f() }`), never method references (`set: f`, `.onSubmit(f)`): 6.1.2 crashed in IRGen (PR #108). Keep `sqlite3_bind_double` calls direct (a helper stored NULL under muter, PR #106).
- **Mutation gate rules for kit code:** ASCII-only source; no comma-joined conditions in `if`/`guard`/`while`; no ternary whose condition ends in an enum member; no locks; every loop bounded by a constant or a collection, never only a runtime value (muter has no per-mutant timeout; PR #105 hung for 150 minutes).
- **Repo guards:** the networking test bans substrings such as `send(`, `connect(`, `(contentsOf:` outside `OllamaClient.swift` (name helpers `write()`, not `send()`); `NoIdentifyingReferencesTests` bans naming the author's employer in tracked files, so use invented proper nouns (e.g. "NORDA") — and keep it out of issue and PR text too, which no test checks.
- **GitHub closing keywords:** write "Closes #70, closes #71"; "Closes #72 and #73" only closes the first.
- **Swift 6 lazy properties** that refer to each other need explicit types (a "circular reference" error).
- **Bash under `set -o pipefail`:** never pipe a command into `grep -q`. `grep` exits on its first match, the writer dies of SIGPIPE (141), and the pipeline fails although it matched (#119). Capture the output first, then `grep -q <<<"$output"`.
- **Editing an issue body that contains "—"** with `${body/…/…}` in the shell silently does nothing; write the body to a file, edit it, and pass `--body-file`.

**Starting a new session:** "Read docs/HANDOFF.md and let's decide what to do next in M4." Everything above, plus the per-feature updates below, is the context.

## Update 2026-10-23: Correct and Explain beyond German (#81, part 2)

On branch `feat/correct-explain-languages`, not yet a PR. Spec `docs/superpowers/specs/2026-10-23-correct-explain-languages-design.md`, plan `docs/superpowers/plans/2026-10-23-correct-explain-languages.md`. With it, #81 is complete.

- **My language** (`Configuration.myLanguage`, absent = English; Settings › General picker; it cannot be switched off). Correct's notes and Explain's text are written in it; Correct's false-friend check is against it.
- **`TextLanguage`** decides the language Correct and Explain work on: a confident enabled guess; when unsure, the one enabled language that is not mine if there is exactly one (keeps today's en + de behaviour), unless a below-floor guess names another candidate; else ask. Explain refuses my language (`alreadyMine`).
- **Review fixes:** without the key, my language is English while it is on, else the first enabled one, so a file with English off never becomes a problem; exact codes win over base codes; switching off my language names that reason first; the prompt says the notes' examples are English when mine is not; three ambiguous golden cases reworded.
- **Corrector / Explainer** take `in: LanguageCode?`; nil resolves. `notGerman` is gone (`notEnabled`, `needsLanguage`, `alreadyMine`). The popup resolves before sending, as Re-pitch does, and reuses `language`.
- **Prompts:** learner framing ("learning X, thinks in Y") or native-speaker framing for my own language; the language's `correctionNotes` (data: German's examples moved out of code; French and Italian new; written to the file only when changed). Reply keys lost `_en` (`explanation`, `summary`).
- **Eval:** correction cases carry `language` (default de-ch); 10 French + 11 Italian cases; the runner corrects in the case's language, not via detection. `EvalFailure.notGerman` → `wrongLanguage` (old reports still load).
- `Configuration.germanLanguage` is gone.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| C1 | Today's setup (English mine, en + de on): Correct and Explain a German text; Correct a short German fragment | As before: corrections with English notes; an English explanation; the fragment is not asked about |
| C2 | Enable French; Correct a French text with two errors | Corrected in French; notes in English |
| C3 | Explain a French text | An English explanation |
| C4 | Explain an English text | "This is already in English." |
| C5 | Correct an English text with a typo | Proofread; no learner or false-friend notes |
| C6 | Set My language to Italian (enable it first); Correct a German text | Notes in Italian |
| C7 | Try to switch off the language set as My language | "… is your language; choose another first." |
| C8 | With en, de, fr on, Correct a short ambiguous text ("Ok merci") | "Which language is this?", then the correction |

**Risk to your setup:** nothing is written until you change a setting; then `myLanguage` appears in `config.json`. Set My language back to English to undo C6.

## Update 2026-10-23: sign, notarize and distribute (#82), done

Merged as #118, with a fix in #119. #82 is closed: all the checks below passed and `v1.0.1` was released. `Tools/release.sh` turns a clean checkout of a `vX.Y.Z` tag into `build/lingoSwen-X.Y.Z.dmg`: version stamped from the tag, hardened runtime, Developer ID signature, notarized, stapled, checked with `spctl`. Spec `docs/superpowers/specs/2026-10-23-sign-notarize-design.md`. The decisions that matter:

- **Builds are handed out privately, never as public GitHub Releases.** The user's Apple membership is an organization team, and a team Developer ID carries the team's name in every signature. No identity, team ID or Apple ID is committed; the script finds the identity in the keychain by prefix and uses its hash, and notarytool reads the keychain profile `lingoswen-notary`. `ReleaseSecretsTests` refuses all three shapes in any tracked file (planted-defect checked).
- **Local only.** CI signing is deferred (the org may not allow exporting the certificate); #82's CI criterion is re-scoped.
- **Gatekeeper assessments are disabled on the user's Mac** (`spctl --status`). The script then skips the `spctl` verdict with a warning instead of failing; a real Gatekeeper test needs another Mac (M3).
- `Info.plist` said 0.1.0; now 1.0.0, and releases stamp the tag's version.

**The certificate** (Developer ID Application, G2) arrived and is in the user's login keychain; `find-identity -v` lists it (M2). It only became valid once Apple's intermediate *Developer ID Certification Authority (G2)* was installed (`https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer`): Xcode normally installs it, and this project never runs Xcode. **It expires 2027-11-22** (not five years); builds already signed stay valid (secure timestamp, notarized), but a new release after that date needs a new certificate from the Account Holder, made the same way from a signing request. The notary profile is stored and works.

**Manual checks: all passed on 2026-10-23.** The first run of M3 stopped at the hardened-runtime check because of the pipefail bug (#119); after the fix, notarization was accepted. The DMG's SHA-256 is `1e2f342dd13448dff935224f04dec137fd4ac8dcb957f4e04f90f363ffc9baf4`.

| # | Do | Expect |
|---|---|---|
| M1 | On the branch, untagged: `Tools/release.sh` | Stops before building: "HEAD is not a vX.Y.Z tag" |
| M2 | When the `.cer` arrives: `security find-identity -v -p codesigning` | One `Developer ID Application:` identity listed |
| M3 | After merge, `git tag v1.0.1` on `main`; `Tools/release.sh` | Notarization accepted; the Gatekeeper-disabled warning (on this Mac); the DMG path and SHA-256 |
| M4 | Copy the DMG to a Mac with Gatekeeper on that has never built lingoSwen; open it, drag to Applications, launch | No Gatekeeper block; the setup window opens; Get Info shows 1.0.1 |
| M5 | On your Mac, quit the dev build and launch the installed one | Accessibility is asked again once (new signature); then Translate works |

**Risk to your setup:** the installed app and the dev build share the bundle ID and `~/Library/Application Support/ch.lingoswen/` (config, history); never run both at once. The Accessibility grant holds for whichever signature was granted last; to go back, quit the installed app, `Tools/make-app.sh --run`, and grant again.

## Update 2026-10-23: French and Italian; Translate with three or more languages (#81, first PR)

Merged as #117; #81 stays open for part 2. Spec `docs/superpowers/specs/2026-10-23-more-languages-design.md`, plan `docs/superpowers/plans/2026-10-23-more-languages.md`. Correct and Explain stay German-only; they are the second PR for #81, with its own design.

- **French (`fr`, vous/tu) and Italian (`it`, Lei/tu) ship switched off.** At launch, a clean `config.json` missing a shipped language (by base code, so a hand-written `fr-CH` counts) gains it, switched off, written back once.
- **Detection chooses among the enabled languages after an open screen** (`ScreenedRecognizer`): a confident guess outside them stands and is refused as before; only otherwise is the constrained guess (`NLLanguageRecognizer.languageConstraints`) used. Constraining alone turned Italian into confident German with en+de on (review finding), so Correct would have corrected it as German.
- **Three or more enabled:** the target last chosen for the detected source is used (`TargetMemory`, UserDefaults key `targetBySource`, codes only); else "Translate into:". An unknown source asks "Which language is this?" first. The header's Swap becomes a menu of the other languages. With two, nothing changes.
- **`direction(into:)` is gone**: `direction(from:into:)` takes the detected or named source; the old one took "the first other enabled language", wrong with three.
- **Golden set:** directions are data (`TranslationDirection(rawValue:)` over shipped codes); 20 synthetic fr↔en / it↔en cases; the eszett check follows the target's locale rules (the score keeps the `esszettAbsent` name).
- Tests that used `fr`/`it` as "an unconfigured language" now use `nl`/`pt`.


**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| L1 | Launch with your current config | Settings › General lists French and Italian, switched off; `config.json` now has them with `"enabled": false`; your settings unchanged (the file is re-saved in the app's format, as a Settings save would) |
| L2 | Translate English and German texts | Exactly as before, Swap included |
| L3 | Enable French; translate a French paragraph | "Translate into:" English / Swiss Standard German; pick German; the header reads "French → Swiss Standard German" as a menu |
| L4 | Translate another French text | Goes straight to German; the header menu switches it to English and re-runs |
| L5 | Translate a short ambiguous text ("ciao") | "Which language is this?", then the target |
| L5b | With only English and German on, Correct an Italian sentence | Refused as not German, as before |
| L6 | Enable Italian too; Settings › General › Run Setup Guide… to the test step | The sample translates |
| L7 | Settings › Glossary with French on | A French column; off again, it disappears and its terms stay in `config.json` |
| L8 | Disable French and Italian again | Back to two languages: Swap button, no pickers |
| L9 | Skim the 20 new French/Italian cases in `evals/golden/translation.json` | References read naturally (I wrote them) |

**Risk to your setup:** L1 re-saves `config.json` (two entries appended; formatting as a Settings save leaves it). Back it up first if you like (Settings › General › Show config.json in Finder); deleting the two entries brings them back on the next launch, switched off. Remembered targets live in the app's preferences; `defaults delete ch.lingoswen targetBySource` forgets them.

## Update 2026-10-22: a shorter menu

The menu is now: the status lines, the four actions, Settings…, History…, Privacy…, Quit. **Check Again** is gone (opening the menu already re-checks, and the status lines update in place while it is open). **Open Configuration Folder** and **Setup Guide…** moved to Settings › General, in a last section **Configuration**, as **Show config.json in Finder** and **Run Setup Guide…**; it scrolls with the form, and only the editable sections are disabled while `config.json` is broken, so these buttons always work. Also: the timeout, history-days and audience-name fields are bordered boxes (a plain field in a grouped form read as a label), and the Settings window is titled after its tab instead of "Untitled". When `config.json` has a problem, the menu's problem line still offers "Show config.json in Finder" itself. Older sections below that mention these menu items predate this change.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| M1 | Open the menu | Status, the four actions, Settings…, History…, Privacy…, Quit; no Check Again, Setup Guide or Open Configuration Folder |
| M2 | Settings › General: scroll to Configuration; press Show config.json in Finder; then Run Setup Guide… | Finder selects config.json; the setup window opens at step 1; the window title reads "General"; the timeout is a bordered box |
| M3 | Break config.json by hand (remove a comma); open Settings › General | The form is disabled, but both buttons still work; fix the file afterwards |

## Update 2026-10-22: first-run setup and re-presented steps (#70, #71); epic #13 complete

**Set Up lingoSwen** is a window of five steps — Accessibility, Ollama, Model, Hotkeys, Try it — with Continue disabled (and the reason shown) until the step checks out. Accessibility is re-read every second and Ollama every other second while the window is open, so a grant or a start is noticed without a restart. Model writes one model for every action and can download a missing one (the Models tab's code); Hotkeys is the Settings tab's view; Try it translates an editable sentence for real, and Finish is enabled only after a result. It opens by itself only on a fresh install, until Finish: `setupCompleted` in `UserDefaults` is decided once (true if `config.json` already existed, false if not) and Finish sets it true; existing installs are marked done the first time this build runs. **Setup Guide…** in the menu opens it any time, and the menu's Accessibility remedy opens its Accessibility step. When Accessibility is missing and an action is triggered, the window opens at the Accessibility step alone ("Granted - try the action again." once it is back), replacing the popup's message, which is removed. The first-launch system prompt is gone: step 1 asks for it. Kit: `Setup/SetupFlow.swift` (`SetupStep`, `SetupFlow.blocker`, `SetupGate`); app: `Setup/`. Spec: `docs/superpowers/specs/2026-10-22-onboarding-design.md`. **M3 is now down to its remaining non-epic items; see the milestone.**

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`). O1 simulates a fresh install by moving your `config.json` aside; O6 puts it back.

| # | Do | Expect |
|---|---|---|
| O1 | Quit; `mv ~/Library/Application\ Support/ch.lingoswen/config.json ~/Library/Application\ Support/ch.lingoswen/config.json.mine && defaults delete ch.lingoswen setupCompleted`; start lingoSwen | The setup window opens at Accessibility (already granted: a check, Continue enabled) |
| O2 | Walk the steps: Ollama; Model (keep the default); Hotkeys (keep); Try it: Translate; Finish | Each step shows its check; the translation streams in; Finish closes the window |
| O3 | Quit and start again | No setup window |
| O7 | Quit; `mv` config.json aside again and `defaults delete ch.lingoswen setupCompleted`; start; close the setup window at step 1 without finishing; quit and start again; then Finish it | The window opens again on the second start; after Finish it stays away (then do O6) |
| O4 | Revoke lingoSwen in System Settings › Privacy & Security › Accessibility; select text and press Control-Option-T; turn it back on | The setup window opens at Accessibility only; after turning it on it says "Granted - try the action again."; Done closes it; the hotkey works again without a restart |
| O5 | Choose Setup Guide… in the menu | The window opens at step 1 with the sidebar |
| O6 | Quit; `mv ~/Library/Application\ Support/ch.lingoswen/config.json.mine ~/Library/Application\ Support/ch.lingoswen/config.json`; start | Your settings are back |

## Update 2026-10-22: the Privacy panel and the Ollama binding warning (#72, #73)

**Privacy…** in the menu (after History…) opens a window of five lines, each marked as it should be (✓), warning (⚠) or unknown (?): the model connection (`http://127.0.0.1:11434`, loopback by construction), where Ollama listens (asked of macOS with `lsof -nP -iTCP:11434 -sTCP:LISTEN -F n`, read-only, no network call; unknown is never shown as safe), the history folder with its iCloud check and the retention in words, dependencies (`BuildFacts.thirdPartyPackages`, kept equal to the package graph by a test), and the absence of telemetry. An Ollama listening beyond this Mac gets a warning, the risk in one sentence, and `launchctl setenv OLLAMA_HOST 127.0.0.1:11434` with Copy. **Check Again** re-reads; opening the window does too. `Tools/make-app.sh` now bundles `PRIVACY.md`, which **Open PRIVACY.md** opens. Kit: `Privacy/ListeningProbe.swift`, `Privacy/PrivacyReport.swift`; app: `Privacy/`. Spec: `docs/superpowers/specs/2026-10-22-privacy-panel-design.md`. **Next in epic #13:** #70 (a first run that checks itself) and #71 (setup steps again when a permission is revoked).

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| P1 | Choose Privacy… in the menu | The window opens in front; five lines, all ✓ with Ollama running as installed |
| P2 | Quit Ollama; Check Again; start Ollama again | The lines clear and a spinner shows while checking; "Ollama listens on" shows ? and "Unknown … not a sign that it is safe", not ✓ |
| P3 | `launchctl setenv OLLAMA_HOST 0.0.0.0:11434`, quit and restart Ollama, Check Again; press Copy; then `launchctl unsetenv OLLAMA_HOST`, restart Ollama, Check Again | ⚠ "All networks (*)", the risk sentence and the command; Copy puts `launchctl setenv OLLAMA_HOST 127.0.0.1:11434` on the clipboard; after unsetting, ✓ again |
| P4 | Press Open PRIVACY.md | It opens in your Markdown app |

## Update 2026-10-21: formality per target language (#110); epic #11's stories done

An audience's `register` is now `"formal"` or `"informal"` (the old `"Sie"`/`"du"` still load; the next save writes the new values). A language carries its pronouns as data: `"addressForms" : {"formal" : "Sie", "informal" : "du"}` on de-ch, `null` on English; a language without the key gets the shipped language's forms for its code, so an existing de-ch keeps Sie/du. Prompts name the target's form (`Address the reader as "Sie".`) or, for a language without forms, the register in words (`Write in a formal register.`); the inference list and Correct follow the same rule. The popup shows "Students (Sie)" into German and "Students (formal)" into English; the Audiences tab offers Formal / Informal, and under it the form the chosen one gives in each language that has forms ("Swiss Standard German: Sie"). The audience's id is no longer shown in the tab (it stays in `config.json`). The Settings window can now be resized, and keeps its size when the tab changes. Italian or French are then one `addressForms` line each. A German written as `de`, `de-de` or `de-at` without the key gets the same forms (by base code). **No going back:** once this build saves `config.json`, a build from before #110 cannot read `"formal"` and falls back to the defaults for the whole file (and would overwrite it on its next save); keep a copy of `config.json` if you might run an older build. Spec: `docs/superpowers/specs/2026-10-21-formality-design.md`.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| F1 | Start lingoSwen; change any setting; look at `config.json` | Your audiences still load; `register` reads `"formal"`/`"informal"`; de-ch has `"addressForms"` with Sie/du, English `null` |
| F2 | Translate an English email to Students into German | Uses Sie, as before; the picker shows "Students (Sie)" |
| F3 | Translate a German text into English with Administration; then pick Informal | The picker shows "Administration (formal)"; the English is formal, then casual |
| F4 | Open Settings, Audiences; switch Students between Formal and Informal; then resize the window and switch tabs | Under the control, "Swiss Standard German: Sie", then "…: du"; no id line; the window resizes and keeps its size across tabs |
| F5 | Correct a German du-text to Students (formal) | The register error is reported as before |

## Update 2026-10-21: the Glossary tab and a concept glossary (#59, #61 third part)

The glossary is now a **concept glossary**: one row per term, one term per configured language (`"glossary": {"concepts": [{"de-ch": "Modul", "en": "module"}]}`). Translating from A to B uses every row with a term in both, so adding French adds a column, not rows. The old `entries` format still loads, one concept each, and then applies in both directions; the next save writes `concepts`. A term for a language that is not configured is kept. Settings has a fifth tab, **Glossary**: a grid with a column per language and a list of do-not-translate terms below; + adds a row saved by its first term, − deletes a row. A term is unique per language ignoring case; at most 80 characters, 200 rows, 100 do-not-translate terms. Do-not-translate matching is exact, capitals included (as before). `PromptBuilder` and `Translator` are unchanged. Spec: `docs/superpowers/specs/2026-10-21-settings-glossary-design.md`. Two-language assumptions elsewhere are now criteria on #81; per-language formality is #110 (next).

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`).

| # | Do | Expect |
|---|---|---|
| G1 | Open Settings, Glossary | A Terms grid with English and Swiss Standard German columns, your existing entry as a row; a Do not translate list with your existing term |
| G2 | Press + under Terms; type "module" under English, Tab, "Modul" under Swiss Standard German, Return | `config.json` has `{"de-ch" : "Modul", "en" : "module"}` under `glossary.concepts` |
| G3 | Translate "Please register for the module." into German; then translate the result back into English | The German uses "Modul"; the English uses "module" |
| G4 | Press + again and type "modul" under Swiss Standard German | Refused: "modul is already in another row for Swiss Standard German." |
| G5 | Add "NORDA" to Do not translate; translate "Die NORDA bietet Module an." into English | "NORDA" is unchanged in the result |
| G6 | Clear both cells of the module row; then press − on another row | Each row disappears from the grid and from `config.json` |

## Update 2026-10-21: the Audiences tab (#61, second part)

Settings has a fourth tab, **Audiences**: the list on the left, the selected audience's name, register (Sie/du), tone guidance and preferred terms (one per line) on the right, its id shown under the name. **+** asks for the name, then adds the audience (its id is made from that name); **Delete…** asks first and is disabled for the last audience; **Restore shipped audiences** adds back missing shipped ones at the end, skipping one whose name another audience now has. Text is written when the field is left (or on Return; Command-Return in the multi-line boxes). Ids are made once from the first name (`AudienceID`: "Behörden" → `behorden`, `-2` when taken) and never change. Limits: names unique ignoring case and at most 40 characters; guidance at most 2,000 characters; at most 50 terms of 80. Also fixed: a second quick edit in the window was refused as "changed on disk" while the watcher settled; the window now applies its own save at once. Spec: `docs/superpowers/specs/2026-10-21-settings-audiences-design.md`. **Next:** the Glossary tab (#59).

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`). A2–A6 change your real audiences; Restore shipped audiences brings the shipped ones back, but an edited shipped audience keeps its edits.

| # | Do | Expect |
|---|---|---|
| A1 | Open Settings, Audiences | The four audiences in file order; Students selected shows its name, Sie, guidance and `id: students` |
| A2 | Press +; type "Behörden" and press Add; choose du; write two lines of guidance and click elsewhere | `config.json` has an audience with id `behorden`, name "Behörden", register "du" and the guidance |
| A3 | Rename "Behörden" to "Students"; click another audience; then rename it to "Ämter" | The first is refused ("Another audience is called Students."); on switching, the note under the list says "Behörden: … Not saved."; "Ämter" is written and the id stays `behorden` |
| A4 | Translate an English text and pick "Ämter" in the popup | The translation uses the du register |
| A5 | Delete Students (confirm); open a Translate popup; then Restore shipped audiences | Students is gone from the popup's picker; Restore brings it back at the end of the list |
| A6 | Delete audiences until one is left | Delete… is disabled for the last one |
| A7 | In General, switch the clipboard option on and off twice quickly | Each click is written; no "changed on disk" message |
| A8 | With another app's window in front (e.g. Safari, full size), choose Settings… in the menu; close it; then choose History… | Each window opens in front of Safari, not behind it |

## Update 2026-10-20: the settings window, first part (#61, #60)

**Settings…** in the menu (above History…) opens a window with toolbar tabs. **General:** a switch per language (at least two stay on), history (keep for N days, unlimited, off), the request timeout (5–600 s), the clipboard switch. **Models (#60):** a pop-up per action of the models Ollama has installed; a configured model that is not installed shows Download…, which asks first and then shows progress. **Hotkeys:** click a shortcut and press the new one; lingoSwen's own hotkeys are suspended while a recorder listens; Clear makes an action menu-only, Default restores it. Every change goes through `SettingsEditor` (kit) and is written to `config.json` at once; the watcher applies it like a hand edit. While `config.json` has a problem, the window shows it and is read-only. Kit: `Settings/SettingsEditor.swift`, `HotKeyText.swift`, `ModelChoice.swift`; `HotKeyBindings.set(_:for:)`. App: `Settings/`, `AppWindow` (shared key handling, now also History's base class). Spec: `docs/superpowers/specs/2026-10-20-settings-window-design.md`. **Next:** the Audiences tab, then the Glossary tab (#59), each with a short design addendum first.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`). The window's layout has not been seen by anyone yet; S1 is the first look.

| # | Do | Expect |
|---|---|---|
| S1 | Choose Settings… in the menu; click through the three tabs | The window comes forward; General, Models and Hotkeys each lay out without clipping |
| S2 | General: switch off English; set Keep records "For a number of days" and type 30, Return; type 3 in the timeout, Return | English is refused ("At least two languages stay on."); `config.json` shows `"retentionDays" : 30`; 3 is refused with "Between 5 and 600 seconds" and the file keeps its value |
| S3 | Models: choose another installed model for Explain; run Explain | `config.json` has it under `models`; Explain uses it |
| S4 | Write a model that is not installed into `config.json` by hand (e.g. `"explain" : "qwen3:0.6b"`); open Models; Download…, confirm | It is listed as not installed; the download shows progress and the row becomes a normal choice; the menu's missing-model line goes |
| S5 | Hotkeys: click Translate's shortcut and press Control-Option-T; then Control-Option-C; then Shift-K; then click it and press Escape | Control-Option-T records without starting Translate; Control-Option-C is refused ("Already the Correct hotkey."); Shift-K is refused ("Use Command, Control or Option with the key."); Escape cancels |
| S6 | Hotkeys: record Control-Shift-Y for Explain; select German text in Mail and press it; then click Default | Explain runs; Default restores Control-Option-E |
| S7 | Click a recorder, then switch to another app with Command-Tab; press Control-Option-T there | Recording stopped when the window lost focus; Translate runs |
| S8 | Break `config.json` by hand (remove a comma); look at the window; fix it | The window shows the problem and nothing can be changed; after the fix it is editable again |
| S9 | Quit Ollama; open Models | "Ollama isn't running"; each action's model is shown as text |

## Update 2026-10-20: retention, off and Clear All (#69); epic #12 complete

`retentionDays` in `config.json` takes a number of days (default `90`), `"unlimited"` or `"off"` (words trimmed, any case); anything else is a config problem naming the three forms. With days, older records are deleted at launch, when a saved change applies, and after each saved record. `"off"` records nothing and keeps existing records; the menu shows "History: off" above History... (information, the icon is unchanged) and the window says "History is off - nothing new is saved." If `config.json` could not be read at launch, history is paused: nothing recorded or deleted, menu "History: off until config.json is fixed"; a mid-session problem keeps the previous settings and their retention. **Clear All…** in the History window asks "Delete all <n> records? This cannot be undone." and then deletes under `secure_delete` and `VACUUM`s. Kit: `Config/HistoryRetention.swift`, `History/HistoryPolicy.swift`, `HistoryStore.deleteOlder/deleteAll/count`, `HistoryBrowser.clearAll/count`. History problems are now whole menu lines (`HistoryProblem.notSaved`, `.pruning`); the readiness cause shows the line as given. App: `ConfigurationSource.isFallback`, `HistoryRecorder.apply(_:)`. The journal limit is in `PRIVACY.md`. Spec: `docs/superpowers/specs/2026-10-20-history-retention-design.md`.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`). The seed command for C1 is the one under #68 below; `config.json` is in `~/Library/Application Support/ch.lingoswen/`.

| # | Do | Expect |
|---|---|---|
| C1 | Seed the 5,000 records; open History; press Clear All…, then Cancel; then Clear All… and Delete | The alert names 5,000 and more; Cancel (or Escape) keeps everything; Delete empties the list at once; `ls -l` shows a small `history.sqlite` and no `-journal` |
| C2 | Set `"retentionDays" : "off"` and save; open the menu; translate something and press Escape; open History | The menu shows "History: off" and the icon is unchanged; no new record; the window says "History is off - nothing new is saved." and lists the old records |
| C3 | Set `"retentionDays" : 1`; quit; `sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite "insert into records (created_at, action, source_language, model, source_text, result_text) values (strftime('%s','now') - 172800, 'translate', 'en', 'm', 'old', 'old')"`; start lingoSwen; open History | The old record is gone; today's records are listed |
| C4 | Quit; set `"retentionDays" : "nope"`; start lingoSwen; translate and press Escape; fix the file and save; translate and press Escape | The menu shows the config.json problem and "History: off until config.json is fixed"; no row is added; after the fix, the line goes and the next translation is recorded |
| C5 | Set `"retentionDays" : "unlimited"`; restart | Nothing is deleted; the menu has no history line |

## Update 2026-10-20: history can be browsed and searched (#68)

**History…** in the menu (above Check Again) opens a normal window: a search field and the records newest first on the left (action, languages, time, the source's first line), the selected record on the right (source and result, each with Copy, then audience, app, model and date). The list loads 200 at a time as you scroll. Search covers source and result, ignoring case and accents ("uber" finds "Über", "strasse" finds "Straße"), 150 ms after typing stops. A record saved while the window is open appears at the top. If the database could not be opened, the window says "History is not saved - <reason>". Command-W, -F, -C, -V, -X, -A and -Z are handled by the window itself, as lingoSwen has no main menu. Kit: `HistorySearch` (one matching rule; SQLite calls it as the registered function `lingoswen_contains`), `HistoryCursor` and `HistoryStore.page(matching:before:limit:)`, `HistoryBrowser` (paging, search, refresh), `HistoryRow` (labels). App: `Sources/BabelOtterApp/History/`. `.gitignore` now names back in any `History/` folder under `Sources` or `Tests`. Spec: `docs/superpowers/specs/2026-10-20-history-window-design.md`. Next: #69, retention, Clear All and "off" (criterion added 2026-10-20); note `Configuration.retentionDays` (default 90) exists but nothing reads it yet.

**Manual check (yours).** Rebuild first (`Tools/make-app.sh --run`). For W2, seed 5,000 made-up records with lingoSwen quit; delete them afterwards with `sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite "delete from records where model = 'seed'"`:

```sh
sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite "with recursive n(i) as (select 1 union all select i + 1 from n where i < 5000) insert into records (created_at, action, source_language, target_language, profile_id, model, source_text, result_text) select strftime('%s','now') - i * 600, 'translate', 'en', 'de-CH', 'colleagues', 'seed', 'Seed record ' || i || ' about the Uber meeting', 'Testeintrag ' || i || ' zur Über-Sitzung' from n;"
```

| # | Do | Expect |
|---|---|---|
| W1 | Open the menu, choose History… | The window comes to the front, newest record first, each row with action, languages, time and first line |
| W2 | Scroll to the bottom repeatedly | More rows load each time; scrolling stays smooth; seed record 5000 is reached |
| W3 | Type `uber` in the search field | Only records containing "Uber" or "Über" are listed; clearing the field lists everything again |
| W4 | Select a record; press Copy under Result; paste in TextEdit | The detail shows source, result, audience, app, model and date; the result is pasted |
| W5 | Leave the window open, translate something and press Escape | The new record appears at the top; the selected record stays selected |
| W6 | Command-F, type, Command-A, Command-C, Command-V; select words in the Result text, Command-C, paste in TextEdit; then Command-W | Each works in the search field; the selected words are pasted; Command-W closes the window; History… opens it again at the same size |
| W7 | Quit; in `~/Library/Application Support/ch.lingoswen/`, `mv history.sqlite history.sqlite.keep && echo junk > history.sqlite`; start lingoSwen, choose History…; quit; `mv history.sqlite.keep history.sqlite` | The window shows "History is not saved - could not open the database (file is not a database)" |
| W8 | Search something, minimize the window; translate something and press Escape; choose History… | The window comes back with the search and selection kept, and the new record listed if it matches |

## Update 2026-10-19: history is recorded (#67)

Each popup's last finished result is written to `~/Library/Application Support/ch.lingoswen/history.sqlite` when the popup closes: source, result, action, languages, audience, model, time and source app. Regenerate replaces the pending record rather than adding one; a popup closed before anything finished records nothing. The file is `0600`, excluded from backup, `secure_delete` on, rollback journal (no `-wal`). If the database cannot be opened or a write fails, the menu shows "History: not saved - <reason>" and everything else works. Kit: `BabelOtterKit/History/` (`HistoryRecord`, `HistoryStore`, `SQLiteHistoryStore` on the system `libsqlite3`, `HistoryProblem`); app: `HistoryRecorder`, `PopupModel.recordHistory()`. There is no window yet (#68), no retention or Clear All (#69). Spec: `docs/superpowers/specs/2026-10-19-history-record-design.md`.

To look: `sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite 'select id, action, source_language, target_language, profile_id, model, source_app_name, substr(result_text,1,40) from records order by id desc limit 5'`

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| H1 | Translate a text, press Regenerate, wait for it, press Escape | Exactly one new row, holding the second result |
| H2 | Press Escape while the first run is still streaming; then try Translate on a French text (refused) | No new row either time |
| H3 | Replace a translation; Copy one; Explain one and close it; then make Replace fail (quit the source app first) and Dismiss; then leave a finished popup open and quit from the menu | One new row each time, five in all |
| H4 | `ls -l ~/Library/Application\ Support/ch.lingoswen/` | `history.sqlite` is `-rw-------`; there is no `history.sqlite-wal` |
| H5 | Quit; in `~/Library/Application Support/ch.lingoswen/`, `mv history.sqlite history.sqlite.keep && echo junk > history.sqlite`; start the app, open the menu, translate something; quit; `mv history.sqlite.keep history.sqlite` | The menu shows "History: not saved - could not open the database (file is not a database)"; Translate still works; after moving the file back, history is as before |

## Update 2026-10-16: Re-pitch is built (#66); all four actions exist

Select a text and press **Control-Option-R** (or choose Re-pitch Selection in the menu). The popup shows "Re-pitch · <language>" with the audience you last re-pitched to in this app pre-selected; Return (or the Re-pitch button, or picking an audience) starts it. The result is the same text in the same language, re-aimed at that audience: form of address, register and tone change, the layout and every fact stay. Any number, date, time, link or email address from the original that is missing from the result is listed as a warning. Replace, Copy and Regenerate work as for Translate. Re-pitch remembers its own last audience per app (`repitch.` keys in `UserDefaults`), apart from Translate's. It runs through `Translator.repitch` (same pipeline, source = target, fixed audience, no glossary); the check is `BabelOtterKit/Text/FactCheck.swift`. Spec: `docs/superpowers/specs/2026-10-16-repitch-design.md`.

Local model check (about two minutes): `BABELOTTER_INTEGRATION=1 swift test --filter RepitchIntegrationTests`.

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| R1 | Select a German du-form draft in Mail, press Control-Option-R | The popup shows "Re-pitch · Swiss Standard German", your last re-pitch audience pre-selected and a Re-pitch button; Return starts it and the result streams in |
| R2 | Pick another audience; then Replace; then open the menu | It re-runs for that audience; Replace pastes the result; the menu lists "Re-pitch Selection (Control-Option-R)" |
| R3 | Select a short German text (a few words) and press Control-Option-R; pick German; type "kürzer" in the style note and press Return. Then start again and pick, in the picker, the audience already shown | "Which language is this?" appears first; Return in the style note starts the re-pitch and pastes nothing; picking the audience already shown starts it too; before a run there is no Replace, and Escape dismisses |

## Update 2026-10-15: Explain is built (#65)

Select German and press **Control-Option-E** (or choose Explain Selection in the menu): the popup, titled "Explain", streams an English summary of the meaning, then lists each idiom or tricky phrase, quoted as written, with its own note. There is no Replace; Copy takes the summary and the notes. The style note works ("focus on grammar"); there is no audience picker. Text detected as another language is refused before anything is sent. The hotkey is configurable as `"explain"` in `config.json`. The pipeline is `BabelOtterKit/Pipeline/Explainer.swift`. Spec: `docs/superpowers/specs/2026-10-15-explain-design.md`.

Local model check (about a minute): `BABELOTTER_INTEGRATION=1 swift test --filter ExplainIntegrationTests`.

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| E1 | Select a German paragraph in Mail, press Control-Option-E | The popup is titled "Explain"; the summary streams in; the notes appear when it finishes |
| E2 | In that popup, press Copy; then open the menu | No Replace button; the clipboard holds the summary and one line per note; the menu lists "Explain Selection (Control-Option-E)" and it behaves as the hotkey does |

## Update 2026-10-15: the audience is inferred from the text (#52)

Translate asks the model, in the same request, which audience the text addresses, and to quote the words that show it (`audience_evidence`). The guess counts only when that quote really occurs in the text: it is then shown beside the picker as "✦ guessed from the text, change if wrong". Otherwise the audience last picked in this app applies, then the last pick anywhere, then Colleagues, labelled as such. Evidence was added after measuring: asked only for an audience, the default model never answered "unclear" and guessed from the topic, overriding a remembered audience. Picking an audience re-runs and is remembered for that app (`UserDefaults`, ids only). Correct never infers. The rules live in `BabelOtterKit/Config/AudienceSession.swift`. Spec: `docs/superpowers/specs/2026-10-15-audience-inference-design.md`.

Local model check (about a minute): `BABELOTTER_INTEGRATION=1 swift test --filter AudienceInferenceIntegrationTests`.

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| A1 | Translate an English email starting "Dear students" | Beside the picker, "detecting..." then "✦ guessed from the text, change if wrong", with Students selected |
| A2 | Pick Colleagues in the picker | The translation runs again in the du register; the note disappears |

## Update 2026-10-14: Copy confirms (#96); the popup opens by the selection (#97)

Copy now shows "Copied" for 0.8 s before the popup closes. The popup is placed against the selection's bounds where the application reports them, else the focused window (near the pointer if it is on the same display, else near the window's top), else the pointer, as before; each Accessibility call is capped at 100 ms. The geometry is `BabelOtterKit/Popup/PopupPlacement.swift`, tested and mutation-gated; the Accessibility reading is `SelectionAnchor.swift` in the app.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| P1 | Translate, then press Copy; again with Shift-Command-C | The button reads "Copied" briefly, then the popup closes; paste gives the translation |
| P2 | Press Copy, then Escape at once | The popup closes immediately |
| P3 | Two displays: selection in TextEdit on one, pointer on the other, press the hotkey | The popup opens just below the selection, on the selection's display |
| P4 | Same in Safari or Mail | As P3 |
| P5 | Same in Teams or another Electron app | The popup opens near the top of that app's window, on its display |
| P6 | Select text near the bottom of a display | The popup opens above the selection, fully on screen |
| P7 | Trigger in TextEdit with one display | The popup still appears at once (C11) |

## Update 2026-10-13: the app is now lingoSwen, with Swen as its picture

The app the user sees is **lingoSwen**: bundle `build/lingoSwen.app`, executable `lingoSwen`, bundle ID `ch.lingoswen`, data in `~/Library/Application Support/ch.lingoswen` (moved by hand from `ch.babelotter` on the one dev machine; there is no migration code). Swen (`Tools/app/Mascot.png`) replaces the otter emoji in the menu bar and popup header and is the app icon, which `Tools/make-app.sh` generates from the same picture. The repo, the Swift package and module names (`BabelOtterKit`, `BabelOtterApp`, `babelotter-eval`), the signing identity "babelOtter Dev" and the design docs keep the old name.

M1b manual checks C1-C15 ran on 2026-10-13: #48, #49, #50, #51 and #54 are closed. C8 and C13 failed as expected and continue as #96 (Copy confirms) and #97 (popup on the selection's display). Left in M1b: #52, #96, #97.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| R1 | Look at the menu bar | Swen, in colour, where the otter was; with Ollama stopped, the triangle beside it |
| R2 | Open the menu | "Quit lingoSwen"; the hover tip reads "lingoSwen: ready" |
| R3 | Translate a selection | The popup header shows Swen and "lingoSwen" |
| R4 | System Settings > Privacy & Security > Accessibility | lingoSwen with Swen's icon; grant it (it is a new app to macOS) and remove the old babelOtter entry |
| R5 | Show config.json in Finder | Opens `ch.lingoswen`, holding your config with the hotkeys, glossary and do-not-translate entries |

## Update 2026-10-12: hotkeys are configurable and config.json reloads live (#26)

Hotkeys are set in `config.json` under `hotkeys` (`"translate": "control+option+T"`, `null` for none) and resolved through the current keyboard layout. Every save to `config.json` applies within about half a second; a broken file or hotkey keeps what was in use and shows as a readiness cause with **Show config.json in Finder**. Design: `docs/superpowers/specs/2026-10-12-configurable-hotkeys-design.md`.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| H1 | Change `translate` to `control+option+Y` and save | Within a second the menu reads "Translate Selection (Control-Option-Y)"; Control-Option-Y translates; Control-Option-T no longer does |
| H2 | Save `config.json` with a missing comma | Triangle; header "config.json: … still using the previous settings" with "Show config.json in Finder"; translating still works. Fix it: ready |
| H3 | Set `translate` to `contrl+option+T` | Triangle; the header names "contrl"; Control-Option-T still translates |
| H4 | On the Swiss German layout, set `translate` to `control+option+Z` and press the key labelled Z; switch to the US layout and press the key labelled Z | It translates both times |
| H5 | Set `correct` to `null` | The menu item reads "Correct Selection"; Control-Option-C does nothing |
| H6 | Set both to `control+option+T` | Header "…is also the Translate hotkey"; Control-Option-C still corrects |
| H7 | Change `models.translate` to a model that is not installed | Within a second, triangle and "Translate: … isn't installed" |
| H8 | Move `config.json` to the Desktop, then back | Header "config.json: the file is missing…", then ready again |
| H9 | Edit `config.json` once in TextEdit and once in VS Code | Both saves apply |
| H10 | Swap the two hotkeys in one save | Control-Option-C translates and Control-Option-T corrects; no "is also" header |

## Update 2026-10-12: closing M1b

#27 is closed. Still to build: #26 (hotkeys you can assign, applied without a restart) and #52 (audience inferred from the source text, profile remembered per app). The stories below are built; one manual pass decides whether they close.

**Manual checks for #48, #49, #50, #51 and #54.** Run on `main` with Ollama up and the default models installed. Tick each that holds; note any that do not.

| # | Story | Do | Expect |
|---|---|---|---|
| C1 | #54 | In Mail, select a paragraph of English in a message you are writing, press Control-Option-T | The popup streams a de-CH translation; Replace puts it in place of the selection |
| C2 | #54 | Translate a few paragraphs with a bulleted list | Paragraphs and list markers survive |
| C3 | #54 | Translate English containing "street" or "large" | No `ß` anywhere in the German |
| C4 | #54 | Translate text containing a do-not-translate term and a glossary term from `config.json` | The first appears verbatim; the second uses the configured rendering |
| C5 | #49 | Translate a typical paragraph and watch the popup | First words appear within about 2 s; the view follows the text without flicker; a spinner shows while it streams |
| C6 | #49 | Watch the end of a stream | The streamed text is replaced by the final, post-processed text (for example `ß` gone) |
| C7 | #50 | Look at Replace and Copy while streaming, then after it finishes | Disabled while streaming, enabled when finished |
| C8 | #50 | Press Copy (or Shift-Command-C) on a finished result | The final text is on the clipboard. **Known gap:** the popup closes at once with no confirmation; the criterion asks the popup to confirm |
| C9 | #50 | Press Regenerate on a finished result | A new translation runs with the same direction, profile and style note |
| C10 | #50 | Press Escape while it streams | The popup closes and the request stops (Ollama's CPU/GPU load drops) |
| C11 | #48 | Trigger in TextEdit with a selection | TextEdit stays frontmost (its menu bar stays), the selection stays selected, and the popup appears near the mouse pointer, fully on screen, before any text arrives (aim: under 150 ms) |
| C12 | #48 | After capture, type in the popup's instruction field and press Return | Typing goes to the popup; TextEdit stays frontmost; babelOtter never becomes the active app |
| C13 | #48 | With two displays: selection on one, mouse pointer on the other, press the hotkey | **Likely gap:** the popup goes to the pointer's display, not the selection's. Passes only if both are on the same display |
| C14 | #51 | Translate one short word whose language is ambiguous (for example "Hand") | The popup asks which language to translate into instead of guessing |
| C15 | #51 | On a finished translation, press Swap in the header | It re-runs in the opposite direction; `config.json` is unchanged |

C8 and C13 are expected to fail as the code stands; if they do, they are small follow-ups on #50 and #48 rather than reasons to keep the whole story open.

## Update 2026-10-08: readiness is built (#28, #29, the #26 bug)

The menu bar icon shows readiness: the otter alone is ready, a triangle is degraded, a stop sign is blocked. The menu names each cause above the configuration line. Blocked means only that Accessibility is missing; Ollama unreachable, a missing model, an unregistered hotkey and a hotkey clashing with a system shortcut are degraded. Checks run every 30 s and on menu open, action trigger and wake. An action without Accessibility opens the popup with **Open System Settings**; the system prompt runs at first launch only.

Spec: `docs/superpowers/specs/2026-10-06-readiness-design.md`. Plan: `docs/superpowers/plans/2026-10-08-readiness.md`.

**Measured 2026-10-08:** `CopySymbolicHotKeys` reports Carbon modifier bits (Command-Shift-3 is key code 20, `0x300`); function and arrow keys add `0x20000`. Carbon hotkeys are non-exclusive, so registration never fails because another app holds the combination, and no API lists other apps' hotkeys.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| M1 | Revoke Accessibility for babelOtter in System Settings | Within 30 s: stop sign; menu starts with the header "Accessibility isn't granted" and "Open Accessibility Settings…" under it |
| M2 | With it revoked, press Control-Option-T in any app | Popup explains; Return or the button opens the Accessibility pane and closes the popup; Escape dismisses |
| M3 | Grant it again | Within 30 s: the otter alone, header "Ready"; no dialog |
| M4 | Stop Ollama (`pkill ollama` or quit the app) | Within 30 s: triangle; header "Ollama isn't running" with "Start Ollama". Click it: Ollama launches and the menu reads "Ready" within a few seconds |
| M5 | Set `models.correct` in `config.json` to a model that is not installed, relaunch | Triangle; header "Correct: ... isn't installed" with "Copy “ollama pull ...”"; clicking it puts the command on the clipboard. Restore it |
| M6 | Pause Ollama (`pkill -STOP ollama`), wait 90 s, open the menu, then `pkill -CONT ollama` | No hang and no pile-up: the menu opens at once, and the status updates once the probe times out or Ollama resumes |
| M7 | Keep the menu open across a status change (open it, then stop Ollama and click Check Again) | The lines change in place; no duplicated header or command |
| M8 | Remove the `correct` entry from `models` in `config.json`, relaunch | Ready (the default model is checked, not skipped), assuming it is installed |
| M9 | With Accessibility revoked, press Control-Option-T three times quickly | One popup, replaced each time; nothing is captured |
| M10 | In System Settings › Keyboard › Keyboard Shortcuts, assign Control-Option-T to a Screenshots entry | Within 30 s: triangle; header "Control-Option-T is also a system shortcut" with "Open Keyboard Shortcuts Settings…", which opens that pane Press it and note which one fires; record that in `docs/architecture.md` section 7. Restore the shortcut: ready again |

## Update 2026-10-05: the evaluation harness is built

**Run it** from the repository root, with Ollama running:

```sh
swift run -c release babelotter-eval [--models a,b] [--only correct|translate|<case-id>,...] [--repeat N] [--compare evals/results/<file>.json]
```

The default model is `mistral-small3.2:24b`. Each run writes one JSON file to `evals/results/` (git-ignored), named by date, time to the second and commit, for example `2026-10-05-113545-ea862df.json`. `--compare <file>` prints per-model deltas against that saved run, over the cases both runs share; it names the baseline and any case it could not compare. With `--repeat N`, counts are per run and a miss reads "(k/N runs)". The tool exits 2 if every case failed.

**Run-to-run variance is real** (`miss-ich-klein` passed on 2026-10-02 and missed on 2026-10-05), and a single run is not a baseline. **Compare against a `--repeat 3` run, at `--repeat 3`.** Before the false-friend rule (`ea862df`), three correction runs gave: recall 81.1%, over-correction 0.3%, category accuracy 85.3% (not the single run's 88.2%), clean pass 100% (`2026-10-05-113545-ea862df.json`). **With the false-friend rule** (below), the current baseline is recall 87.5%, over-correction 0.4%, category accuracy 81.3%, clean pass 100%, guard violations 0 (`2026-10-05-133719-b59d4c7-dirty.json`; "dirty" only because a throwaway probe test was in the tree). Results are git-ignored, so both files are local only; re-run `main` at `--repeat 3` on another machine.

**The first real run** (2026-10-05, `mistral-small3.2:24b`, 38 correction cases of which 8 are clean, 20 translation cases):

| Correction | |
|---|---|
| Recall | 81.1% |
| Over-correction | 0.3% (2 words) |
| Guard violations | 0 |
| Category accuracy | 88.2% |
| Clean pass | 100% |
| Failures / warnings | 0 / 4 |
| Latency median / max | 5.8 s / 22.0 s |

| Translation | |
|---|---|
| No eszett | 100% |
| Terms kept | 100% |
| Structure kept | 100% |
| chrF | 70.2 |
| Failures | 0 |
| Latency median / max | 4.4 s / 7.1 s |

**The 7 misses**, each a genuine model miss (the model left the error or kept the wrong word): `miss-ich-klein` ("ich habe"), `miss-probiere-um-zu` (kept "um"), `eszett-weidenhofstrasse` ("Seit letzte Woche"), `case-helfen-mich` ("du mich" instead of "du mir"), `falsefriend-sensibel` ("sensible Lösung"), `falsefriend-rezept` ("das Rezept" for receipt), `learner-mail-mittwoch` ("die du gefragt hast"). Five persist across runs; the false friends and "helfen" + dative are the most telling.

**The golden set was reviewed by the user** on 2026-10-05. Rulings:

- "probiere" and "versuche" are both acceptable.
- "Use Swiss conventions when generating, but German (Germany) usage in the input is not an error." Two clean cases, `clean-de-brief-komma` and `clean-de-fahrrad-monatsende`, measure this. The model already obeys it without being told: both pass in every run. Stating it in the prompt was tried and dropped; see the lesson below.
- The eszett is the one Germany spelling that is always rewritten (FR-TRN-05). The two ß fixes in `eszett-weidenhofstrasse` therefore always pass, so read spelling recall with that in mind.

**Rules for adding a case** (full list in the Task 9 brief): everything is synthetic (invented people and places such as Frau Muster, Otterbach, the Weidenhof school; nothing real, NFR-P8); `wrong` is two or three words, unique in its text; list every acceptable `right`, and never put `wrong` inside a `right`; clean cases are natural Swiss Standard German without eszett; protected `terms` appear verbatim in both `text` and `reference`; references are natural Swiss Standard German or English. `GoldenFilesTests` and `FixtureContentGuardTests` enforce the structure and the content.

**Verified by the user, 2026-10-05:** with Ollama stopped, `swift run babelotter-eval --only correct` prints "Ollama could not be reached on 127.0.0.1:11434. Start it with `ollama serve` and try again." and exits 1.

**Lesson: do not give the model example pairs of what it must not change** (measured 2026-10-05, three runs each against `main`). Stating the Germany-usage rule in the Correct prompt made things worse both times it was tried:

- With examples ("Fahrrad and Velo", "Ende des Monats" and "Ende Monat", "a comma after the salutation or none"), the model learned the swap it was told not to make. "Ende des Monats" became "Ende Monat". Naming the salutation drew edits to it: "Sehr geehrter Herr Beispiel" became "Sehr geehrte Frau Beispiel" in 3 of 3 runs, changing a person's gender, which the prompt already forbids. Clean pass fell to 83.3%, category accuracy to 76.5%.
- Without examples, clean pass stayed at 100%, but category accuracy fell from 85.3% to 78.2%. The extra rule costs the error labelling and buys nothing the model was not already doing, so it was not merged.

A prompt line is not free: every rule competes for the model's attention with the rules already there, and an example is read as an instruction. Add a rule only when a measured case fails without it.

**The false-friend rule is kept** (2026-10-05). The Correct prompt now says the author often thinks in English, so each word's meaning is checked in context, and a German word used with the meaning of a similar English word is an error. It names no example and no category:

- **First wording**, which said "an error of category false friend": recall 81.1% to 87.8%, but category accuracy 85.3% to 79.6%. Naming a category inside the instruction shifted other labels; gender and agreement fixes came back as "case".
- **Kept wording**, with no category named: recall 87.5%, category accuracy 81.3%, clean pass 100%, over-correction 0.4%, guard violations 0.
  - "das Rezept" (receipt) is now fixed in 3/3 runs.
  - "probiere ... um ... zu" is fixed in 2/3, and "warten für den Bus" in 1/3.
  - "sensible Lösung" is still missed in 3/3.
  - Five previously right labels now come back as another category, mostly "case"; "Der Sitzung" is arguable either way.

The user ruled on 2026-10-05 that the corrected text, which Replace pastes, matters more than the category chip.

**The keep test for a prompt change** (user ruling, 2026-10-05), measured at `--repeat 3` against a `--repeat 3` baseline:
1. Clean pass stays at 100%.
2. Guard violations stay at 0.
3. Recall rises, and over-correction does not.
4. Category accuracy may dip slightly when recall rises clearly; say so in the PR and let the user decide.
5. Never name example words from the golden set in the prompt: that teaches the test, not German.

**Next steps.**

1. The remaining persistent misses:
   - "sensible Lösung" (false friend);
   - "du mich ... helfen" (helfen takes the dative);
   - "Seit letzte Woche" (seit takes the dative);
   - "die du gefragt hast" (missing nach).
   Two of the four are dative after a verb or preposition, so that is a shared target.
2. Try other installed models with `--models`. Category labels in particular may be a model limit, not a prompt one.

## Update 2026-10-01: Correct is merged; the evaluation harness is next

**Start here on a new machine.**

```sh
git fetch && git checkout feat/eval-harness   # the active branch
swift test                                    # 487 tests, all green
Tools/make-app.sh --run                       # needs the "babelOtter Dev" signing identity
ollama pull mistral-small3.2:24b              # the default model, about 15 GB
```

On a new Mac, create the signing identity once: Keychain Access, then Certificate Assistant, then Create a Certificate. Name it `babelOtter Dev`, with identity type *Self Signed Root* and certificate type *Code Signing*. Without it, `make-app.sh` signs ad hoc, and Accessibility has to be granted again after every build.

**Where things stand.**

- **On `main`:** Translate (Control-Option-T), the audience picker and instruction field, and **Correct (Control-Option-C)**, merged as #88 (`6564c30`). CI is green, including the mutation gate at 82.0%.
  - That score is honest. Of 133 mutants, the 24 that muter reports as surviving were each planted by hand and are killed by the suite: muter reports mutants inside closures and nested loops without ever inserting them. Six real survivors were found that way and killed with new tests.
  - Issues #40, #62, #63 and #64 are closed, as are epics #9 and #5.
- **Merged 2026-10-02:** PR **#87**, the guard that keeps a hidden popup from taking keyboard focus plus the muter-artefact correction, and PR **#89**, the 2026-09-21 capture readings in `docs/architecture.md` section 7 (Word can read on tier 1 when its focus is a text area). Both are merged into this branch; every other branch is deleted.
- **After pulling app changes, rebuild:** `Tools/make-app.sh --run`. A stale `build/babelOtter.app` from before #88 looked like "Control-Option-C does nothing" on 2026-10-02.
- **Active branch: `feat/eval-harness`**, already merged with `main`. It holds only the approved design so far: `docs/superpowers/specs/2026-09-30-eval-harness-design.md` (#74, #75, #76).

**What changed in Correct after manual testing, and why** (all on `main`):

- **Explanations name the real rule.** The model had explained a correct fix as "the gender of the pronoun *du*", and *du* has no gender.
- **The timeout fires on 60 s of silence, not 60 s in total.** Five short paragraphs took 59.9 s while streaming the whole time. Translate and Correct now emit a `progress` event for every piece of text the model sends.
- **The error list is read leniently.** One reply in three named two categories ("word order|spelling", copying the schema's own notation) or padded the list with empty items. The text that gets pasted is still read strictly.
- **The prompt keeps the author's meaning.** "mit der Kollege" had become "mit der Kollegin", turning a male colleague into a female one. It now becomes "mit dem Kollegen".

**Known limits, which motivate the harness.** On a learner text, the 24B model fixes spelling and some word order. It misses a lowercase "ich" at the start, "eine Sätze", "in Deutsch" (should be "auf Deutsch") and "probiere … um … zu". Its reason for one word-order fix is also off. A gender-gap `_r` appeared once during manual testing and never reproduced.

**Next steps, in order.**

1. Write the implementation plan for the harness from its spec, with the writing-plans skill.
2. Draft the golden set (`Evals/golden/correction.json`, about 30 cases, and `translation.json`, about 20). All cases must be synthetic: invented names, nothing real. **The user reviews the set before it is committed.**
3. Build it the same way as Correct: kit scorers test-first, then the thin `babelotter-eval` CLI, then one real run on the local model.

**Working conventions that saved time this round.**

- Before writing a test to kill a muter survivor, plant the mutant by hand at muter's reported line and column. Most survivors are artefacts.
- Check live-model behaviour with a temporary test under `Tests/BabelOtterKitTests/Integration/`, gated by `BABELOTTER_INTEGRATION=1`, and delete it afterwards. Never commit one.
- Wall-clock assertions are skipped under muter: test `IS_MUTER_RUNNING`.

## Update 2026-09-29: Correct is built; the live model check passes, the manual ones don't yet

**Correct is implemented, on `feat/correct`, behind its own hotkey:
Control-Option-C.** Select German text anywhere and press it. A popup near
the cursor streams the corrected text, then shows an inline word-level diff
(removed struck through in red, added in green, the rest plain), every error
itemised with a category chip and an English explanation, and any stylistic
suggestions listed but not applied -- dimmed rows, each with its own Copy
button for the suggested fragment. **Replace** pastes only the errors-fixed
text; a suggestion never reaches the document unless adopted by hand.
Non-German text gets "Correct works on German text." and nothing is sent.
Text that is already correct shows "No errors found" with a checkmark icon;
Replace and Copy are both disabled (nothing corrected to paste or copy).
Full design: `docs/superpowers/specs/2026-09-28-correct-design.md`.

**The live integration test passes**
(`BABELOTTER_INTEGRATION=1 swift test --filter OllamaIntegrationTests`,
against `mistral-small3.2:24b`, ~6-19s depending on load). Its first run,
before the fix below, had "Ich habe gestern mit der Kollege gesprochen."
come back as "Ich habe gestern mit der Kollegin gesprochen." -- the model
resolved the article/noun mismatch by changing the noun's gender (to a
female colleague) rather than fixing the case ending on the masculine noun
(`dem Kollegen`). Both are grammatically valid resolutions of the same
mismatch, but not the same sentence, so `PromptBuilder`'s Correct
instruction gained a meaning rule: fix each error with the smallest change
that keeps the author's meaning, resolve agreement/case errors by changing
articles, pronouns and endings rather than the noun, and never change a
person's gender, a count, the tense, or who the text is about. Run three
times after that change, against the same sentence: "Ich habe gestern mit
dem Kollegen gesprochen." every time, itemised as one `case` error, no
warnings. Never `Kollegin` again.

**Not yet run -- the manual checks, yours to do in the apps used daily:**

| Do | Expected |
|---|---|
| Control-Option-C on German with a deliberate mistake in Word | diff shows the fix; the error is listed with a category and an English explanation |
| Same in Teams and Outlook | same |
| Control-Option-C on correct German | "No errors found"; Replace disabled (Copy is disabled too, by design: there is nothing corrected to copy) |
| Control-Option-C on English | "Correct works on German text."; nothing sent |
| Control-Option-C on a 5-sentence paragraph with several errors | finishes without timing out (it can take a minute or more; the timeout now only fires on silence) |
| Replace after a correction with suggestions | only the error fixes are pasted |
| A suggestion's Copy button | copies the suggested fragment |
| Switch the audience to "Students (Sie)" on text addressing the reader as du | a register error appears |

## Update 2026-09-28: the prototype is on `main`, and it works where it matters

**#85 (Translate prototype) and #86 (audience picker and instruction field)
are merged.** Both passed CI, the mutation gate included (81.9% on #85 -- the
first scored run since the M1a shell; see the muter trap about `guard` inside
a `Task` closure below for why every earlier run was cancelled).

**Manual verification passed, 2026-09-28**, in the apps used daily:

- **Teams:** capture, streaming translation, Escape stopping Ollama, Replace,
  the user's clipboard restored afterwards, Sie/du switching, and an
  instruction plus Return re-running without pasting.
- **Word:** capture and Replace; the translation (not the old clipboard) was
  pasted, so the 0.8s settle is long enough there.
- **Outlook:** capture and Replace in a message being composed.

Recorded as measurements in `docs/architecture.md` section 7. **Not yet
exercised:** OneNote, Chrome, Safari, Mail, TextEdit, VS Code; the short-text
direction picker, bullet-list structure, and "Ollama not running". The tables
further down still list them.

**Cleaned up afterwards:** `PopupPanel.makeKeyNow()` now does nothing when
the panel is hidden, so clicking Dismiss during a capture cannot leave an
invisible key window. The 15 mutants the first scored run reported as
surviving turned out to be muter artifacts. Every one is killed when planted
by hand, so the true score was 83/83; see the muter trap about closures and
loops below.

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

- **Profile inference.** The audience is picked in the popup (it starts at
  the last one chosen) but not yet inferred from the source text (#58). The
  model already returns a `detected_audience`; nothing reads it.
- **A settings window.** Configuration is hand-edited JSON only (see the
  README's status block for the path).
- **Onboarding.** The Accessibility prompt is the bare system one; there is
  no guided setup, and no re-prompt if a grant is later revoked (#71).
- **History.** Nothing is written to disk. A result lives only in the popup
  until Replace, Copy, or Dismiss.
- **Configurable hotkeys.** Control-Option-T is the one hotkey, and it is
  hardcoded.

**Audience and instruction (branch `feat/profile-and-instruction`).** Once a
translation has started, the popup shows an audience menu -- each profile
labelled with its register, e.g. "Students (Sie)", "Colleagues (du)" -- and a
one-line instruction field with a Regenerate button. Changing the audience
re-runs the translation; the instruction ("shorter", "use Sie") applies on
Return or Regenerate, to this invocation only, and is never saved. The last
audience chosen is remembered (its id only, in UserDefaults). While the
instruction field has focus, Return means Regenerate, not Replace.

Manual checks for it -- passed in Teams on 2026-09-28:

| Do | Expected |
|---|---|
| Translate English to German, pick "Students (Sie)" | re-runs, addresses the reader as Sie |
| Pick "Colleagues (du)" | re-runs with du |
| Type "shorter" in the instruction field, press Return | re-runs shorter; nothing is pasted |
| Next Control-Option-T | starts with the audience picked last |

**Rigour is now split by layer.** `BabelOtterKit` keeps TDD and the mutation
gate. `Sources/BabelOtterApp` is AppKit glue and is built for speed, verified
by using it. Mutation testing moved to `.github/workflows/mutation.yml` and only
runs when the kit or its tests change; its timeout went from 60 to 150 minutes
after three runs were cancelled at the hour.

**Default model:** `mistral-small3.2:24b`, pulled locally.

**Watchdog: idle, not total (changed 2026-09-30).** `timeoutSeconds` (60)
now measures *silence*: a run fails only after that long with nothing at all
from the model. It used to budget the whole run, and a five-paragraph
correction measured 59.9 s on the default 24B model, warm -- a healthy reply
cut off at the line. Translate and Correct now report a `progress` event for
every piece of text the model sends, because Correct's error list streams
with no preview change for its whole length. A cold model load (roughly 25 s
for the 24B model) still counts against the silence budget before the first
token, which fits within 60 s; if it does not, raise `timeoutSeconds` in
`config.json`.

### Outstanding manual checks (yours -- nothing here can be pressed or watched from a coding session)

`swift test && Tools/make-app.sh --run`, grant Accessibility when prompted
(menu bar icon shows the status; *Check Again* rereads it), then work
through these. They come from tasks 5, 6 and 7 of the prototype plan. The
Teams, Word and Outlook rows, Escape, and clipboard restore passed on
2026-09-28 (see the update at the top); the rest have not been run.

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
- A mutant inside a closure, or inside a loop body whose condition is also
  mutated, is silently never inserted and then reported as a survivor. This
  understates the score. It explained all 15 survivors after the prototype
  and 23 of the 29 on `feat/correct`; the other 6 were real. See item 3
  under "Settled".
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

3. **~~Seven surviving mutants, all in sort comparators, look like equivalent
   mutants.~~ Wrong, corrected 2026-09-28: they are not survivors at all.**
   muter 16 reports a mutant as surviving when it never inserted it into the
   code. It drops mutants inside closures (the `sorted`, `filter` and
   `first(where:)` comparators here), and mutants inside a loop body whose own
   condition also carries a mutant. The tests then run unmodified code and
   pass, and that reads as a survivor. All 15 "survivors" of the first scored
   run after the prototype merged (81.9%) were planted by hand, one at a time,
   at the exact position muter gave, and the suite killed every one: the
   true score was 83/83. Not every survivor is an artifact, though: of the
   29 that `feat/correct`'s first scored run reported, 23 were artifacts and
   6 were real (in `WordDiff` and `CorrectionCheck`, killed in 0889948).
   **Before writing a test to kill a reported survivor, plant it by hand.**
   If the suite already kills it, muter never measured it.

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
