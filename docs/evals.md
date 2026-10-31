# Skill Evals

Read this when changing a skill's discovery text, its tier, or `/do`'s routing table, or when a
decision about skills is waiting for "numbers, not intuition".

`tools/skill-eval/` measures skills by running them. It is a repo-only skill, surfaced to Claude
Code through `.claude/skills/skill-eval` like `skills-release`, and never published. The
validators check what a skill says; `tests/run.sh` checks what its scripts return; this checks
which skill a real session picks for a real request.

## Running

```bash
bash tools/skill-eval/scripts/run-suite.sh routing --runs 3 --jobs 4
bash tools/skill-eval/scripts/run-suite.sh ambient --runs 3 --jobs 4
bash tools/skill-eval/scripts/run-suite.sh routing --runs 1 --case routing-explain
```

Each run is a real model call on your credential, about $0.10–0.40 with Opus; the 48 cases (32
routing, 16 ambient) at 3 runs cost roughly $25. Output goes to
`tools/skill-eval/results/<timestamp>-<suite>/` (gitignored): `aggregate-result.json` and
`report.html` from the harness, `traces/<case>/<run>.jsonl`, and `summary.md`. `--model` overrides
the model; `--out` the directory; `--max-cost-usd` aborts the suite at that spend. Exit status is the
harness's: 0 every case at 100%, 1 below, 2 partial.

## How it works

It builds on `claude plugin eval` (Claude Code 2.1.269+, reference:
<https://code.claude.com/docs/en/plugin-evals.md>) rather than driving `claude -p` itself. The
harness already gives each run an empty temp workspace with a fresh `HOME` and config, so the
user's own plugins, skills, `CLAUDE.md` and memory are absent and only the plugin under test
loads. That matters here: a plain `claude -p --plugin-dir .` on a machine with the v5 group
plugins installed loads both `edloidas:explain` and `assist:explain`, and the measurement is
meaningless. It also supplies repeated runs, deterministic graders, cost reporting and a JSON
result. `run-suite.sh` adds what it lacks: it fixes the flags, copies each run's trace out of the
sealed temp directory (`collect-traces.sh`), and writes the summary (`summarize.sh`).

Fixed flags: the plugin is the repo root, cases come from `tools/skill-eval/cases`, the suite is a
tag, one arm only (`--ablation none` — a no-plugin baseline cannot load the skills being graded),
`--scaffold` so each case's `setup.sh` builds the fixture, `--disallow-tools Agent` so a route
cannot fan out into subagents, and `--keep-temp` so traces survive long enough to collect.

Principles the cases follow:

- **The prompt is an organic request.** No case prompt or fixture file mentions evals, tests,
  graders or the expected skill. The one leak is the harness's own workspace path,
  `/tmp/claude-eval-*/home/cwd`, which the run can see.
- **Grade what the run did, never what it says.** Graders are `tool_used` on the `Skill` tool's
  input, or `regex` over the trace. `summarize.sh` reads the same trace: the Skill calls, the
  `Route:` line `/do` printed, the playbook it opened. A run that writes "I used explain" without a
  Skill call loaded nothing.
- **A fixture, not the repo.** `fixtures/tally` is a three-file shell project committed into a
  fresh git repo per run. Variants build on it: `setup-conflict.sh` leaves a rebase stopped on a
  conflict, `setup-issue.sh` adds an issue's text as a file, `setup-dirty.sh` a staged change,
  `setup-branch.sh` an unpushed feature branch, `setup-tests.sh` a weak test file. Cases allow
  only `Read`, `Glob`, `Grep`, `Skill`, so a run can route but cannot edit, run git, or reach
  GitHub.
- **One run is noise.** Default is 3 runs per case; read the pass rate, not one verdict.
- **The environment is recorded.** The summary names the Claude Code version, the model read from
  each trace's init event, runs per case, and cost.

## Suites

| Suite | Prompt shape | Measures |
| ----- | ------------ | -------- |
| `routing` | `/edloidas:do <request>` | The first route `/do` takes: the skill it loads, or the playbook or in-session route it prints |
| `ambient` | The request alone | Whether an `auto` skill fires on its own, and where a request for a `routed` skill ends up — through `do`, directly, or nowhere |
| `live` | `/edloidas:<skill> <request>` | Whether a skill that changes things works end to end: the `do` playbooks, `solve-issue` offline, `live-probe write-runbook`, `reflect`, `orchestrate`'s preflight, `sharpen` |

`live` is not run by `run-suite.sh`: its cases edit and run code, so they need Edit, Write and Bash
granted, and its fixture is `fixtures/ledger` (a small Node.js project with seeded defects, built by
`fixtures/setup-ledger.sh <variant>`). Run it directly, with a cost ceiling:

```bash
claude plugin eval . --eval-dir tools/skill-eval/cases --tag live --runs 1 --ablation none \
  --scaffold --trust-plugin --no-publish --keep-temp --disallow-tools Agent \
  --allow-tools Edit Write Bash --max-cost-usd 15 --output-dir <out>
```

Bash runs inside the harness's OS sandbox (writes confined to the workspace, no network), and
`gh` is unauthenticated. The harness has no script grader, so behaviour — the bug fixed, the
output unchanged, the tree left clean — is checked afterwards on each kept workspace
(`<kept>/sealed/home/cwd`) with `cases/live/check.sh <case> <workspace>`, before
`collect-traces.sh` deletes it. A live run costs $0.20–0.60 with Opus.

The sandbox needs nested unprivileged user namespaces. Where AppArmor restricts them (Ubuntu
24.04+, `kernel.apparmor_restrict_unprivileged_userns=1`), every Bash call in a run fails with
`apply-seccomp: write /proc/self/setgroups … Permission denied`, and the suite then measures only
how the skills behave without a shell. Check one trace for that line before reading the results.

Cases cap `max_turns` at 6: the route is decided in the first few turns, and the rest of the run is
cost. A run that reaches the cap is graded like any other; the summary marks it `at turn cap`, not
as an error.

## Reading the summary

```markdown
| routing-issue-writer | /edloidas:do write this up as an issue for later: count.sh ignores stdin | issue-writer | 0/1 | 1: skill: issue-flow |
```

`Pass` is passing runs over runs, with errors and turn-cap stops counted beside it. `Observed per
run` is the trace: `route:` is the text after `/do`'s `Route:` line, `skill:` every Skill call in
order, `read:` a `do` playbook it opened. `no skill, no route` means nothing fired. The **Failed
graders** section gives each failing grader's explanation.

A failing case is one of three things, and the traces say which: a **routing or description
defect** (the skill text sent the request elsewhere — report it, do not patch the case), a **case
defect** (the grader or prompt is wrong), or **noise** (passes in other runs). Fix a case defect in
the case; route a skill defect to whoever owns the skill.

Baselines worth keeping go in `tools/skill-eval/reports/<date>-<suite>.md`, the summary as
generated plus a note for anything re-run. Compare a change against the latest baseline at the
same run count and model.

## Tests

`collect-traces.sh`, `summarize.sh` and `run-suite.sh` are tested in `tests/tools/skill-eval/`
on hand-built results and traces in the harness's shape, with `claude` stubbed. No test calls a
model.
