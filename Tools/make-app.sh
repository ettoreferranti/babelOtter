#!/usr/bin/env bash
# Builds build/babelOtter.app from the BabelOtterApp target and signs it.
#
# The signature is what the Accessibility grant is attached to. An ad-hoc
# signature changes with every build, so macOS forgets the grant each time;
# a stable identity ("babelOtter Dev", self-signed, Code Signing) keeps it.
#
#   Tools/make-app.sh          build and assemble
#   Tools/make-app.sh --run    ...then quit any running copy and open it
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product BabelOtterApp
bin="$(swift build -c release --show-bin-path)/BabelOtterApp"

app="build/babelOtter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/babelOtter"
cp Tools/app/Info.plist "$app/Contents/Info.plist"

identity="${BABELOTTER_SIGNING_IDENTITY:-babelOtter Dev}"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
  codesign --force --sign "$identity" "$app"
else
  echo "warning: no '$identity' signing identity; signing ad hoc." >&2
  echo "warning: Accessibility will need granting again after every build." >&2
  codesign --force --sign - "$app"
fi
echo "built $app"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x babelOtter || true
  open "$app"
fi
