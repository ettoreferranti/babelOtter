#!/usr/bin/env bash
# Mutation testing on this Mac, as CI runs it (.github/workflows/mutation.yml),
# so a muter problem shows up in minutes rather than after a CI round.
#
# Installs muter on first use into build/tools/muter: the same tag, checksum
# and log-decoding patch as CI (#94). This Mac's Swift is newer than CI's
# (6.1.2), so a local pass does not replace CI; it catches the rest early.
#
#   Tools/mutate.sh              kit files changed since main
#   Tools/mutate.sh <file>...    those kit files
#   Tools/mutate.sh --all        every kit file, both passes, as CI (long)
#   Tools/mutate.sh --check      only check that mutation.yml lists every kit file
#
# Every run first checks the file list, as CI's first step does. The gate is
# CI's: at least 80% killed, no mutant that failed to build, and no survivor
# at all when fewer than 20 mutants were applied.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "mutate: $*" >&2
  exit 1
}

workflow=".github/workflows/mutation.yml"
tools="build/tools"
muter="$tools/muter/bin/muter"

install_muter() {
  if [[ -x "$muter" ]]; then return; fi
  echo "mutate: installing muter 16 into $tools (once)..." >&2
  mkdir -p "$tools"
  curl --fail --location --silent --show-error --proto '=https' -o "$tools/muter.zip" \
    https://github.com/muter-mutation-testing/muter/archive/refs/tags/16.zip
  echo "de8c5f73f5f2810e83e6c72a5a429d0328f90df25842f8c581b4e66a3c694076  $tools/muter.zip" | shasum -a 256 -c - >/dev/null \
    || fail "muter.zip does not match its checksum."
  rm -rf "$tools/muter-16"
  unzip -q "$tools/muter.zip" -d "$tools"
  local file="$tools/muter-16/Sources/muterCore/MutationTesting/MutationTestingIODelegate.swift"
  export OLD='let contents = try String(contentsOf: testLogUrl)'
  export NEW='let contents = String(decoding: try Data(contentsOf: testLogUrl), as: UTF8.self)'
  perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$file"
  local patched
  patched="$(cat "$file")"
  grep -qF "$NEW" <<<"$patched" || fail "the log-decoding patch did not apply (#94)."
  make -C "$tools/muter-16" install prefix="$PWD/$tools/muter" >/dev/null
}

# The two lists, read from the workflow so they cannot drift from CI's.
pass1="$(awk '/PASS1="/ { on = 1; sub(/.*PASS1="/, "") } on { line = $0; gsub(/^ +|"$/, "", line); print line } on && /"$/ { exit }' "$workflow")"
pass2="$(sed -n 's/.*PASS2="\(.*\)"/\1/p' "$workflow")"
[[ -n "$pass1" ]] || fail "could not read PASS1 from $workflow."
[[ -n "$pass2" ]] || fail "could not read PASS2 from $workflow."

listed="$(printf '%s\n%s\n' "$pass1" "$pass2" | sort)"
actual="$(find Sources/BabelOtterKit -name '*.swift' | sort)"
if [[ "$listed" != "$actual" ]]; then
  echo "mutate: $workflow does not list exactly the kit files. Add each new file to PASS1 ('>' on disk only, '<' listed only):" >&2
  diff <(printf '%s\n' "$listed") <(printf '%s\n' "$actual") >&2 || true
  exit 1
fi
echo "mutate: $workflow lists every kit file."

case "${1:-}" in
  --check)
    exit 0
    ;;
  --all)
    files="$actual"
    ;;
  "")
    files="$(git diff --name-only main...HEAD -- Sources/BabelOtterKit; git diff --name-only -- Sources/BabelOtterKit)"
    files="$(printf '%s\n' "$files" | grep -E '\.swift$' | sort -u || true)"
    # Deleted files have nothing to mutate.
    existing=""
    while IFS= read -r file; do
      if [[ -n "$file" && -f "$file" ]]; then existing+="$file"$'\n'; fi
    done <<<"$files"
    files="$existing"
    [[ -n "$files" ]] || { echo "mutate: no kit file changed since main."; exit 0; }
    ;;
  *)
    files="$(printf '%s\n' "$@")"
    while IFS= read -r file; do
      grep -qxF "$file" <<<"$actual" || fail "$file is not a kit source file."
    done <<<"$files"
    ;;
esac

install_muter

reports=()
run_pass() {
  # Absolute: muter writes it from inside its copy of the project.
  local name="$1" report="$PWD/$tools/mutate-$1.json"
  shift
  local args=()
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then args+=(--files-to-mutate "$file"); fi
  done <<<"$selected"
  [[ ${#args[@]} -gt 0 ]] || return 0
  echo "mutate: pass $name on $(grep -c . <<<"$selected") file(s); muter's log is in $tools/mutate-$name.log"
  if ! "$muter" run "${args[@]}" "$@" --format json -o "$report" >"$tools/mutate-$name.log" 2>&1; then
    local log
    log="$(cat "$tools/mutate-$name.log")"
    if grep -q "initially failed" <<<"$log"; then
      fail "the tests fail before any mutant (muter copies untracked files too, such as evals/results/); run swift test. Log: $tools/mutate-$name.log"
    fi
    fail "muter failed in pass $name; see $tools/mutate-$name.log."
  fi
  reports+=("$report")
}

# Pass 2 holds the files that need RelationalOperatorReplacement left out
# (muter.conf.yml, KNOWN BUG); everything else runs in pass 1.
selected="$(grep -vxF -f <(printf '%s\n' "$pass2") <<<"$files" || true)"
run_pass 1
selected="$(grep -xF -f <(printf '%s\n' "$pass2") <<<"$files" || true)"
run_pass 2 --operators ChangeLogicalConnector RemoveSideEffects SwapTernary

[[ ${#reports[@]} -gt 0 ]] || fail "no files to mutate."

count() {
  jq -s --arg outcome "$1" '[.[].fileReports[]?.appliedOperators[]? | select(.testSuiteOutcome == $outcome)] | length' "${reports[@]}"
}
total="$(jq -s '[.[].totalAppliedMutationOperators] | add' "${reports[@]}")"
killed="$(jq -s '[.[].numberOfKilledMutants] | add' "${reports[@]}")"
survived="$(count passed)"
unbuilt="$(count buildError)"

# Each survivor or unbuilt mutant as file:line operator.
jq -s -r '.[].fileReports[]? | .path as $file | .appliedOperators[]?
  | select(.testSuiteOutcome == "passed" or .testSuiteOutcome == "buildError")
  | "  \(.testSuiteOutcome == "passed" | if . then "survived" else "did not build" end): \($file):\(.mutationPoint.position.line) \(.mutationPoint.mutationOperatorId)"' \
  "${reports[@]}"

[[ "$total" -gt 0 ]] || fail "no mutants were applied; muter did not really run."
score="$(awk "BEGIN { printf \"%.1f\", ($killed * 100.0) / $total }")"
echo "mutate: $killed/$total killed ($score%), $survived survived, $unbuilt did not build."
[[ "$unbuilt" -eq 0 ]] || fail "$unbuilt mutant(s) did not build, so nothing was learned about them."
if [[ "$total" -lt 20 && "$survived" -gt 0 ]]; then
  fail "fewer than 20 mutants, so none may survive (as in CI)."
fi
awk "BEGIN { exit !($killed * 100 >= 80 * $total) }" || fail "below the 80% gate."
echo "mutate: passes the gate."
