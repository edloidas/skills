# The check catalog

Four families. Each check says what to look for, what it costs when it is wrong, and the shape that
fixes it. Severity is about consequence, not about how odd the YAML looks.

Every example here is drawn from a real workflow, and where a repository gets it wrong that is said
plainly — a sophisticated pipeline with one gap is the normal case, not an outlier.

## A. Gating correctness

The most valuable family, because these fail **green**. A pipeline that runs fast and blocks nothing
is worse than a slow one.

### A1 — A matrix job with no stable fan-in gate

**Look for:** a job with `strategy.matrix` whose name is what branch protection requires.

Matrix legs bake their values into the check name (`Node.js Smoke Test (22.x, ubuntu-latest)`). Two
things follow, both bad. Change the matrix and every required check configured against the old names
is orphaned — the pull request waits forever on checks that will never report. And a leg that fails
leaves a plain `needs` dependent **skipped**, which branch protection treats as **passing**.

The fix is a single fan-in job with a stable name, required instead of the legs:

```yaml
node-smoke-gate:
  name: Node.js Smoke Test
  runs-on: ubuntu-latest
  needs: node-smoke
  # `always()` because a plain `needs` leaves this skipped when a leg fails,
  # and branch protection treats skipped as passing.
  if: always()
  steps:
    - name: Fail if any smoke leg failed
      if: contains(fromJSON('["failure", "cancelled"]'), needs.node-smoke.result)
      run: exit 1
```

**Severity:** high. Without `if: always()` the gate is decorative.

### A2 — A job that cannot fail the run

**Look for:** `continue-on-error: true` on a job that reads like a gate, a required check with no
`needs` path back to the work it validates, or an assertion step whose command cannot exit non-zero
(a bare `echo`, a pipe that swallows the status, a `|| true`).

**Severity:** high when the job is named as a gate, low when it is honestly advisory.

### A3 — Gating on a noisy signal

**Look for:** wall-clock benchmarks, flake-prone end-to-end suites, or coverage deltas wired as
blocking.

Wall clock on a shared runner is not a gate-quality signal — cross-process p50 variance runs ±5-10%
and averages ±43%. A benchmark job belongs outside every required path with `fail-on-alert: false`,
and the hard budget lives in a deterministic check instead: bundle size, a draw-count assertion, an
allocation count.

**Severity:** medium. The symptom is people re-running CI until it passes, which trains everyone to
ignore it.

### A4 — Required-check names that no workflow produces

Detect it, then **hand it to `security-audit`**, which reconciles rulesets against workflow triggers
and owns the fix. Report the observation, not a recommendation.

## B. The critical path

Wall clock is set by the longest dependency chain, not by the number of jobs.

### B1 — Independent steps serialized in one job

**Look for:** a single job running lint, typecheck, test and build in sequence.

Split only what is genuinely independent, and check first whether the toolchain already parallelizes
internally. A unified command — Vite+'s `vp check`, or a `check` script that fans out itself —
already does this, and splitting it adds a checkout, a setup and an install per job for nothing.

**Severity:** medium, and only when the serialized steps are actually independent.

### B2 — No cheap gate at the head of the graph

**Look for:** every job starting from `[]` with no shared first step.

One fast job that everything else `needs`, directly or transitively, means a commit failing lint
never pays for the expensive legs. The cascade is the point: a skipped head skips the run.

```yaml
check:   { runs-on: ubuntu-latest }             # lint, format, typecheck
build:   { needs: check }
test:    { needs: check }
```

**Severity:** medium. Pure spend, no correctness impact.

### B3 — Expensive jobs running on every event

**Look for:** a Playwright browser download, a full benchmark suite, or a cross-platform matrix
triggered on every push and pull request.

Restrict them to default-branch pushes plus `workflow_dispatch`, which also gives a feature branch a
way to run them deliberately before merge. The test is whether anything consumes the result: an
artifact that expires unread is pure cost.

```yaml
if: github.event_name == 'workflow_dispatch' || github.ref == 'refs/heads/master'
```

**Severity:** medium to high, scaled by the job's share of total minutes. A suite costing ~150s
against ~80s for every blocking job combined is worth moving.

### B4 — Re-doing setup instead of consuming an artifact

**Look for:** two jobs that both check out, set up a runtime, install dependencies and build the same
thing.

A downstream job that only needs build output should download the artifact and skip the install
entirely. The strongest version of this also improves what is tested: consuming the packed tarball
means the Windows leg exercises the Linux-packed bytes that actually ship, and a job testing the
published artifact needs neither a checkout nor a dependency install.

**Severity:** medium.

### B5 — Double runs on the same commit

**Look for:** `on: [push, pull_request]` with no guard.

