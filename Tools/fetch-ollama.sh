#!/usr/bin/env bash
# Downloads the Ollama pinned in Tools/ollama.lock into build/cache/, checks
# its SHA-256, and unpacks it. Prints the unpacked folder. Downloads only when
# the archive is not cached; a cached archive is checked again every time.
#
#   Tools/fetch-ollama.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "fetch-ollama: $*" >&2
  exit 1
}

value() {
  local found
  found="$(grep -E "^$1=" Tools/ollama.lock | head -1 | cut -d= -f2-)"
  [[ -n "$found" ]] || fail "Tools/ollama.lock has no $1."
  printf '%s' "$found"
}

version="$(value version)"
url="$(value url)"
sha256="$(value sha256)"

cache="build/cache"
archive="$cache/ollama-$version-darwin.tgz"
unpacked="$cache/ollama-$version"
mkdir -p "$cache"

if [[ ! -f "$archive" ]]; then
  echo "fetch-ollama: downloading Ollama $version..." >&2
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 -o "$archive.partial" "$url"
  mv "$archive.partial" "$archive"
fi

actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$sha256" ]]; then
  rm -f "$archive"
  fail "$archive does not match Tools/ollama.lock (got $actual); it was deleted. Run again to download it afresh."
fi

rm -rf "$unpacked"
mkdir -p "$unpacked"
tar -xzf "$archive" -C "$unpacked"
[[ -x "$unpacked/ollama" ]] || fail "the archive has no ollama binary at its top level."
printf '%s\n' "$unpacked"
