---
name: skill-eval
description: >
  Measure how this collection's skills behave by running them: sends realistic requests to a
  sandboxed Claude Code session with the edloidas plugin loaded, and reports per case which
  skill fired, which route /do took, and the pass rate over repeated runs.
when_to_use: >
  Before and after changing a skill's description, tier, or /do's routing table; on "run the
  skill evals", "does /do still route X", "measure skill triggering".
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read
disable-model-invocation: true
metadata:
  author: edloidas
  tier: manual
---

# Skill Eval

Runs the suites under `cases/` through `claude plugin eval` and writes a Markdown summary. Every
run is a real model call on the user's credential: about $0.15–0.60 a run with Opus. How the
harness, the cases and the grading work is in `docs/evals.md`; this file is the procedure.

**Mutation class:** writes only under `tools/skill-eval/results/` (gitignored), plus
`tools/skill-eval/reports/` when the user asks to record a baseline. Runs execute in the
harness's own temp workspace with read-only tools and no subagents; nothing reaches the real repo
or GitHub.

## Step 1: Pick the scope

| Request | Suite | Runs |
| ------- | ----- | ---- |
| A `/do` routing-table or routed-skill change | `routing` | 3 |
| An auto skill's description or `when_to_use` | `ambient` | 3 |
| A tier change, or "run everything" | both | 3 |
| One case named, or checking a case just written | that case, `--case <name>` | 1 |

Say the run count and the rough cost — cases × runs × $0.30 — in one line before starting, and
start without waiting unless the total passes 40 runs; past that, ask first.

## Step 2: Run

```bash
bash tools/skill-eval/scripts/run-suite.sh <suite> --runs <n> --jobs 4
```

It takes a few minutes; run it in the background and wait. Exit 1 means at least one case scored
below 100% — the summary is still written. Exit 2 means a partial run (auth or cost ceiling); say
so. A `--case` value is one exact name or a `*` glob, not a bracket set.

End Step 2 with one line: `Ran <suite>: <cases> cases × <runs> runs, $<cost>, exit <n>.`

## Step 3: Read and report

Read `<out>/summary.md` and, for every case below 100%, open its traces in
`<out>/traces/<case>/` to see what the run did instead. Report:

- the summary table, pasted unedited
- per failing case, one line: expected, observed, and whether it is a **routing or description
  defect** (the skill text sent the request elsewhere), a **case defect** (the grader or the
  prompt is wrong), or **noise** (passes in other runs of the same case)

```markdown
| routing-issue-writer | /edloidas:do write this up as an issue for later: count.sh ignores stdin | issue-writer | 1/3 | 1: skill: issue-flow<br>2: route: issue-writer · skill: issue-writer<br>3: skill: issue-flow |

- routing-issue-writer: expected issue-writer, observed issue-flow in 2 of 3 — routing defect:
  "write this up as an issue" matches both the draft row and the file-an-issue lifecycle row.
```

Then stop. Do not edit a skill, a case, or a grader to make a case pass; a defect is reported for
the user to route.

## Adding a case

A case is `cases/<suite>/<name>/case.yaml` plus a `setup.sh` symlink to `../../../fixtures/setup.sh`
(or `setup-conflict.sh`). Write the prompt as the user would type it; the candidate sees the
prompt and the `tally` fixture, so neither may mention evals, tests, graders or expected skills.
Grade only from what the run did — a `tool_used` grader on `Skill` with
`input_match: '"skill"\s*:\s*"edloidas:(?:<name>)"'`, or a `regex` grader on `target: trace` —
never an `llm` grader on the final text. Run the new case once with `--case <name> --runs 1`.
