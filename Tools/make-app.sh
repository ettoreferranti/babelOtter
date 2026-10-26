#!/usr/bin/env bash
# Builds build/lingoSwen.app from the BabelOtterApp target and signs it.
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

app="build/lingoSwen.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/lingoSwen"
cp Tools/app/Info.plist "$app/Contents/Info.plist"
cp Tools/app/Mascot.png "$app/Contents/Resources/Mascot.png"
# The Privacy panel opens this build's own copy (#72).
cp PRIVACY.md "$app/Contents/Resources/PRIVACY.md"
# The built-in server (#126): Ollama's official macOS build, pinned in
# Tools/ollama.lock, unchanged. Its binaries keep Ollama's own Developer ID
# signatures (hardened runtime, timestamped); the app's signature seals them.
ollama="$(Tools/fetch-ollama.sh)"
ditto "$ollama" "$app/Contents/Resources/ollama"

# The app icon, from the same picture padded to a square.
work="$(mktemp -d)"
side="$(sips -g pixelWidth -g pixelHeight Tools/app/Mascot.png | awk '/pixel/ {print $2}' | sort -n | tail -1)"
sips -s format png --padToHeightWidth "$side" "$side" Tools/app/Mascot.png --out "$work/square.png" >/dev/null
mkdir "$work/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/square.png" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/square.png" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$work"

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
  pkill -x lingoSwen || true
  pkill -x babelOtter || true
  open "$app"
fi
