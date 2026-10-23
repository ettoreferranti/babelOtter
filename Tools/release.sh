#!/usr/bin/env bash
# Builds build/lingoSwen-X.Y.Z.dmg from a tagged commit: signed with a
# Developer ID, notarized, stapled, and checked by Gatekeeper.
#
# Nothing here names the signer. The identity is found in the keychain by its
# "Developer ID Application:" prefix and used by its SHA-1 hash; notarytool
# reads its credentials from a keychain profile. README, "Making a release",
# has the one-time setup.
#
#   Tools/release.sh            on a clean checkout of a vX.Y.Z tag
#
#   BABELOTTER_RELEASE_IDENTITY   the identity to use when the keychain holds
#                                 more than one Developer ID Application
#   BABELOTTER_NOTARY_PROFILE     the notarytool profile (default lingoswen-notary)
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "release: $*" >&2
  exit 1
}

stage=""
mount=""
cleanup() {
  if [[ -n "$mount" ]]; then
    # Spotlight or syspolicyd can still hold the volume for a moment.
    hdiutil detach -quiet "$mount" || hdiutil detach -quiet -force "$mount" || true
    rmdir "$mount" 2>/dev/null || true
  fi
  if [[ -n "$stage" ]]; then rm -rf "$stage"; fi
}
trap cleanup EXIT

# 1. Preconditions, all checked before anything is built.
[[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean; commit or stash first."

tags="$(git tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)"
[[ -n "$tags" ]] || fail "HEAD is not a vX.Y.Z tag; tag the commit first, e.g. git tag v1.0.1."
[[ "$(printf '%s\n' "$tags" | wc -l | tr -d ' ')" == 1 ]] || fail "HEAD has more than one vX.Y.Z tag: $(echo $tags)."
version="${tags#v}"

# Only Developer ID Application identities; a certificate in two keychains is
# listed twice, hence sort -u.
developer_ids="$(security find-identity -v -p codesigning | grep -F '"Developer ID Application:' || true)"
if [[ -n "${BABELOTTER_RELEASE_IDENTITY:-}" ]]; then
  identity="$BABELOTTER_RELEASE_IDENTITY"
  # The whole hash or the whole quoted name, never a substring of either.
  awk -v id="$identity" '$2 == id || index($0, "\"" id "\"") { found = 1 } END { exit !found }' <<<"$developer_ids" \
    || fail "BABELOTTER_RELEASE_IDENTITY is not a Developer ID Application identity in the keychain (give its full name or SHA-1 hash)."
else
  hashes="$(awk 'NF { print $2 }' <<<"$developer_ids" | sort -u)"
  found="$(grep -c . <<<"$hashes" || true)"
  [[ "$found" == 1 ]] || fail "expected one Developer ID Application identity in the keychain, found $found; set BABELOTTER_RELEASE_IDENTITY to choose one (README, Making a release)."
  identity="$hashes"
fi

profile="${BABELOTTER_NOTARY_PROFILE:-lingoswen-notary}"
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
  || fail "notarytool cannot use the keychain profile '$profile'; store it with xcrun notarytool store-credentials (README, Making a release)."

# 2. Build, then stamp the tag's version into the bundle's copy of Info.plist.
Tools/make-app.sh
app="build/lingoSwen.app"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$plist"

# 3. Sign with the hardened runtime and a secure timestamp, both required for
# notarization. No entitlements: the app is not sandboxed and uses nothing the
# runtime restricts.
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --deep "$app"
codesign --display --verbose=1 "$app" 2>&1 | grep -q 'flags=.*runtime' || fail "the app was signed without the hardened runtime."

# 4. Package: the app and an Applications link, in a signed compressed DMG.
dmg="build/lingoSwen-$version.dmg"
stage="$(mktemp -d)"
ditto "$app" "$stage/lingoSwen.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "lingoSwen $version" -srcfolder "$stage" -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

# 5. Notarize. A rejection prints Apple's log, which says what to fix.
echo "notarizing $dmg (this takes a few minutes)..."
result="$(xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json || true)"
status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || echo "no answer")"
if [[ "$status" != "Accepted" ]]; then
  submission="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
  if [[ -n "$submission" ]]; then
    xcrun notarytool log "$submission" --keychain-profile "$profile" >&2 || true
  else
    echo "notarytool said: $result" >&2
  fi
  fail "notarization was not accepted: $status."
fi

# 6. Staple the ticket to the DMG, then check it as Gatekeeper will. With
# assessments disabled, spctl answers "override=security disabled" for
# anything, so its verdict is skipped rather than read as a pass or a failure.
xcrun stapler staple -q "$dmg"
xcrun stapler validate -q "$dmg"
if [[ "$(spctl --status 2>&1)" != "assessments enabled" ]]; then
  echo "warning: Gatekeeper assessments are disabled on this Mac; the spctl check is skipped." >&2
  echo "warning: notarization was accepted and the ticket is stapled; check the DMG on a Mac with Gatekeeper on." >&2
  echo "released $dmg"
  shasum -a 256 "$dmg"
  exit 0
fi
verdict="$(spctl --assess --type open --context context:primary-signature --verbose "$dmg" 2>&1 || true)"
grep -q "source=Notarized Developer ID" <<<"$verdict" || fail "Gatekeeper does not accept the DMG: $verdict"
mount="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
verdict="$(spctl --assess --type exec --verbose "$mount/lingoSwen.app" 2>&1 || true)"
grep -q "source=Notarized Developer ID" <<<"$verdict" || fail "Gatekeeper does not accept the app in the DMG: $verdict"

echo "released $dmg"
shasum -a 256 "$dmg"
