#!/usr/bin/env bash
# Scaffold for every case: copies the tally fixture into the run's empty workspace (the
# current directory) and commits it, so the run sees an ordinary small repository.
# Each case's setup.sh links here. The harness may pass the resolved path or the link itself.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fixture="$here/tally"
[ -d "$fixture" ] || fixture="$here/../../../fixtures/tally"
[ -d "$fixture" ] || { echo "fixture not found: $fixture" >&2; exit 1; }

cp -R "$fixture/." .
git init --quiet -b main
git -c user.name=Dana -c user.email=dana@example.com add -A
git -c user.name=Dana -c user.email=dana@example.com commit --quiet -m "Initial tally scripts"
