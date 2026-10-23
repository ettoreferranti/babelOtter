# Sign, notarize and distribute — design

**Status:** approved in conversation 2026-10-23, pending review of this document.
**Milestone:** M4. **Covers:** #82 (epic #15).

## 1. What it does

`Tools/release.sh` turns a tagged commit into `build/lingoSwen-X.Y.Z.dmg`. It signs the build with a Developer ID, notarizes and staples it, so a colleague can install it without Gatekeeper blocking it. It runs on the maintainer's Mac and nowhere else. The DMG is handed to colleagues privately and is never attached to a public GitHub Release.

```
Tools/release.sh            # on a clean checkout of a vX.Y.Z tag
```

1. **Preconditions.** The working tree is clean; `HEAD` is exactly one tag of the form `vX.Y.Z`; exactly one `Developer ID Application:` identity is in the keychain (or `BABELOTTER_RELEASE_IDENTITY` names one); the notarytool keychain profile `lingoswen-notary` exists (or `BABELOTTER_NOTARY_PROFILE` names one). Any failure stops the script before it builds, with the fix in the message.
2. **Build.** Runs `Tools/make-app.sh`, which is unchanged, then stamps the bundle's copy of `Info.plist`: `CFBundleShortVersionString` = `X.Y.Z`, `CFBundleVersion` = `git rev-list --count HEAD`.
3. **Sign.** `codesign --force --options runtime --timestamp --sign "$identity"` on the app. Hardened runtime, no entitlements: the app is not sandboxed and uses nothing the runtime restricts (AX, CGEvent keystrokes, a global hotkey, loopback HTTP, an `lsof` child). Then `codesign --verify --strict --deep`.
4. **Package.** `hdiutil create` a UDZO DMG holding the app and an `/Applications` link, volume name `lingoSwen X.Y.Z`; the DMG is signed with the same identity.
5. **Notarize.** `xcrun notarytool submit --wait --keychain-profile …` on the DMG. If it is rejected, the script fetches `notarytool log` and prints it, then fails.
6. **Staple and check.** `xcrun stapler staple` the DMG, then `stapler validate` and `spctl -a -t open --context context:primary-signature -v` on the DMG, and `spctl -a -t exec -v` on the app mounted from it. The last line prints the DMG's path and its SHA-256.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Account | The maintainer's existing team membership | It exists; a personal one costs a year's fee for no gain while builds stay private |
| Where builds go | Privately to colleagues (an internal share or a direct link), never a public GitHub Release | A team Developer ID carries the team's legal name in every signature (`codesign -dv`, Gatekeeper's dialogs). On a public download it would say where the author works, which this repo must not |
| What the repo holds | No identity name, team ID, Apple ID or password, anywhere | The script finds the identity in the keychain by its `Developer ID Application:` prefix; notarytool reads credentials from a keychain profile. A test keeps team-ID-shaped strings out of `Tools/` (section 4) |
| Where it runs | Locally only, for now | The certificate never leaves the maintainer's Mac; an organization may not let it be exported to CI. CI signing can follow if that is allowed; #82's first criterion ("when CI runs") is re-scoped to the local script, and the issue says so |
| Package | A notarized, stapled DMG | The usual drag-to-Applications install; a stapled DMG passes Gatekeeper offline |
| Version | Taken from the tag; `Info.plist` in the repo says `1.0.0` | It still said `0.1.0`. The tag is the one source; the release refuses an untagged or dirty commit, so a build always matches a commit |
| `make-app.sh` | Unchanged; the release re-signs its output | Dev builds keep the self-signed identity and their Accessibility grant |
| Updates | None in the app; a colleague installs the next DMG over the old one | An updater would be a second non-loopback network call site, against `NFR-P2` |

## 3. Privacy

`PRIVACY.md`'s "Notarization would upload the binary to Apple" becomes **"Notarization uploads the binary to Apple"**: a release build's DMG, which holds the app binary and the bundled `PRIVACY.md` but no user content, configuration or history, is uploaded to Apple's notary service by the maintainer at release time. The user's Mac sends nothing for this. On first launch macOS checks the signature and the notarization ticket; that traffic belongs with the Gatekeeper/XProtect paragraph, is the operating system's, and carries no user content. The posture line "v1 is a local build only" goes. lingoSwen's own network activity is unchanged: loopback only.

## 4. Tests

The script is bash and outside the mutation gate; it is verified by running it (section 6). One guard goes in `Tests/` with the other repo guards:

- `ReleaseSecretsTests`: no tracked file under `Tools/` contains a `Developer ID Application:` followed by a name, a 10-character team ID in parentheses (`\([A-Z0-9]{10}\)`), or an `@` address after `--apple-id`. Planted-defect check: a temporary line with each shape must fail it.
- `Info.plist`'s `CFBundleShortVersionString` is `1.0.0`; no test (the release overwrites the bundle's copy).

## 5. Docs

- `README.md`: a short **Installing a release build** section (Ollama first; open the DMG and drag lingoSwen to Applications; grant Accessibility on first use) and **Making a release** (the one-time steps: a Developer ID Application certificate in the login keychain, `xcrun notarytool store-credentials lingoswen-notary`; then tag and run the script). Nothing names a team.
- `PRIVACY.md` as in section 3. `docs/HANDOFF.md`: the update section with the manual checks.

## 6. Prerequisites and manual checks (yours)

Prerequisites:

1. **A Developer ID Application certificate with its private key in your login keychain.** On the team, only the Account Holder can create one (the portal says so for an Admin), so the key is made here and only a request travels:
   1. Keychain Access › Certificate Assistant › *Request a Certificate From a Certificate Authority…*, your Apple ID's address, *Saved to disk*. This creates the private key in your login keychain.
   2. Send the `.certSigningRequest` to the Account Holder, who creates the **Developer ID Application** certificate from it (Certificates › + › Developer ID Application, profile type G2 Sub-CA) and sends back the `.cer`.
   3. Double-click the `.cer`. `security find-identity -v -p codesigning` now lists one `Developer ID Application:` identity. It is valid for five years; no `.p12` is ever exported.
2. **Notarization credentials.** As an Admin you can notarize. Create an app-specific password for your Apple ID at account.apple.com, then `xcrun notarytool store-credentials lingoswen-notary --apple-id … --team-id …`; the password lives in the keychain only.

| # | Do | Expect |
|---|---|---|
| M1 | Run `Tools/release.sh` on the branch, untagged | Stops before building: "HEAD is not a vX.Y.Z tag" |
| M2 | After merge, tag `v1.0.1` on `main`, run it | Notarization accepted; a DMG and its SHA-256 printed; `spctl` says "accepted, source=Notarized Developer ID" |
| M3 | Copy the DMG to a Mac (or a user account) that has never built lingoSwen; open it and drag to Applications; launch | No Gatekeeper block; the setup window opens; Finder › Get Info on the app shows 1.0.1 |
| M4 | On your own Mac, quit the dev build and launch the installed one | macOS asks for Accessibility again once (a new signature); after granting, Translate works |

**Risk to your setup:** the installed app and the dev build share `~/Library/Application Support/ch.lingoswen/` (config and history) and the bundle ID, so they must not run at the same time; the Accessibility grant holds for whichever signature was granted last. To go back to the dev build, quit the installed one, run `Tools/make-app.sh --run` and grant again.
