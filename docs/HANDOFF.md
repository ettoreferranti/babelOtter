# Handoff — state as of 2026-09-19

Read this first if you are picking babelOtter up in a new session.

## Where things stand

**M0 Foundations is complete: 11 of 11 tasks.** Everything lives on the branch
`feat/m0-foundations`, which is **not merged to `main`** — that decision is the
user's and has not been made.

| | |
|---|---|
| Branch | `feat/m0-foundations`, 26 commits ahead of `main` |
| Tests | 65 in 8 suites, green from a clean build |
| Mutation | 7/7 = 100%, gating CI at ≥80% |
| CI | green (`macos-15` / Xcode 16.4 / Swift 6.1.2) |
| Dependencies | zero, enforced by test |
| Local toolchain | Xcode 27 / Swift 6.4 — **two majors ahead of CI**, so CI is the binding check |

Issues #16–#25 and #30 are closed. Milestones: M0 done, then M1a Pipeline (27),
M1b Translate UX (13), M2 (5), M3 (17), M4 (9).

## Documents that matter

| Path | What it is |
|---|---|
| `docs/superpowers/specs/2026-09-18-babelotter-design.md` | The spec. Binding authority. |
| `docs/architecture.md` | Architecture. **§7 is measured reality and supersedes §2–3 where they disagree.** |
| `PRIVACY.md` | Threat model, enforcement mechanisms, accepted risks |
| `docs/superpowers/plans/2026-09-18-m0-foundations.md` | The executed M0 plan |
| `.superpowers/sdd/2026-09-18-m0-foundations/progress.md` | Execution ledger — every ruling, gitignored, does not merge |

## The one thing to understand about this codebase

**Twelve times during M0, a guard shipped that looked protective and silently
was not.** Each was caught only by planting the defect and watching the guard
fail — never by reading the diff. Examples: a networking symbol matching
nothing; a test unable to detect the bug it was written for; a decoder passing
on an unrecognised schema; a redaction defeated by `dump()`; a path check
defeated by case and symlinks; a phone marker missing the commonest Swiss
spelling; a mutation gate scoped to a hardcoded file list whose score would stay
100% while covering less and less.

**Verify guards by making them fail.** A green suite is not evidence.

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
   replacement into web content, which makes the Universal Clipboard risk
   accepted in `PRIVACY.md` more load-bearing than that document assumes.

## Open decisions for the user

- **Merge M0 to `main`?** Not done. Branch is green and reviewed.
- **Pull #77 (strict AX-only mode) forward from M4 into v1?** Spike #30 showed
  the clipboard path is common, not rare, so the accepted v1 privacy risk is
  wider than it looked when accepted.
- **Mutation threshold at M1a.** At 7 mutants a single survivor still passes
  80%; a small-population rule currently compensates. Revisit once M1a grows the
  surface roughly tenfold.
- **`ci.yml` trigger** carries `feat/m0-foundations` in its `push` branches
  list, with an inline note to remove it at merge.

## Not yet measured

Teams; the focus-taking panel variant (#52); Chrome; Word; and **whether a
managed ZHAW Mac permits the Accessibility grant at all** — if MDM blocks it, no
capture tier works and M1b's premise fails. Worth testing early on the work
machine.

## Known operational risk

muter occasionally reports a `buildError` for a mutant that otherwise builds
(observed once on CI, not reproduced in 3 local runs). The gate now fails loudly
on any unmeasured mutant rather than scoring around it, so this surfaces as a red
build to investigate rather than as quietly reduced coverage.
