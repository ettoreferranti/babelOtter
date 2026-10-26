# Built-in model server — design

**Status:** approved in conversation 2026-10-26. Section 7 lists what changed while building.
**Milestone:** M4. **Covers:** #126 (epic #15), in one PR. It replaces #103, closed after the small-model spike (`docs/evals/2026-10-small-models.md` on `spike/small-models`). **Parent spec:** `2026-09-18-babelotter-design.md` section 4.12 (`FR-ONB-01`–`04`), 4.13 (`FR-OLL-01`–`04`) and the privacy NFRs (`NFR-P1`–`P4`); decision 11 (model pulls go through the daemon) still holds.

## 1. What it does

lingoSwen ships Ollama inside the app. On a new install it runs that copy as a private server and downloads Mistral Small 3.2 through it, so a colleague installs one app and waits for one download. A user who already runs Ollama keeps using their own.

### 1.1 Two model servers

A **Model server** setting, at the top of Settings › Models:

| Mode | Talks to | Models | The bundled Ollama |
|---|---|---|---|
| **Built-in** | `127.0.0.1:47434` | in `~/Library/Application Support/ch.lingoswen/ollama/models` | started by lingoSwen at launch, stopped at quit |
| **My own Ollama** | `127.0.0.1:11434`, as today | the user's own | never started |

- Under the mode, one status line: "Built-in server running", "Starting the built-in server…", "The built-in server stopped: <reason>", or, for My own Ollama, today's reachability.
- The per-action model pickers list the active server's models.
- Switching modes takes effect at once: Built-in → own stops the bundled server; own → Built-in starts it, and the readiness check runs again.
- In My own Ollama mode, when the built-in models folder isn't empty: **Remove Built-in Models (15.2 GB)…**, which asks first. Nothing is deleted without it.

### 1.2 The built-in server

- **Started** in `applicationDidFinishLaunching`, and when switching to Built-in, as `Contents/Resources/ollama/ollama serve` with this environment and nothing inherited beyond `HOME` and `PATH`:

  | Variable | Value | Why |
  |---|---|---|
  | `OLLAMA_HOST` | `127.0.0.1:47434` | loopback only (`NFR-P1`), away from a user's own Ollama |
  | `OLLAMA_MODELS` | the folder above | never touches `~/.ollama` |
  | `OLLAMA_KEEP_ALIVE` | `30m` | the model stays loaded through a working session, then frees its ~19 GB |
  | `OLLAMA_NO_CLOUD` | `1` | no remote inference or web search, whatever a model asks for |

- **Stopped** in `applicationWillTerminate` (SIGTERM, then SIGKILL after 3 s) and when switching to My own Ollama.
- **Left over from a crash:** the server's pid goes to `ollama/server.pid`. At start, a pid there whose executable is our bundled binary is terminated first; any other pid is ignored and the file replaced.
- **It exits unexpectedly:** restarted once; a second exit within a minute leaves it stopped, with the reason (its exit status and the last log line) in the status line and in readiness, and **Restart** as the remedy.
- **Port 47434 taken by something else:** the server exits at once; the status says "Port 47434 is in use by another program."
- **Log:** its output goes to `ollama/server.log`, emptied at each start. Ollama logs no prompt text at its default level; `OLLAMA_DEBUG` is never set.

### 1.3 First launch

The setup window's Ollama and Model steps (#70) become one **Model** step:

| What the step finds | It shows | Continue when |
|---|---|---|
| Ollama answering on 11434 with `mistral-small3.2:24b` | "Ollama is already on this Mac, with Mistral Small 3.2." **Use My Ollama** (default) or **Use Built-in** | the choice is made |
| Anything else | "lingoSwen sets up its own model: Mistral Small 3.2, a 15 GB download from Ollama's library." **Download**, then progress, with **Cancel** | the download finished |

- **Download** first checks free disk space: under 20 GB available, it says how much is free and how much is needed, and doesn't start.
- A failed or cancelled download can be started again; Ollama resumes from the parts it already has.
- Once it's done, `mistral-small3.2:24b` is written for every action, as today's Model step does.

**Which mode an install gets:**
- **New installs:** Built-in. `Configuration.default` carries it, and the first launch writes it, unless the step above switches to My own Ollama.
- **Existing installs:** a `config.json` without `modelServer` decodes as My own Ollama, so nothing changes for anyone running lingoSwen today.

