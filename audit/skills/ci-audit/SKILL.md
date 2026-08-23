---
name: ci-audit
description: >
  Audit GitHub Actions workflows for the things that cost wall clock, cost money, or let a pipeline
  pass without checking anything. Builds the job graph, then runs a catalog covering gating
  correctness (matrix jobs whose failures read as passing, gates that cannot fail), the critical path
  (serialized independent work, expensive jobs on every event, duplicated setup, double runs),
  caching effectiveness (key derivation, restore-keys, redundant auto-caches), and spend (missing
  timeouts, artifact retention, concurrency groups, cancel-in-progress on irreversible releases).
  Reads and reports only; never edits a workflow. Use when the user asks to audit or review CI, speed
  up a pipeline, cut Actions minutes, parallelize jobs, fix caching, or work out why a check is not
  blocking what it should.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(yq:*) Bash(gh:*) Bash(ls:*) Read Glob Grep
---

# CI Audit (GitHub Actions)

Audit the workflows in `.github/workflows/` for wall clock, spend, and whether the gating actually
gates. This skill **reads and reports**; it never edits a workflow.

Scoped to GitHub Actions deliberately. The checks below are about Actions' own semantics — skipped
results counting as passing, matrix legs in check names, `concurrency` groups, artifact retention —
and none of it transfers to another CI system. On a repository with no `.github/workflows/`, say so
and stop rather than guessing at a Jenkinsfile or a `.gitlab-ci.yml`.

## What this owns, and what it does not

`security-audit` has its own GitHub Actions auditor and the two overlap on the same files. The split
is by **consequence**, and it is stated in both skills:

| This skill | `security-audit` |
| ---------- | ---------------- |
| Performance, spend, and gating correctness | The security surface |
| Cache **hit rate** — key derivation, fallbacks | Cache **poisoning** and cross-branch scope |
| Whether a required check can fail the run | Whether a workflow can be made to run attacker code |
| Job graph, matrix design, artifact flow | `permissions:`, `persist-credentials`, `pull_request_target`, OIDC |
| — | Action pinning: SHA vs tag vs branch, with severities |

Two consequences worth stating plainly. **Do not report action pinning** — it looks like a
maintenance finding and is a supply-chain one, `security-audit` grades it, and duplicating it here
produces two different severities for one line of YAML. And when a required check name matches no
workflow, report the observation and hand it over: reconciling rulesets against triggers needs the
`gh api` calls that skill already makes.

## When to use

- "Audit my CI", "review the workflows", "why is CI slow"
- "Cut our Actions minutes", "parallelize the pipeline"
- "Fix caching in CI", "the cache never hits"
- "Why did that merge when the tests failed" — gating correctness, family A

Trigger phrases: `ci audit`, `github actions`, `workflow performance`, `actions minutes`, `ci slow`,
`parallelize ci`, `ci caching`, `required check`.

## Phase 1: Inventory

Glob `.github/workflows/*.yml` and `.github/workflows/*.yaml`. An empty result — the directory is
missing, or holds no YAML — means print `No GitHub Actions workflows found.` and stop.

Use globbing rather than shelling out. `fd` is not guaranteed present, and it exits non-zero with
`Search path is not a directory` when `.github/workflows/` is absent, so a bare `fd` returns an error
where the stop condition expects an empty result. Where a shell is preferred anyway, guard it:

```bash
[ -d .github/workflows ] && ls .github/workflows/*.y*ml 2>/dev/null
```

For each workflow, extract the shape before reading any step. The job graph is what most findings are
about, and it is not legible by reading top to bottom:

```bash
yq -r '.jobs | to_entries | map(.key + " <- " + ((.value.needs // []) | tostring)) | .[]' <file>
yq -r '[.on | keys | join(",")] | join("")' <file>
yq -r '.concurrency // "none"' <file>
```

Record per workflow: triggers, the `concurrency` block, the `needs` graph, which jobs carry a
`strategy.matrix`, which have `timeout-minutes`, and which upload or download artifacts.

Then state the **critical path** — the longest chain through the graph — because that is the number
any parallelization finding has to move. Splitting a job that is not on it changes nothing.

Where the run history is available, get real numbers rather than guessing which job is slow:

