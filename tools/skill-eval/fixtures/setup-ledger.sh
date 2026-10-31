#!/usr/bin/env bash
# Scaffold for the live suite: copies the ledger fixture into the run's empty workspace (the
# current directory) and commits it as three commits by two authors, then applies a variant.
#
#   bash setup-ledger.sh <variant>
#
# Variants: plain, bug (parseAmount mishandles one-digit cents), perf (adds a 30k-line ledger),
# review (an uncommitted change with planted defects), issue / issue-false (bug, plus an issue
# text file whose stated cause is right / wrong), reflect (plain, plus synthetic transcripts in
# $HOME), and runbook (plain, without the Running section).
set -eu
variant="${1:?usage: setup-ledger.sh <variant>}"
here="$(cd "$(dirname "$0")" && pwd)"
fixture="$here/ledger"
extra="$here/ledger-extra"
[ -d "$fixture" ] || { echo "fixture not found: $fixture" >&2; exit 1; }

commit() {
  name="$1"; email="$2"; date="$3"; msg="$4"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -c user.name="$name" -c user.email="$email" commit --quiet -m "$msg"
}

cp -R "$fixture/." .
if [ "$variant" = bug ] || [ "$variant" = issue ] || [ "$variant" = issue-false ]; then
  cp "$extra/amount-bug.js" src/amount.js
fi
if [ "$variant" = perf ]; then
  awk 'BEGIN { srand(7); for (i = 0; i < 30000; i++) { m = int(rand() * 15000);
    printf "2026-%02d-%02d, shop-%05d, %d.%02d\n", (i % 12) + 1, (i % 28) + 1, m, int(rand() * 90) + 1, int(rand() * 100) } }' \
    > examples/year.txt
fi

git init --quiet -b main
git add package.json README.md AGENTS.md .gitignore src/amount.js src/ledger.js bin/total.js test examples
commit Dana dana@example.com "2026-09-02T10:00:00Z" "Initial ledger tools"
git add src/calendar.js bin/weekend.js
commit "Lee Okafor" lee@example.com "2026-09-15T16:20:00Z" "Add weekend listing"
git add -A
commit Dana dana@example.com "2026-10-01T09:30:00Z" "Add merchants listing and HTTP server"

case "$variant" in
  review) git apply "$extra/average.patch" ;;
  issue) cp "$extra/issue-true.md" issue-17.md ;;
  issue-false) cp "$extra/issue-false.md" issue-17.md ;;
  reflect) bash "$extra/seed-transcripts.sh" "$PWD" ;;
esac