### 1.4 Readiness and remedies

| Mode | Cause | Menu header | Remedy |
|---|---|---|---|
| Built-in | server starting | "Starting the model server…" | none (re-checked every 2 s while starting) |
| Built-in | server stopped | "The model server stopped" | **Restart** |
| Built-in | model missing | "Mistral Small 3.2 isn't downloaded" | **Download…** (opens the setup Model step) |
| My own Ollama | unchanged | "Ollama isn't running", "X isn't installed" | unchanged: **Start Ollama**, copy `ollama pull X` |

### 1.5 Privacy

- `NFR-P1` holds: lingoSwen's only socket is still loopback HTTP, now to 47434 or 11434. The bundled server listens on `127.0.0.1` only, which the Privacy panel asserts for whichever port is active.
- `NFR-P2` and decision 11 hold: lingoSwen downloads nothing itself. The bundled server pulls the model from Ollama's registry, through the existing `OllamaClient.pull`, and only when the user presses Download.
- **The bundled server's own network use** is the registry pull and nothing else: it is the CLI server (no updater), and `OLLAMA_NO_CLOUD=1` turns off its cloud features. This is checked once in the build (section 6) and stated in PRIVACY.md, which can't be enforced by a test of lingoSwen's sources.
- The Privacy panel's "Model connection" row names the mode and port, and "Ollama listens on" checks the active port.
- PRIVACY.md gains a section on the built-in server: what it is, where its models and log live, what it connects to and when, and how to remove it.

## 2. Decisions

1. **Bundle the whole official build** (`ollama-darwin.tgz`, ~166 MB compressed), unchanged, rather than only its llama.cpp parts. The DMG grows by about that much; nothing breaks because of a part we removed.
2. **Pinned Ollama version**, recorded in `Tools/ollama.lock` (version, URL, SHA-256). The build downloads it once into `build/cache/`, checks the hash, and refuses a mismatch. An update is a deliberate commit, followed by an eval run.
3. **A fixed port, 47434**, not a free one found at launch: finding one needs `socket(`/`bind(`, which `NetworkingCallSiteTests` forbids, and a fixed port lets the Privacy panel check it.
4. **Keep-alive 30 minutes.** Ollama's 5 minutes would reload 15 GB after every short break; "until quit" would hold 19 GB all day.
5. **Download from Ollama's registry**, through the server, not from Hugging Face by the app: no second networking call site, and the existing pull code and progress UI.
6. **The built-in models folder is lingoSwen's own**, never `~/.ollama/models`: two servers writing one store can corrupt it, and removing lingoSwen's models must not touch the user's.
7. **No memory check.** The maintainer's colleagues have Macs with enough memory (decided 2026-10-25); a check can come later.
8. **The eval tool stays on 11434** (My own Ollama): it measures models, not the server mode.

## 3. The kit (`Sources/BabelOtterKit/`)

- **`Config/ModelServer.swift`:** `enum ModelServer: String, Codable { case builtIn, own }`, with its endpoint (`.builtIn` → port 47434, `.own` → `OllamaEndpoint.loopback`).
- **`Configuration.modelServer: ModelServer?`**: absent decodes as `.own`; `Configuration.default` sets `.builtIn`. `Configuration.endpoint` reads it.
- **`OllamaEndpoint.builtIn`** (port 47434), beside `.loopback`. `OllamaClient.loopback(timeout:)` gains an endpoint argument; it is still the only place a transport is built.
- **`Server/BuiltInServerLaunch.swift`:** the executable path inside the bundle, the arguments, and the environment of section 1.2, as values, tested exactly.
- **`Server/BuiltInServerPolicy.swift`:** the state machine (`stopped`, `starting`, `running`, `failed(reason)`), the restart-once rule, the pid-file decision (terminate, ignore), and the wording of each status. Pure, with an injected clock.
- **`Server/DiskSpacePolicy.swift`:** given free bytes, whether Download may start and the message if not.
- **Readiness:** new causes `serverStarting`, `serverStopped(reason)`, and `modelMissing` with a `.download` remedy in Built-in mode; the wording in `ReadinessPolicy`.
- **Setup:** `SetupFlow` merges the Ollama and Model steps into one Model step, with the two branches of section 1.3.
- **Privacy:** `ListeningProbe` and `PrivacyReport` take the active port; the wording names the mode.

