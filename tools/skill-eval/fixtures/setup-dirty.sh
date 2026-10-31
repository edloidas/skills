#!/usr/bin/env bash
# Scaffold for cases about the current changes: the tally repository with an uncommitted,
# staged edit to count.sh that adds stdin support and quietly drops the empty-file case.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
# Run through a case's setup.sh link, $here is the case directory, not this one.
[ -d "$here/tally" ] || here="$here/../../../fixtures"
bash "$here/setup.sh"

cat > scripts/count.sh <<'SCRIPT'
#!/usr/bin/env bash
# Prints the byte count of a file, or of standard input when no file is given.
set -eu
if [ "$#" -eq 0 ]; then
  wc -c | tr -d ' '
else
  wc -c < $1 | tr -d ' '
fi
SCRIPT
git add scripts/count.sh
