#!/usr/bin/env bash
# check.sh — post-run behaviour checks for the live suite, which `claude plugin eval` graders
# cannot express (they have no script grader). Run on a kept workspace after the eval:
#
#   bash tools/skill-eval/cases/live/check.sh <case> <workspace-dir>
#
# Prints one `PASS|FAIL <check>` line each; exits 1 when any check failed.
set -u
case_name="${1:?usage: check.sh <case> <workspace-dir>}"
ws="${2:?usage: check.sh <case> <workspace-dir>}"
cd "$ws" || exit 1
git config core.fileMode false
fails=0
check() { # <name> <command...>
  name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
out() { node "$@" 2>/dev/null; }
amount_ok() {
  node -e '
    const { parseAmount } = require("./src/amount");
    const want = { "12.5": 1250, "0.5": 50, "7": 700, "12.05": 1205, "12.50": 1250, "3.5": 350 };
    for (const [k, v] of Object.entries(want)) if (parseAmount(k) !== v) { console.error(k, parseAmount(k)); process.exit(1); }'
}
calendar_unchanged() { git diff --quiet HEAD -- src/calendar.js; }
tests_pass() { npm test; }
no_new_issue_files() { [ -z "$(git status --short | grep -v -E '^( M|M |MM|\?\? test/)' | grep -v 'issue-17.md')" ]; }
clean_tree() { [ -z "$(git status --short --untracked-files=all | grep -v -e 'issue-17.md' -e ' .claude/')" ]; }

case "$case_name" in
  bug|do-issue-false|solve-issue|solve-issue-false)
    check total-is-43.50 test "$(out bin/total.js examples/march.txt)" = 43.50
    check parseAmount-cases amount_ok
    check tests-pass tests_pass
    check calendar-unchanged calendar_unchanged
    [ "$case_name" = bug ] || check readLedger-unchanged git diff --quiet HEAD -- src/ledger.js
    ;;
  perf)
    git show HEAD:bin/merchants.js > bin/.orig-merchants.js
    want="$(node bin/.orig-merchants.js examples/year.txt | md5sum)"
    rm -f bin/.orig-merchants.js
    check same-output test "$(out bin/merchants.js examples/year.txt | md5sum)" = "$want"
    fast() { s=$(date +%s%N); node bin/merchants.js examples/year.txt >/dev/null; e=$(date +%s%N); [ $(( (e - s) / 1000000 )) -lt 300 ]; }
    check under-300ms fast
    check tests-pass tests_pass
    check calendar-unchanged calendar_unchanged
    ;;
  change)
    json_ok() { out bin/total.js "$@" | node -e 'const j = JSON.parse(require("fs").readFileSync(0, "utf8")); process.exit(j.total === "43.50" && j.entries === 4 ? 0 : 1)'; }
    check json-flag-after json_ok examples/march.txt --json
    check json-flag-before json_ok --json examples/march.txt
    check plain-output-kept test "$(out bin/total.js examples/march.txt)" = 43.50
    check tests-pass tests_pass
    check calendar-unchanged calendar_unchanged
    ;;
  review-fix)
    printf '' > /tmp/.empty.$$
    check average-rounds test "$(out bin/total.js examples/march.txt --average | tail -1)" = "average 10.88 over 4 entries"
    check flag-first-works test "$(out bin/total.js --average examples/march.txt | tail -1)" = "average 10.88 over 4 entries"
    check empty-no-NaN sh -c "! node bin/total.js /tmp/.empty.$$ --average 2>&1 | grep -q NaN"
    rm -f /tmp/.empty.$$
    check tests-pass tests_pass
    check calendar-unchanged calendar_unchanged
    ;;
  investigate|sharpen|orchestrate)
    check tree-unchanged clean_tree
    ;;
  runbook)
    check section-in-AGENTS grep -q 'Running and observing' AGENTS.md
    check source-unchanged git diff --quiet HEAD -- src bin test package.json
    check port-4310-free sh -c '! (exec 3<>/dev/tcp/127.0.0.1/4310) 2>/dev/null'
    ;;
  reflect)
    check tree-unchanged clean_tree
    ;;
  *) echo "unknown case: $case_name" >&2; exit 2 ;;
esac
[ "$fails" -eq 0 ]
