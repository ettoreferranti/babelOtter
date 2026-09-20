# Privacy Model

babelOtter is built around one inviolable rule. This document states that
rule, the threat model behind it, how the rule is *enforced* rather than
merely promised, and — honestly — the one place where macOS can undo it.

---

## NFR-P1 — The inviolable rule

> **babelOtter never transmits your content. The clipboard path can expose it
> to Universal Clipboard if Handoff is enabled.**

The first sentence is the rule, and it is absolute: babelOtter opens exactly
one socket, to loopback, and an architecture test fails the build if a second
call site appears.

The second sentence is not a loophole in that rule — it is macOS doing
something babelOtter neither asks for nor can observe. It is stated up front
rather than buried, because the alternative wording, "no user content ever
leaves this machine", would have been a promise this program is not in a
position to keep on its own.

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

### The clipboard is a conduit, by decision

**Decided 2026-09-20.** Earlier versions of this document carried the clipboard
as a *risk accepted for v1*, on the assumption it was a fallback for occasional
apps. Measurement removed that assumption twice over.

Reading: the Accessibility API reaches TextEdit, Preview, Outlook, Safari and
Mail. It does not reach Microsoft Teams, Word, OneNote or VS Code.

Writing: worse. Every web surface tested accepts a write, reports success, and
changes nothing — including a plain editable `<textarea>` in Safari that reads
perfectly. Accessibility writes are confirmed working only in native AppKit
text.

So the clipboard is not a fallback. It is the only capture path for Electron
apps, and the only replacement path for everything except native AppKit text.
A product that refused to use it would not work in most of the places people
write.

**The exposure.** When babelOtter uses the clipboard it places your text on the
general pasteboard and restores what was there before. If Handoff is enabled,
macOS may sync the general pasteboard to your other Apple devices. That is
macOS, not babelOtter — but the effect on your content is the same, so it is
stated here rather than explained away.

**babelOtter cannot tell whether Handoff is on.**
`com.apple.coreservices.useractivityd` exposes no readable setting for it, and
the per-host domain does not exist. So the app cannot warn you only when the
risk is live; it has to assume it always might be.

**What babelOtter does about it**

- Tells you, per action, when the clipboard path was used, so exposure is never
  silent (`FR-CAP`, `NFR-P9`).
- Restores your previous clipboard contents around every operation, including
  on the failure paths.
- Marks its pasteboard items `org.nspasteboard.ConcealedType` and
  `com.apple.is-sensitive`. **Measured 2026-09-20: these do not stop Universal
  Clipboard.** A concealed item copied on one Mac pasted verbatim on another,
  signed in to the same account. The markers are still set, because clipboard
  managers do respect them and keeping your text out of a clipboard history
  app is worth something — but they are not a defence against Handoff, and
  this document previously recorded that as unverified rather than as known.

There is no other mitigation available. The only reliable way to keep the
clipboard path off your other devices is to turn Handoff off:
`System Settings → General → AirDrop & Handoff → Handoff: off`.

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
