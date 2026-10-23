# Sign, notarize and distribute — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-23-sign-notarize-design.md` (#82). **Branch:** `feat/sign-notarize`.

Each task ends with `swift build` and `swift test` green and one commit. No kit code changes, so the mutation gate does not run.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `ReleaseSecretsTests`: a pure scanner for a named `Developer ID Application:` identity, a parenthesised 10-character team ID and an `--apple-id` address, run over every tracked text file | `Tests/BabelOtterKitTests/Privacy/ReleaseSecretsTests.swift` | the scanner against planted lines; the repository scan |
| 2 | `Info.plist` says 1.0.0 | `Tools/app/Info.plist` | - |
| 3 | `Tools/release.sh`: preconditions, build, stamp, sign, DMG, notarize, staple, check | `Tools/release.sh` | `bash -n`; manual M1 (untagged refusal), M2-M4 once the certificate arrives |
| 4 | `PRIVACY.md` (notarization, posture), `README.md` (installing; making a release) | docs | the full suite (identifying-reference guards) |
| 5 | HANDOFF update with the manual checks; #82 notes the re-scoped CI criterion | docs, issue | - |

Then a fresh-context review, fixes, and the manual checks (yours) before a PR. M2-M4 wait for the Developer ID certificate.
