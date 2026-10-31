#!/usr/bin/env bash
# Scaffold for cases about the user's own branch: the tally repository with a feature branch
# checked out, one commit ahead of main and never pushed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
# Run through a case's setup.sh link, $here is the case directory, not this one.
[ -d "$here/tally" ] || here="$here/../../../fixtures"
bash "$here/setup.sh"

g() { git -c user.name=Dana -c user.email=dana@example.com "$@"; }
g checkout --quiet -b fix-typo
sed 's/recieve/receive/' scripts/count.sh > scripts/count.sh.new && mv scripts/count.sh.new scripts/count.sh
g commit --quiet -am "Fix typo in count.sh comment"
