#!/bin/bash
#
# babelOtter Accessibility diagnostic.
#
# Answers two things docs/architecture.md section 7 lists as unmeasured:
# whether a managed Mac permits the Accessibility grant at all, and which
# capture tier works in each app tried.
#
# Reads only. Writes a scratch build to a temp dir and one transcript in ~.
#
# Usage:  Tools/ax-probe.sh [rounds]     (default 6)

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROUNDS="${1:-6}"
BUILD="$(mktemp -d /tmp/babelotter-probe.XXXXXX)"
LOG="$HOME/babelotter-ax-probe-$(date +%Y%m%d-%H%M%S).txt"
trap 'rm -rf "$BUILD"' EXIT

run_checks() {
    echo "=== babelOtter Accessibility probe - $(date) ==="
    sw_vers
    echo "hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo

    echo "=== 1. admin rights ==="
    if id -Gn | tr ' ' '\n' | grep -qx admin; then
        echo "admin: yes"
    else
        echo "admin: NO - an Accessibility grant needs admin, so this alone may be the answer"
    fi
    echo

    echo "=== 2. MDM and privacy policy payloads ==="
    # The MDM server URL names the employer, and these transcripts get shared.
    profiles status -type enrollment 2>/dev/null \
        | sed "s|https://[^ ]*|<redacted MDM server>|"
    echo "--- TCC / privacy payloads: names and keys only ---"
    echo "    (system_profiler can take 10-30s on a managed Mac; it is not stuck)"
    echo "    NOTE: this describes your employer's management profiles. Read it"
    echo "    before sharing the transcript anywhere public."
    #
    # Patterns are ANCHORED to the start of a line, and every line is truncated.
    # An earlier version grepped case-insensitively for "TCC" anywhere on a
    # line. Base64 contains the substring "tcc" readily, so that matched the
    # middle of a Microsoft Defender onboarding blob and dumped an org GUID, a
    # signature and a full certificate chain into the transcript. Short tokens
    # matched against unanchored output containing encoded data is a good way
    # to leak a secret you did not know was there.
    system_profiler SPConfigurationProfileDataType 2>/dev/null \
        | grep -aE "^[[:space:]]*(Name|Identifier|Description):|^[[:space:]]*com\.apple\.TCC\.configuration-profile-policy:|^[[:space:]]*Accessibility =" \
        | cut -c1-140 \
        | sed 's/^/  /' \
        | head -60
    echo "--- end ---"
    echo

    if ! command -v swiftc >/dev/null 2>&1; then
        echo "swiftc not found. Run 'xcode-select --install', then rerun."
        return 1
    fi

    if ! swiftc "$HERE/ax-probe.swift" -o "$BUILD/ax-probe"; then
        echo "compile failed"
        return 1
    fi

    "$BUILD/ax-probe" "$ROUNDS"
}

run_checks 2>&1 | tee "$LOG"

echo
echo "Transcript saved to: $LOG"
