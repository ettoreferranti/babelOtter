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
| `OllamaEndpoint` value type | Only constructs from `127.0.0.1` / `::1` / `localhost`. Deliberately ignores `OLLAMA_HOST`. Rejects everything else. |
| Networking call-site allowlist test | Asserts exactly one file in the codebase references `URLSession` / `Network` / `NWConnection`. A new call site fails CI. |
| Dependency allowlist test | `Package.resolved` is checked against a reviewed allowlist. No package may perform networking. |
| Log redaction wrapper | User-content types cannot reach a logging API without passing through a redactor the type system enforces. |
| Storage path resolver | Refuses any history path resolving inside an iCloud-synced tree. |
| Fixture content guard | CI rejects non-synthetic test data (this repo is public). |
| Mutation testing (≥80%) | Proves the above tests would actually *catch* a regression, rather than merely existing. |

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

### ⚠️ ACCEPTED RISK (v1) — Clipboard fallback and Universal Clipboard

When the Accessibility API cannot read or write the selection in a given app
(common in some Electron apps and web content), babelOtter falls back to
simulating ⌘C / ⌘V through the general pasteboard. Your previous clipboard
contents are saved and restored around the operation.

**The risk:** if Handoff / Universal Clipboard is active, macOS may sync
general pasteboard contents to your other Apple devices via iCloud. That is
user content leaving the machine, and it would violate NFR-P1.

The usual mitigation is marking the pasteboard item `org.nspasteboard.ConcealedType`
and `com.apple.is-sensitive`. Those are a *community convention respected by
clipboard managers*; Apple does not document any supported way to exclude an
item from Universal Clipboard, and it is unverified whether concealment
suppresses the sync at all.

**Decision:** this risk is **knowingly accepted for v1** and documented here.
Investigation and a strict AX-only mode are deferred to post-v1 — see the
`privacy` + `post-v1` issues in the backlog.

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
issue examples must be **synthetic**. No real correspondence, no internal ZHAW
material, no personal data may enter this repo. CI enforces a fixture content
guard, and integration tests that touch real text run **locally only** — never
on GitHub-hosted runners.
