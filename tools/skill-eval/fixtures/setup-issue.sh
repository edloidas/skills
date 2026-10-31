#!/usr/bin/env bash
# Scaffold for cases that hand the run an issue: the tally repository, plus the issue's text
# saved as a local file, since `gh` is not signed in inside a run.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
# Run through a case's setup.sh link, $here is the case directory, not this one.
[ -d "$here/tally" ] || here="$here/../../../fixtures"
bash "$here/setup.sh"

cat > issue-12.md <<'ISSUE'
# Read from stdin when no file is given #12

Opened by dana · label: enhancement

`count.sh` requires a path today. When it is called with no argument it should read standard
input instead, so it works at the end of a pipe:

```sh
cat notes.txt | scripts/count.sh
```

Acceptance:

- `scripts/count.sh notes.txt` behaves as before.
- `printf 'abc' | scripts/count.sh` prints `3`.
- The README's Usage section shows the pipe form.
ISSUE