A same-repo pull request produces both events for one commit, so everything runs twice. Skip the
pull-request event when the branch lives in the same repository — the push run already covered that
head commit — and keep fork pull requests, which produce no push event.

**Severity:** medium. It is close to half the bill on a busy repository.

## C. Caching

This family is about **hit rate**. Cache *poisoning* and cross-branch scope are `security-audit`'s.

### C1 — A key not derived from the lockfile

**Look for:** a `key:` with no `hashFiles`, or one hashing `package.json` rather than the lockfile.

`package.json` states ranges, so it does not change when a resolved dependency does. The key must
change exactly when the installed tree changes, and be scoped by OS:

```yaml
key: bun-${{ runner.os }}-${{ hashFiles('bun.lock') }}
restore-keys: |
  bun-${{ runner.os }}-
```

**Severity:** medium. A key that never changes serves a stale tree; one that always changes never hits.

### C2 — No `restore-keys`

Without a fallback prefix, a lockfile change means a cold install rather than a near-miss restore.
Cheap to add, and it is what makes the first build after a dependency bump tolerable.

**Severity:** low.

### C3 — A redundant or broken auto-cache

**Look for:** `cache: 'npm'` on `actions/setup-node` in a repository with no `package-lock.json`, or
an explicit `actions/cache` step duplicating what a setup action already does.

Setup actions fail or warn when the lockfile they key on is absent. Turn the auto-cache off
explicitly rather than leaving a broken step in place:

```yaml
- uses: actions/setup-node@<sha> # v5
  with:
    package-manager-cache: false
```

**Severity:** low, but it is noise every maintainer learns to ignore, which is its own cost.

### C4 — Caching what is cheaper to rebuild

**Look for:** a cache around a step that takes less time than the restore-and-save round trip, or a
cache of derived output that is invalidated by nearly every commit.

**Severity:** low.

## D. Spend and hygiene

### D1 — No `timeout-minutes`

**Look for:** any job without it. The default is **360 minutes**, so one hung step — a dev server
that never becomes ready, a prompt waiting on stdin — burns six hours of runner time before the
platform intervenes.

Set it per job at roughly twice the observed p95. This is the single most common gap: a pipeline can
be otherwise carefully built and still declare it on one job out of sixteen.

**Severity:** medium, and high on a self-hosted runner where the job also blocks a queue.

### D2 — Default artifact retention

**Look for:** `upload-artifact` with no `retention-days`. The default is 90 days.

An artifact that exists only to hand bytes to the next job in the same run needs `1`. A diagnostic
bundle someone might read after a failure needs about `7`. Reserve longer windows for artifacts that
are genuinely referenced later.

**Severity:** low individually, real in aggregate on a busy repository.

### D3 — Diagnostics uploaded unconditionally

**Look for:** logs, traces, screenshots or coverage uploaded with no condition.

Guard them with `if: failure()`. On a green run nobody opens them, and the upload costs time in the
critical path of every single build.

```yaml
- name: Upload e2e artifacts
  if: failure()
  uses: actions/upload-artifact@<sha> # v7
  with:
    name: e2e-artifacts
    path: |
      e2e/artifacts/
      dev-server.log
    retention-days: 7
```

**Severity:** low.

### D4 — No `concurrency` group

**Look for:** a workflow with no `concurrency:` block.

Without one, three pushes in a minute run three full pipelines and the first two are already
irrelevant. Key the group so that each branch or pull request is its own lane:

```yaml
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

**Severity:** medium.

### D5 — `cancel-in-progress: true` on irreversible work

**Look for:** it on a release, publish, or deploy workflow.

Cancelling mid-flight is not free when the work is not idempotent. A run interrupted between
`npm publish` and the GitHub Release step leaves a published version with no release, and the
cancelling run cannot republish it. These workflows want a serialized group that queues instead:

```yaml
concurrency:
  group: release
  cancel-in-progress: false
```

**Severity:** high. This is the check most worth having, because the damage only appears under a race
nobody tests for.

### D6 — Unnecessary full history

**Look for:** `fetch-depth: 0` where nothing reads history.

It is required for tag discovery, changelog generation, or a diff against the merge base, and
otherwise it just downloads the whole repository. Say which of those applies before recommending a
change.

**Severity:** low, rising with repository age.

### D7 — A fixed sleep waiting on a service

**Look for:** `sleep <n>` before a step that talks to a server the previous step started.

A fixed wait is either too short, and flakes, or too long, and taxes every run. Poll instead, and
dump the log when the wait expires so the failure is diagnosable:

```yaml
- name: Wait for dev server
  run: |
    for _ in $(seq 1 60); do
      curl -sSf http://localhost:3000 >/dev/null 2>&1 && exit 0
      sleep 1
    done
    cat dev-server.log || true
    exit 1
```

**Severity:** medium when it flakes, because a flaky gate gets ignored.
