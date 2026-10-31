#!/usr/bin/env bash
# Scaffold for cases about the test suite: the tally repository plus a small test file whose
# assertions check little.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
# Run through a case's setup.sh link, $here is the case directory, not this one.
[ -d "$here/tally" ] || here="$here/../../../fixtures"
bash "$here/setup.sh"

mkdir -p tests
cat > tests/count.test.sh <<'TESTS'
#!/usr/bin/env bash
# Tests for scripts/count.sh.
set -u
fail=0
out="$(bash scripts/count.sh README.md)"
[ -n "$out" ] || { echo "FAIL: prints something for README.md"; fail=1; }
out="$(bash scripts/count.sh README.md)"
[ "$out" = "$out" ] || { echo "FAIL: output is stable"; fail=1; }
bash scripts/count.sh README.md >/dev/null 2>&1 || true
echo "ok: runs without crashing"
exit "$fail"
TESTS
git -c user.name=Dana -c user.email=dana@example.com add tests
git -c user.name=Dana -c user.email=dana@example.com commit --quiet -m "Add count.sh tests"
