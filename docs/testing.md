# Script Tests

Read this when adding or changing a bundled shell script, or a per-skill rule in
`validate-skills.sh`.

`tests/` holds behavioral tests for the shell scripts this repo bundles. Plain bash, no
install step, no new dependency:

```bash
bash tests/run.sh                    # everything
bash tests/run.sh detect-base        # only files whose path matches
```

**Tests live at the repo root, never inside a skill.** A `tests/` directory under
`skills/<name>/` would be symlinked into every generated host tree and ship inside
the installed plugin. `tests/skills/<skill>/<script>.test.sh` mirrors the skill path
instead, so the distribution layer never sees them.

A test file sources `tests/lib/assert.sh` and `tests/lib/fixture.sh`, defines `test_*`
functions, and ends with `run_tests`. Each case runs in its own subshell in its own sandbox
directory, with `HOME`, `TMPDIR`, and `XDG_CONFIG_HOME` pointed inside it and every
environment variable the scripts under test consult unset — `CLAUDECODE`, `OUTSIDER_*`,
`GIT_DIR`, and the rest. A script that starts reading a new variable needs that variable
added to the scrub in `run_tests`, or a case will pass or fail based on who ran it. `fixture.sh` builds throwaway git
repos with a local bare "remote" and replaces `PATH` with a sandbox pair — a stub directory
plus symlinks to a fixed list of core tools — which is what makes "the tool is not
installed" testable at all. Nothing reaches the network, real `$HOME`, or a real remote.

Three conventions matter:

- **Target bash 3.2**, the shell stock macOS ships. No associative arrays, no `mapfile`,
  no `${var,,}`, no `[[ -v ]]`. Under `set -u`, `"${arr[@]}"` and `${arr[0]}` on an empty
  array are unbound-variable errors on every bash before 4.4 — but `${#arr[@]}` is not,
  which is why it is the guard the bundled scripts use. Where an expansion cannot be
  guarded by a preceding `${#arr[@]}` check, use `${arr[@]+"${arr[@]}"}`.
- **The suite needs `timeout` or `gtimeout`** on PATH, since one of the scripts it tests
  requires it. Stock macOS has neither.
- **A known defect gets two cases**: one asserting the correct behavior, marked `skip` with
  the reason and the fix, and one pinning what the script does today. The skip keeps the
  finding visible in the report; the pin makes a fix trip the suite instead of passing
  silently.

Scripts whose whole body is a `gh` call are deliberately untested — the stub would assert
the stub. Cover logic, refusals, and parsing.

The per-skill rules in `validate-skills.sh` are tested too, in `tests/github/`.
`validate-skills.sh --skill <dir>` runs only those rules against one skill directory — no
marketplace, manifests, or README — which is what lets a case build a fixture skill in its
sandbox. A new per-skill rule gets a failing and a passing case there.

**The suite runs on both axes.** The `test-scripts` job is a matrix over `ubuntu-latest`
and `macos-latest`, so the bash 3.2 and BSD-userland targets above are verified rather
than merely conventional. Two details make the macOS leg real: it invokes
`/bin/bash tests/run.sh` explicitly, because Homebrew's bash 5 comes first on the
runner's PATH and plain `bash` would just duplicate the Linux leg; and it installs
`coreutils` first, because `CORE_TOOLS` links `timeout`/`gtimeout` only when one is
already present and stock macOS ships neither — without it the suite drops the tool
silently instead of failing. `fail-fast` is off so a failure on one OS still reports
the other.
