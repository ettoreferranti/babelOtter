# Privacy Model

babelOtter is built around one inviolable rule. This document states that
rule, the threat model behind it, how the rule is *enforced* rather than
merely promised, and — honestly — where v1 knowingly falls short.

---

## NFR-P1 — The inviolable rule

> **No user content ever leaves this machine.**

"User content" means all of it: source text, translations, corrections,
explanations, glossary entries, do-not-translate terms, audience profiles,
style notes, history records, prompts, model responses, and logs.

There is no telemetry, no analytics, no crash reporting, no remote
configuration, no update check, and no "anonymous usage statistics".
There is no opt-out because there is nothing to opt out of.

## NFR-P2 — Permitted network activity

babelOtter itself opens **no non-loopback connections**. Ever.

| Traffic | Who opens it | Carries user content? |
|---|---|---|
| `http://127.0.0.1:11434` — inference, streaming | babelOtter | Yes — loopback only |
| `http://127.0.0.1:11434/api/pull` — model download | babelOtter | **No** — model name only |
| Actual model bytes from ollama.com | **the Ollama daemon**, not babelOtter | No |
| `git push` / CI | you, manually | No — source code only |

Model downloads are delegated: babelOtter asks the *local* Ollama daemon to
fetch a model, and Ollama makes the outbound connection. The app's own egress
stays loopback-only, so the architectural invariant holds without exception.
Downloads always require explicit confirmation showing model name and size.

---

## Why the App Sandbox cannot enforce this

The obvious idea — sandbox the app and deny network access — does not work.
macOS offers `com.apple.security.network.client` as an all-or-nothing
entitlement; there is no loopback-only variant. Denying it would also block
Ollama. Granting it permits connections to anywhere.

So the guarantee is made **in code and proven by tests**:

| Mechanism | What it guarantees |
|---|---|
| `OllamaEndpoint` value type | Only constructs from the literal loopback addresses `127.0.0.1` / `::1`. `localhost` is accepted as a spelling and stored as `127.0.0.1`, because a *name* is resolved by `/etc/hosts` and the system resolver rather than by this type. Deliberately ignores `OLLAMA_HOST`. Rejects everything else. |
| Networking call-site allowlist test | No file outside `Config/networking-allowlist.txt` may mention any of ~19 networking symbols (`URLSession`, `NWConnection`, `getaddrinfo`, `socket(`, …), and that allowlist may hold at most one path. Today **zero** files mention them — the single allowlisted path is `OllamaClient.swift`, which M1a has yet to write. A new call site fails CI. This is a lexical scan of source text: it catches the accidental introduction of networking, not a contributor deliberately evading it — the limits are listed in full in `NetworkingCallSiteTests`' own documentation. |
| Dependency allowlist test | `Package.resolved` and `Package.swift`'s `.package(` / `.binaryTarget(` declarations are checked against a reviewed allowlist, and a declaration the scan cannot parse counts as unreviewed. Nothing here inspects what a package *does*: every dependency is human-reviewed and attested in its allowlist commit not to perform networking. The list is empty today, which is the point. |
| Log redaction wrapper | Every textual representation of a user-content type is redacted — interpolation, `description`, `debugDescription`, `dump()`, `Mirror`. The **accidental** path to a log is therefore safe by default. This is not type-system enforcement: `UserText.value` is `public`, so `logger.info("\(text.value)")` compiles. The deliberate path is left open on purpose and is a greppable, reviewable token. |
| Storage path resolver | Refuses any history path resolving at or inside an iCloud-synced tree, comparing case-insensitively and after resolving symlinks on both sides. |
| Fixture content guard | CI rejects test data carrying any of four markers of real correspondence (email, Swiss phone, IBAN, AHV), and reports — rather than skips — any file it cannot read as UTF-8 text, such as a `.docx`, a PDF or a screenshot. It does not detect names or addresses; a human reading the fixture is still the actual control. |
| Mutation testing (≥80%) | Proves the tests around the three mechanisms implemented in `Sources/` — `OllamaEndpoint`, the log redaction wrapper, the storage path resolver — would actually *catch* a regression. **It says nothing about the other three.** The networking, dependency and fixture guards are lexical scanners implemented entirely in `Tests/`, which muter excludes; nothing mutates them. What stands in for it there is that each scanner's detection logic is extracted and exercised directly against synthetic input in memory, so it is proven regardless of what happens to be on disk — a weaker guarantee than mutation coverage, stated here rather than implied away. |