```bash
gh run list --workflow <file> --limit 20 --json databaseId,conclusion,createdAt,updatedAt
gh run view <id> --json jobs --jq '.jobs[] | "\(.name) \(.startedAt) \(.completedAt) \(.conclusion)"'
```

Say whether timings are measured or estimated. An estimated saving stated as a measured one is the
fastest way to lose an audit's credibility.

## Phase 2: Run the catalog

Read `references/checks.md` and work the four families. Each check there carries what to look for,
the cost when it is wrong, and the shape that fixes it.

| Family | Covers |
| ------ | ------ |
| **A. Gating correctness** | Matrix jobs with no stable fan-in gate, jobs that cannot fail the run, gates on noisy signals, required names nothing produces |
| **B. Critical path** | Serialized independent steps, no cheap head gate, expensive jobs on every event, setup repeated instead of artifacts consumed, push and pull-request double runs |
| **C. Caching** | Keys not derived from the lockfile, missing `restore-keys`, redundant or broken auto-caches, caching what is cheaper to rebuild |
| **D. Spend and hygiene** | Missing `timeout-minutes`, default artifact retention, diagnostics uploaded unconditionally, no `concurrency` group, `cancel-in-progress` on irreversible work, needless full history, fixed sleeps |

**Family A first.** A pipeline that is fast and gates nothing is worse than a slow one, and these
findings fail green — nobody notices them from the run list.

Two rules on severity:

- **Rate by consequence, not by how odd the YAML looks.** A missing `timeout-minutes` on a job that
  reliably finishes in 40 seconds is a low finding; the same gap on a job that can hang on a dev
  server is the one that burns six hours.
- **A finding needs the number it moves.** "Split these jobs" is not a finding. "These three steps
  are independent and sit on the critical path; splitting them removes ~90s from every run" is.
  Where the number cannot be established, say it is an estimate.

Recognise what is already right. A workflow doing the non-obvious things well — a fan-in gate with
`if: always()`, `cancel-in-progress: false` on the release, an unprivileged job producing the
artifact a privileged one consumes — should be told so, in one line each. It is how the report earns
the right to be believed about the rest.

## Phase 3: Report

```
## CI audit: <N> workflows, <J> jobs · critical path <T> (measured|estimated)

### Gating correctness
<finding: what is wrong, what it lets through, the shape that fixes it>

### Critical path
<finding, with the time it moves>

### Caching
<finding>

### Spend and hygiene
<finding>

### Already right
- <one line per non-obvious thing the workflows get right>

### Handed to security-audit
- <required-check reconciliation, or anything touching the security surface>
```

Drop any section with no findings. Do not pad a clean result — a workflow set with nothing wrong is a
real outcome, and `Already right` carries it.

`references/ci-template.yaml` is an optimized pnpm workflow with parallel jobs, path filters and
concurrency control; `references/ci-template-vp.yaml` is the Vite+ (`voidzero-dev/setup-vp`) variant.
Offer them when a repository is starting from nothing, not as a target to converge every pipeline on.

## Rules

- **Read and report. Never edit a workflow.** Findings are for the maintainer to apply.
- **Gating correctness before speed.** A faster pipeline that checks less is a regression.
- **No finding without a consequence.** Name what it costs or what it lets through.
- **Measured or estimated, always stated.** Never present an estimate as a measurement.
- **Stay off the security surface.** Pinning, `permissions:`, and trigger safety belong to
  `security-audit`. Report the boundary crossing, not the verdict.
- **Do not recommend splitting a unified check command** without establishing that the toolchain does
  not already parallelize internally.

## Error handling

| Situation | Action |
| --------- | ------ |
| No `.github/workflows/` | Print `No GitHub Actions workflows found.` and stop |
| `.github/workflows/` exists but holds no YAML | Same message. A directory with only a README is not a pipeline |
| Workflows exist but only `workflow_dispatch` | Audit them, and say nothing runs automatically |
| A workflow fails to parse | Report the parse error as the first finding and audit the rest |
| `yq` unavailable | Read the YAML directly, and say the job graph was derived by reading |
| `gh` unavailable or no run history | Audit statically, and mark every timing an estimate |
| A reusable workflow (`uses:` at job level) | Audit the caller's graph; say the callee was not read unless it is in this repository |
| A composite action in the repository | Read it — its steps are on the critical path too |
| Only one job, doing everything | Still audit families A, C and D. A single job is not automatically wrong |