## 4. The app (`Sources/BabelOtterApp/`)

- **`Server/BuiltInServerController.swift`:** runs the launch as a `Process`, writes the pid file and log, watches for exit, applies the policy, and publishes its state to readiness and Settings. Started and stopped from `AppDelegate` and on a mode change.
- **The endpoint, threaded through:** `AppEnvironment`, `ReadinessMonitor`, `SettingsModel`, `SetupWindow` and the Privacy panel make their client from `Configuration.endpoint` instead of `.loopback`, and remake it when the mode changes.
- **Settings › Models:** the mode picker, the status line, and Remove Built-in Models.
- **Setup:** the merged Model step.
- **PRIVACY.md and the Privacy panel:** as in section 1.5.

## 5. Packaging (`Tools/`)

- **`Tools/ollama.lock`** and **`Tools/fetch-ollama.sh`:** download the pinned tgz into `build/cache/` if missing, check its SHA-256, and unpack it.
- **`make-app.sh` and `release.sh`** copy it into `Contents/Resources/ollama/`. Ollama ships its binaries signed with the hardened runtime; `release.sh` keeps those signatures if notarization accepts them, and otherwise signs every nested Mach-O itself, inside out, with `--options runtime --timestamp`, before the outer bundle. The build finds out which on the first release (section 6) and the script keeps only the path that works.
- **The DMG** still holds no model.

## 6. Testing

**Unit tests:** `ModelServer` coding (absent → own, default → built-in, round trip); the endpoints; the launch values; every policy transition (start, run, exit, restart once, second exit fails, pid file ours/theirs/missing, port taken); disk-space messages; readiness causes and remedies per mode; setup branches; Privacy wording with each port. The muter gate applies to all of it.

**Checked once, by hand, during the build (results in the PR):**
- the bundled server with `lsof` while idle, while pulling and while generating: it listens on `127.0.0.1:47434` only, and connects out only during a pull;
- a notarized test build launches its bundled server on a Mac with no Ollama.

**Manual (in HANDOFF):**
1. With your Ollama running: the app on a fresh user account (or with `config.json` moved away) offers **Use My Ollama**; choosing it downloads nothing.
2. Your existing `config.json` stays on My own Ollama after the update.
3. Switch to Built-in in Settings: the server starts, readiness asks for the download; Download shows progress, Cancel stops it, Download again resumes.
4. After the download: Translate, Correct, Explain and Re-pitch work through the built-in server.
5. Quit lingoSwen: no `ollama` process from the app is left (`pgrep -fl ch.lingoswen`).
6. Switch back to My own Ollama: the built-in server stops; Remove Built-in Models frees the space.
7. Privacy panel in each mode: the right port, loopback only.

## 7. Changed while building

- **The server's own `HOME`** (`ollama/home/`): Ollama keeps state under `~/.ollama` (its key, among others), so with the user's `HOME` it would have written there. Only `PATH` is inherited now.
- **Ollama fetches a model-recommendations list** from ollama.com every few hours, with no switch to turn it off. It carries no user content; PRIVACY.md says so, next to the model download.
- **Only our own listener is trusted** (security review): the server counts as running only when `lsof` shows the child process listening on 47434, and actions refuse to run (opening the setup Model step instead) until it is running. Another program that took the port first never gets text.
- **Readiness keeps one cause per action** for a missing model, as for the user's own Ollama; in Built-in mode its remedy is **Download <model>…**, which opens the setup Model step. The section 1.4 header "Mistral Small 3.2 isn't downloaded" was not used.
- **An unreadable `config.json`** (or a folder that can't be prepared) falls back to My own Ollama, not the defaults' Built-in: it belongs to someone already using lingoSwen, who must not be offered a 15 GB download.
- **Ollama keeps its own signatures** inside the app. They are Developer ID, hardened runtime and timestamped; `release.sh` checks each nested Mach-O for the hardened runtime before signing the outer bundle without `--deep`. Notarization of this layout is still to be confirmed on the first release.
- **Pinned version 0.40.8**, the one the October 2026 eval runs used.
