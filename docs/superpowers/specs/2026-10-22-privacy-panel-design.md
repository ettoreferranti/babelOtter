# Privacy panel and the Ollama binding warning — design

**Status:** approved in conversation 2026-10-22, pending review of this document.
**Milestone:** M3. **Covers:** #72 and #73 (epic #13), in one PR. **Parent spec:** `2026-09-18-babelotter-design.md` section 4.12 (`FR-ONB-03`, `FR-ONB-04`) and 5.1 (`NFR-P2`, `NFR-P4`, `NFR-P6`, `NFR-P7`).

## 1. What it does

**Privacy...** in the menu (after History...) opens a small window that reports, line by line, what can be checked about lingoSwen's privacy right now. Each line has a mark: a check (as it should be), a warning, or a question mark (could not be determined, never reported as safe). **Check Again** re-reads everything; the window also re-reads when it is opened. A check clears the lines first and shows a spinner, so an earlier result never stands in for the current one; only the latest check's result is shown.

| Line | Shows | Mark |
|---|---|---|
| Model connection | `http://127.0.0.1:11434`, "this Mac only (loopback)" | Check: `OllamaEndpoint` can only be built from a loopback address, so this is a fact of the build, not a measurement |
| Ollama listens on | the addresses Ollama's port is open on, as macOS reports them | Check for loopback only, worded "for the Ollama running as you": lsof without admin rights does not see another user's or root's processes, and the panel says so; **warning** for any other address ("all networks" for `*`, `0.0.0.0` or `::`; "this network" for a specific address); question mark when nothing is reported (not running, run by another user or as root) |
| History | the folder (`~/Library/Application Support/ch.lingoswen/`), and the retention in words ("kept 90 days", "off") | Check when the folder is outside iCloud and the history recorder opened its database; warning when the folder is inside iCloud, when the recorder could not open the database (its own reason, so the panel says what history really does), or on any unexpected error |
| Dependencies | "0 third-party packages", "checked against the allowlist on every change" | Check |
| Telemetry | "No telemetry, analytics or crash reporting. Nothing is sent anywhere but the local model." | Check (a statement, not a measurement; worded so) |

- **The warning (#73)**, under "Ollama listens on" when it is not loopback-only: "Other devices on your network can use your Ollama and see what is sent to it." Then the fix: "Run this in Terminal, then quit and restart Ollama:" with `launchctl setenv OLLAMA_HOST 127.0.0.1:11434` and a **Copy** button.
- **Open PRIVACY.md** at the bottom: the copy bundled with this build, opened in the default app for Markdown. A line above it names the accepted clipboard risk in one sentence, so the panel itself says it: "Replace and Copy pass text through the clipboard, which Universal Clipboard can carry to your other devices; see PRIVACY.md." When the app runs outside its bundle (`swift run`), the button is disabled with "PRIVACY.md is in the repository".

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Where | Its own window, from the menu | It reports state and changes nothing; Settings edits |
| #73 with #72 | One PR | The panel's line includes the listening interface; the warning lives in it |
| How the binding is read | `/usr/sbin/lsof -nP -iTCP:11434 -sTCP:LISTEN -F n` run as a child process, its `n` lines parsed | Read-only, ships with macOS, needs no network call (`NFR-P4`'s single call site is untouched) and no extra permission for the user's own Ollama |
| Unknown | Stated as unknown, never as safe | `FR-ONB-04`'s last criterion; lsof sees only the user's own processes |
| "Allowlist check passed" | Worded as what is true: checked on every change, by CI | The running app cannot re-run the test; a test keeps the shown count equal to the package graph |
| PRIVACY.md | Bundled by `Tools/make-app.sh`, opened locally | Matches the build; offline; no browser to a repository |

## 3. The kit (`Sources/BabelOtterKit/Privacy/`)

- `ListeningExposure` (`ListeningProbe.swift`): `.loopbackOnly([String])`, `.exposed([String], everywhere: Bool)`, `.unknown`; and `ListeningProbe.parse(_ lsofFieldOutput: String) -> ListeningExposure`: every `n`-line's address before the last `:`; loopback is `127.x.x.x`, `[::1]`, `localhost`; everywhere is `*`, `0.0.0.0`, `[::]`; no `n` lines is `.unknown`. Bounded: at most 64 lines are read.
- `BuildFacts.thirdPartyPackages = 0`, with a test that it equals the number of `.package(` declarations in `Package.swift` and of pins in `Package.resolved` (none when the file is absent).
- `PrivacyReport` (`PrivacyReport.swift`): built from an endpoint, a `ListeningExposure`, the history folder with its `StorageLocator` verdict, the `HistoryPolicy`, and `BuildFacts`; gives an ordered list of `PrivacyLine { title, detail, mark: .ok/.warning/.unknown, remedy: String? }`. All wording lives here, so it is tested.
- `OllamaEndpoint.defaultPort` (11434) is the port lsof is asked about.

## 4. The app

- `ListeningProbeRunner`: runs lsof with a 2-second limit off the main actor; a missing binary, a non-zero exit with no output, or the time limit gives `.unknown`. The child gets no environment beyond `PATH=/usr/bin:/bin:/usr/sbin`.
- `PrivacyWindowController` + `PrivacyView`, an `AppWindow` presented in front like History and Settings; Check Again re-runs the probe and rebuilds the report.
- `Tools/make-app.sh` copies `PRIVACY.md` into `Contents/Resources/`; the button opens `Bundle.main.url(forResource: "PRIVACY", withExtension: "md")`.
- The menu gains **Privacy...** after History....

## 5. Out of scope

- Changing Ollama's binding from lingoSwen (it only tells you the command).
- The rest of epic #13: the first-run walkthrough (#70) and re-presenting setup steps (#71).
- Network traffic monitoring of any kind.

## 6. Testing

- **`ListeningProbeTests`**: `n127.0.0.1:11434` and `n[::1]:11434` are loopback; `n*:11434`, `n0.0.0.0:11434`, `n[::]:11434` are exposed everywhere; `n192.168.1.20:11434` is exposed, not everywhere; mixed loopback and wildcard is exposed; `p`/`f` lines are ignored; empty output is unknown; more than 64 lines stop at 64.
- **`PrivacyReportTests`**: each line's wording and mark for each state; the remedy only for exposed; history inside iCloud is a warning; retention in words for days, unlimited, off and paused.
- **`BuildFactsTests`**: the count matches the package graph.

### Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| P1 | Choose Privacy... in the menu | The window opens in front; five lines, all checks with Ollama running as installed |
| P2 | Quit Ollama; Check Again | "Ollama listens on" shows a question mark and "unknown", not a check |
| P3 | `launchctl setenv OLLAMA_HOST 0.0.0.0:11434`, restart Ollama, Check Again; then `launchctl unsetenv OLLAMA_HOST` and restart Ollama | A warning, "all networks", the explanation and the command with Copy; after unsetting, a check again |
| P4 | Press Open PRIVACY.md | It opens in your Markdown app, the version from this build |