The in-app **Privacy panel** reports live status: resolved endpoint, Ollama's
listening interface, history location, iCloud exposure of that path, and
dependency count.

---

## Storage

Everything lives under `~/Library/Application Support/ch.babelotter/`:

- **Not** iCloud-synced (unlike `~/Documents` and `~/Desktop`, which are).
- Marked excluded-from-backup.
- Database file mode `0600`.
- History retention is configurable and there is an unconditional
  **Clear all history** control.

Nothing babelOtter writes ever lands inside the repository. See `.gitignore`.

---

## Known limitations and accepted risks

Stated plainly rather than buried.

### ⚠️ OPEN RISK — Clipboard fallback and Universal Clipboard (closing in M1a, #77)

When the Accessibility API cannot read or write the selection in a given app,
babelOtter falls back to simulating ⌘C / ⌘V through the general pasteboard.
Your previous clipboard contents are saved and restored around the operation.

**This path is not rare. On measurement, it is the majority path.** An earlier
version of this document called it a fallback for "some Electron apps and web
content", which implied an edge case. Two rounds of measurement against real
applications, on 2026-09-19 and 2026-09-20, say otherwise.

Of the applications measured, the Accessibility API can read the selection in
TextEdit, Preview, Outlook and Safari. It cannot in **Microsoft Teams,
Microsoft Word, Microsoft OneNote or VS Code** -- those focus a container that
exposes no selection at all, and a walk of their accessibility trees found
nothing selectable underneath. For those four, the clipboard is not the
fallback. It is the only path.

**Replacement is worse than reading.** Measured 2026-09-20: the Accessibility
API accepts a write and reports success while changing nothing, on every web
surface tried -- including a plain editable `<textarea>` in Safari that reads
perfectly. AX write is confirmed working only in native AppKit text such as
TextEdit. So putting a result *back* needs the clipboard for all web content as
well as all Electron apps, which is a wider set than reading needs.

Anyone whose working day is mostly Teams, Word and OneNote should read the risk
below as applying to most of what they do, not to an occasional edge case. The
full per-application table, for reading and for writing, is in
`docs/architecture.md` section 7.

**The risk:** if Handoff / Universal Clipboard is active, macOS may sync
general pasteboard contents to your other Apple devices via iCloud. That is
user content leaving the machine, and it would violate NFR-P1.

The usual mitigation is marking the pasteboard item `org.nspasteboard.ConcealedType`
and `com.apple.is-sensitive`. Those are a *community convention respected by
clipboard managers*; Apple does not document any supported way to exclude an
item from Universal Clipboard, and it is unverified whether concealment
suppresses the sync at all.

**Decision:** this risk is **knowingly accepted for the moment**, and is being
closed rather than carried. It was originally accepted for the whole of v1 on
the assumption that the clipboard was a rare fallback. Once spike #30 showed
that assumption was false, the strict Accessibility-only mode that closes the
gap was pulled forward out of post-v1 into M1a (issue #77), so that it ships in
the same milestone as the fallback it guards rather than after it.

Until #77 lands, the exposure described above is real and unmitigated.

**If this matters to you today**, disable Handoff:
`System Settings → General → AirDrop & Handoff → Handoff: off`.

### Ollama's network binding is not under babelOtter's control

Ollama may bind to all interfaces (`*:11434`) rather than loopback, making it
reachable from your local network. This is inbound exposure of your Ollama
instance, not babelOtter leaking data, but it undermines the guarantee at the
system level. To restrict it:

```sh
launchctl setenv OLLAMA_HOST 127.0.0.1:11434   # then restart Ollama
```

babelOtter's Privacy panel warns when it detects a non-loopback binding.

### Ollama keeps its own logs

`~/.ollama/logs/` may contain prompt text depending on Ollama's log level.
These are local files, but they are outside babelOtter's control and are not
covered by our redaction policy. They can be cleared manually.

### OS-level traffic babelOtter cannot prevent

macOS itself performs Gatekeeper / XProtect checks and may report app-launch
hashes to Apple. This is operating-system behaviour, carries no user content,
and is out of scope for any application.

### Notarization would upload the binary to Apple

v1 is a local build only, which avoids this entirely. Should distribution be
added later, notarization uploads the app binary (not user data) to Apple.

---

## This repository is public

The eval golden set, test fixtures, default glossary entries, screenshots and
issue examples must be **synthetic**. No real correspondence, no internal work
material, no personal data may enter this repo. CI enforces a fixture content
guard, and integration tests that touch real text run **locally only** — never
on GitHub-hosted runners.
