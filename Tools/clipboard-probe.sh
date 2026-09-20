#!/bin/bash
#
# Is the clipboard conduit viable?
#
# Spike #30 named the clipboard "tier 3" and reached it by elimination, never
# simulating a Command-C or Command-V. So every tier-3 verdict in
# docs/architecture.md means "Accessibility cannot do it", not "the clipboard
# can". This measures the second claim.
#
# Usage:  Tools/clipboard-probe.sh [--paste] [--conceal] [rounds]
#
#   --paste    also press Command-V to replace the selection. Modifies text;
#              use a scratch document. Confirms at the prompt first.
#   --conceal  afterwards, leave a CONCEALED item on the pasteboard so you can
#              check on another Mac whether Universal Clipboard synced it.
#              PRIVACY.md records that as unverified; this is how to verify it.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# Defaulted because macOS ships bash 3.2, where expanding an empty array under
# `set -u` is an error rather than nothing.
PROBE_ARGS=("${@:-4}")
BUILD="$(mktemp -d /tmp/babelotter-clipboard.XXXXXX)"
LOG="$HOME/babelotter-clipboard-probe-$(date +%Y%m%d-%H%M%S).txt"
trap 'rm -rf "$BUILD"' EXIT

run_probe() {
    echo "=== babelOtter clipboard probe - $(date) ==="
    sw_vers
    echo

    if ! command -v swiftc >/dev/null 2>&1; then
        echo "swiftc not found. Run 'xcode-select --install', then rerun."
        return 1
    fi
    if ! swiftc "$HERE/clipboard-probe.swift" -o "$BUILD/clipboard-probe"; then
        echo "compile failed"
        return 1
    fi
    "$BUILD/clipboard-probe" "${PROBE_ARGS[@]}"
}

run_probe 2>&1 | tee "$LOG"

echo
echo "Transcript saved to: $LOG"
