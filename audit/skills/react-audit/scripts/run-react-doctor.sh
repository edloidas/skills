#!/usr/bin/env bash
# run-react-doctor.sh — Run react-doctor over a scope, when it is available.
#
# Usage: run-react-doctor.sh <project-dir> <output-file> <diagnostics-dir> [scope-arg ...]
#
# <output-file>      human-readable summary, as printed to the terminal
# <diagnostics-dir>  react-doctor writes diagnostics.json plus one .txt per rule here;
#                    diagnostics.json is the one worth parsing
#
# Scope args are passed straight through to react-doctor. Pass one of:
#   --scope files --include-untracked   scan the files changed in the working tree
#   --scope changed --base <ref>        report only issues new since <ref>
#   --staged                            scan staged changes only
#   (nothing)                           scan the whole project
#
# Exit codes:
#   0  ran to completion — read <diagnostics-dir>/diagnostics.json
#   1  ran and gated on severity, or failed for its own reasons — read <output-file>
#   3  no package runner available — the track is skipped, not failed
#   4  react-doctor could not be started — the track is skipped, not failed
#
# A warning-level finding still exits 0, so the exit code says whether the tool ran,
# never whether the code is clean. Read diagnostics.json either way.
#
# Writes nothing into the project directory. Telemetry, the score API, and crash
# reporting are all opted out, so no source metadata leaves the machine.

set -uo pipefail

PROJECT_DIR="${1:-.}"
OUTPUT_FILE="${2:-/dev/stdout}"
DIAGNOSTICS_DIR="${3:-}"
REQUESTED_DIR="$PROJECT_DIR"
shift 3 2>/dev/null || true
SCOPE_ARGS=("$@")

if [[ -z "$DIAGNOSTICS_DIR" ]]; then
  echo "ERROR: no diagnostics directory given." > "$OUTPUT_FILE"
  echo "Usage: run-react-doctor.sh <project-dir> <output-file> <diagnostics-dir> [scope-arg ...]" >> "$OUTPUT_FILE"
  exit 4
fi
mkdir -p "$DIAGNOSTICS_DIR" 2>/dev/null || true

PROBE_TIMEOUT=60
RUN_TIMEOUT=180

# GNU coreutils `timeout` is not on stock macOS. Without it the run is unbounded
# rather than skipped — a slow scan beats no scan.
if command -v timeout &>/dev/null; then
  TIMEOUT=(timeout)
elif command -v gtimeout &>/dev/null; then
  TIMEOUT=(gtimeout)
else
  TIMEOUT=()
fi

# bash 3.2 (the macOS default) errors on an empty array expansion under `set -u`,
# so every array below is expanded through this guard.
run_with_timeout() {
  local seconds="$1"
  shift
  if [[ ${#TIMEOUT[@]} -gt 0 ]]; then
    "${TIMEOUT[@]}" "$seconds" "$@"
  else
    "$@"
  fi
}

if ! PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)"; then
  echo "ERROR: project directory not found: $REQUESTED_DIR" > "$OUTPUT_FILE"
  exit 4
fi

# Prefer an already-installed binary; otherwise fetch it with a package runner.
# bunx first — it is the fastest of the three and the preferred runner here; npx last.
if [[ -x "$PROJECT_DIR/node_modules/.bin/react-doctor" ]]; then
  RUNNER=("$PROJECT_DIR/node_modules/.bin/react-doctor")
elif command -v react-doctor &>/dev/null; then
  RUNNER=(react-doctor)
elif command -v bunx &>/dev/null; then
  RUNNER=(bunx react-doctor@latest)
elif command -v pnpm &>/dev/null; then
  RUNNER=(pnpm dlx react-doctor@latest)
elif command -v npx &>/dev/null; then
  RUNNER=(npx --yes react-doctor@latest)
else
  echo "SKIPPED: no react-doctor binary and no bunx/pnpm/npx to fetch one." > "$OUTPUT_FILE"
  exit 3
fi

# Probe before committing to a full run, so "tool unavailable" is distinguishable
# from "tool ran and found issues" — both of which react-doctor reports as non-zero.
if ! run_with_timeout "$PROBE_TIMEOUT" "${RUNNER[@]}" --version >/dev/null 2>&1 < /dev/null; then
  echo "SKIPPED: react-doctor could not be started via '${RUNNER[*]}'." > "$OUTPUT_FILE"
  echo "Offline, or the package failed to resolve. Re-run the audit without this track." >> "$OUTPUT_FILE"
  exit 4
fi

echo "Running react-doctor via ${RUNNER[*]}..." >&2

run_with_timeout "$RUN_TIMEOUT" "${RUNNER[@]}" \
  --cwd "$PROJECT_DIR" \
  --no-dead-code \
  --no-supply-chain \
  --no-telemetry \
  --no-score \
  --output-dir "$DIAGNOSTICS_DIR" \
  --verbose \
  --yes \
  ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"} \
  > "$OUTPUT_FILE" 2>&1 < /dev/null
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 124 && ${#TIMEOUT[@]} -gt 0 ]]; then
  echo "" >> "$OUTPUT_FILE"
  echo "WARNING: react-doctor timed out after ${RUN_TIMEOUT}s — output above is partial." >> "$OUTPUT_FILE"
  exit 1
fi

# `--yes` plus a closed stdin keeps every invocation non-interactive, so a prompt can
# never hang the run. Non-zero here means gating or a tool-side failure, never "issues
# found" on its own.
echo "react-doctor exited with code $EXIT_CODE." >&2
echo "Diagnostics: $DIAGNOSTICS_DIR/diagnostics.json" >&2
exit "$EXIT_CODE"
