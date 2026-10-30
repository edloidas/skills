#!/usr/bin/env bash
# Scaffold for cases that need a rebase stopped on a conflict: the tally repository, plus a
# feature branch and main that both rewrote the same line of count.sh.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/setup.sh"

g() { git -c user.name=Dana -c user.email=dana@example.com "$@"; }
g checkout --quiet -b feature/lines
sed 's/wc -c/wc -l/' scripts/count.sh > scripts/count.sh.new && mv scripts/count.sh.new scripts/count.sh
g commit --quiet -am "Count lines instead of bytes"
g checkout --quiet main
sed 's/wc -c/wc -m/' scripts/count.sh > scripts/count.sh.new && mv scripts/count.sh.new scripts/count.sh
g commit --quiet -am "Count characters, not bytes"
g checkout --quiet feature/lines
g rebase main >/dev/null 2>&1 || true
