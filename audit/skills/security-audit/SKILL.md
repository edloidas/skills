---
name: security-audit
description: >
  Audit a repository for security risks — supply chain, CI, release, runtime, secrets,
  repository settings, and package-manager install-time controls for pnpm and bun. Reads and
  reports only; never mutates the repo or its GitHub settings. Aggregates findings from
  focused subagents across whichever areas the repo exposes.
when_to_use: >
  On "audit security", "check supply chain", "harden CI", "harden release", "audit rulesets",
  "audit install scripts", or "review for vulnerabilities". Also for SHA pinning,
  `pull_request_target`, npm provenance and trusted publishers, immutable releases,
  Dependabot, branch and tag protection, secret scanning, or lifecycle-script allowlists.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Agent
---

# Security Audit

## Purpose

**This skill reads and reports. It never writes.** No file edit, no `gh api` write, no
GitHub issue, no invocation of another skill on the user's behalf. It detects security gaps
across whichever areas a repository exposes, aggregates them into one severity-ordered
report, and hands off. Every `gh api` command it produces is report *text* for a human or a
downstream skill to run — the audit never executes one.

`maintain:repo-hardening` is the write half of the pair. It applies the baseline via
`gh api`: rulesets, Actions token defaults, security features, immutable releases,
branch-restricted environments for deploy secrets. Findings from this skill are its input;
run it after an audit, or standalone on a new repo. If the user wants changes made rather
than gaps listed, that is the skill to use.

A new audit area adds a checklist under `references/` and a prompt in
`references/subagent-prompts.md`, never a mutation — that is what keeps the skill safe to run
on a repo the user does not own.

**Audit areas currently implemented:**

| Area | Checklist |
|---|---|
| GitHub Actions workflows under `.github/workflows/` | `references/actions-checklist.md` |
| Release configuration (`release.yml`, `package.json`, `dependabot.yml`, npm publishing) | `references/release-checklist.md` |
| Repository settings via the GitHub REST API (Actions defaults, rulesets, security features, immutable releases, deploy environments) | `references/repo-settings-checklist.md` |
| Package manager and install-time controls, **pnpm and bun only** (lifecycle-script allowlists, release-age gates, scope→registry mapping) | `references/package-manager-checklist.md` |
| Application source code (injection and unsafe-execution vectors) | `references/code-security-checklist.md` |

**Not yet implemented:** non-GitHub CI providers (CircleCI, GitLab CI), container security
(Dockerfiles, base-image pinning), committed-secret scanning beyond GitHub's native
feature, runtime config (CSP, CORS, security headers), dependency policy (license
allowlist, banned packages).

For dependency CVE scanning specifically, use `gh dependabot alerts`, `npm audit`, or
`pnpm audit` directly — this skill does not duplicate that.

**Boundary with `audit:ci-audit`.** Both read `.github/workflows/`, split by consequence. This skill
owns the security surface: action pinning, `permissions:`, `persist-credentials`,
`pull_request_target`, OIDC, third-party action sources, and cache **poisoning** or cross-branch
scope. `ci-audit` owns performance, spend, and gating correctness — the job graph, cache **hit
rate**, matrix design, `timeout-minutes`, artifact retention, and `concurrency`. Action pinning is
graded here and only here, so the same line of YAML never gets two severities. When `ci-audit` finds
a required check name that no workflow produces, it hands the observation over, because reconciling
rulesets against triggers needs the `gh api` calls only this skill makes.

## When to Use

Trigger phrases: `security audit`, `supply chain`, `ci hardening`, `harden actions`, `audit release`, `harden settings`, `audit rulesets`, `audit install scripts`, `audit package manager`, `minimum release age`, `allowBuilds`, `staged publishing`, `pwn request`, `sha pinning`.

**Not for:**
- Applying the fixes → `maintain:repo-hardening`
- Bug hunting on a diff → `review:changes-review`; style and comment noise → `review:code-cleanup`
- CI speed/parallelization → `audit:ci-audit`
- Dependency CVE scanning → run `gh dependabot alerts` / `pnpm audit` directly

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Workflow

### Step 1: Detect Repo Layout

Run in parallel. Every command here is a read:

```bash
ls .github/workflows/ 2>/dev/null
cat .github/dependabot.yml 2>/dev/null
jq '{name, packageManager, trustedDependencies, scripts: (.scripts | keys), publishConfig, private}' package.json 2>/dev/null
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
cat pnpm-workspace.yaml 2>/dev/null
cat bunfig.toml 2>/dev/null
cat .npmrc 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions/workflow 2>/dev/null
gh api repos/<owner>/<repo>/rulesets 2>/dev/null
gh api repos/<owner>/<repo>/immutable-releases 2>/dev/null
gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis}' 2>/dev/null
```

Resolve `<owner>/<repo>` from `gh repo view --json nameWithOwner --jq .nameWithOwner`. If the API calls fail with `404` or auth errors, note it — repo-settings findings will be skipped for that area.

Compute the following in the orchestrator and substitute them into the dispatch prompts.

**Org-scope context, for Subagent D:**

- `org_prefix` — derived from `package.json` `name:`. If the name is `@<prefix>/<pkg>`, the prefix is `<prefix>`. If the name is unscoped, leave `org_prefix` empty (no org scopes will be flagged).
- `org_scope_patterns` — given a non-empty `org_prefix`, owned scopes are `@<prefix>/*` AND any scope matching `@<prefix>-*/*` (e.g., for `enonic`: `@enonic/*`, `@enonic-types/*`, `@enonic-cli/*`).
- `already_covered_scopes` — union of: `minimumReleaseAgeExclude` from `pnpm-workspace.yaml` (use `yq`), `minimumReleaseAgeExcludes` from `bunfig.toml`, `registries:` keys from `pnpm-workspace.yaml`, `[install.scopes]` keys from `bunfig.toml`, and `@<scope>:registry=` lines from `.npmrc`.

These pre-approve scopes the team has already decided to trust. Subagent D treats them as covered and emits no finding for missing config.

**Default posture: deny everything.** Subagent D flags missing exclude/registry config **only** for owned scopes (matching `org_scope_patterns`) that appear in the lockfile and are not in `already_covered_scopes`. All other scopes stay under the release-age and dependency-confusion gates — that is the intended hardening. If `org_prefix` is empty, no scope-specific findings are emitted.

**Release-target context, for Subagent B:**

- `release_publishes_to_npm` — `true` if any of these exist (the audit does not care WHICH non-npm publisher is used, only whether npm is involved): a `release.yml` / `release.yaml` in `.github/workflows/` containing a literal `npm publish`, `npm stage publish`, `pnpm publish`, `yarn publish`, or `bun publish`; a `publishConfig.registry` field in `package.json`; or a `scripts.publish` value containing any of those commands.
- `detected_build_systems` — assembled from root file presence: `npm` if `package.json` + any lockfile, `gradle` if `build.gradle`/`build.gradle.kts`, `maven` if `pom.xml`, `cargo` if `Cargo.toml`, `pip` if `requirements.txt`/`pyproject.toml`, `docker` if `Dockerfile`. `github-actions` is always added when `.github/workflows/` exists. This drives item 7 (dependabot ecosystem coverage) so the audit recommends the right ecosystems regardless of stack.

Close the step with one line: `Layout: pnpm 10.28, 5 workflows, release.yml present, gh api 200 — dispatching A, B, C, D; E skipped (config-only repo).`

**Routing.** Skip the Actions subagent if `.github/workflows/` is absent. Skip the Release subagent unless one of these holds: a `release.yml`/`release.yaml` exists, `package.json` has `publishConfig`, or `package.json` `scripts` has any of `publish`, `release`, `prepublishOnly`. If `package.json` is absent or `private: true`, note it — release findings about provenance change severity. Dispatch the Package Manager subagent if any lockfile exists — including `package-lock.json` or `yarn.lock`, where its whole job is the one out-of-scope finding (the audit supports pnpm and bun only) rather than a tuning pass. Dispatch the Repo Settings subagent if `gh api .../actions/permissions` returns HTTP 200; skip only on `404` or auth error. An empty `[]` from `/rulesets` is success — Subagent C treats the absence of rulesets as a finding, not a reason to skip. Skip the code subagent on a configuration-only or docs-only repo.

### Step 2: Dispatch Audit Subagents in Parallel

Read `references/subagent-prompts.md`. It holds one prompt per audit area, the placeholder
substitution table, and the rule that no subagent mutates anything.

Dispatch **one subagent per applicable audit area, concurrently** if the host allows it. If
the host has no subagent facility, run each area sequentially inline using the same prompts.
Substitute every placeholder before dispatch — `{{SKILL_DIR}}` in particular, since
subagents are spawned with the user's CWD and relative checklist paths will not otherwise
resolve.

As new audit areas are added under `references/`, add the matching prompt to that file. No
change to Step 3 or Step 4 is needed.

Close the step with one line: `Dispatched 4 of 5 auditors in parallel; awaiting A, B, C, D.`

### Step 3: Aggregate Findings

Wait for all dispatched subagents. Apply the four aggregation rules, then assemble the
report. Severities come from `references/severity-table.md` — use it to reconcile any
disagreement between subagents on the same finding shape.

**Aggregation rule 1 — Pin-status cross-check (A ↔ C).** Reconcile Subagent A's pin findings with Subagent C's `sha_pinning_required` report:

- A reports zero pin findings (every `uses:` is SHA-pinned) AND C reports `sha_pinning_required: false` → emit **high**: "All actions are SHA-pinned but `sha_pinning_required` is off. Enable to prevent regression: `gh api -X PUT /repos/<owner>/<repo>/actions/permissions -F sha_pinning_required=true`."
- A has pin findings AND C reports `sha_pinning_required: false` → do NOT additionally flag the setting. The issue is the unpinned actions (already in A's report). In `### Already hardened` add: "`sha_pinning_required` cannot be enabled until A's pin findings are fixed — re-run the audit afterward."
- C reports `sha_pinning_required: true` → "Already hardened: `sha_pinning_required` enforced."

**Aggregation rule 2 — Required-status-check coverage (A ↔ C).** For each `{ruleset_id, protected_branches, required_checks}` entry in C's `RULESET_REQUIRED_CHECKS` map, for each `required_check`, for each `protected_branch`:

- Find workflow(s) in A's `WORKFLOW_TRIGGER_MAP` whose `name:` matches `required_check`.
- If no workflow matches the name, OR none of the matching workflows trigger on `protected_branch` (check both `push_branches` and `pr_branches`; treat `*` as matching any branch), emit **high**: "Required check `<check>` on branch `<branch>` (ruleset `<id>`) is not produced by any workflow triggering on that branch. PRs to `<branch>` will be permanently BLOCKED. Either add the branch to the workflow's `on.push.branches` / `on.pull_request.branches`, or remove the check from the ruleset's `required_status_checks`."

**Aggregation rule 3 — Pass collation.** Each subagent's report ends with a "passes" / "already hardened" section. Concatenate these into `### Already hardened`, prefixed with the source subagent: `[Actions] persist-credentials: false on all checkouts`, `[Repo Settings] secret_scanning enabled`, `[Package Manager] minimumReleaseAge: 4320 with Strict: true`.

**Aggregation rule 3b — Not-checked collation.** Anything that did not run gets a line in `### Not checked`, never in `### Already hardened` — a skip listed among the passes reads as a pass. One line per item, with its reason: every one of the five areas skipped by Step 1 routing; a `gh api` `404` or auth failure that dropped repo settings; a subagent that returned nothing or errored; an item a subagent itself skipped and declared in its header (Subagent B's npm-publisher items when `release_publishes_to_npm` is false, Subagent D's items 2-8 on an unsupported manager); and any tool the detection needed but did not find (`gh`, `jq`, `yq`). Areas with nothing outstanding still appear here as `[<area>] Fully checked` only if you list them for all five — otherwise list only the gaps.

**Aggregation rule 4 — Sequencing hints.** If any finding pair has a "fix A before C is actionable" relationship (rule 1's second case is canonical; the rule-2 BLOCKED-PR finding depends on the ruleset existing at all; D's `allowBuilds` fix may break installs until paired with `strictDepBuilds`), surface the ordering in a final `### Sequencing` section: `1. Apply [Actions] findings → 2. Re-run audit → 3. Apply [Repo Settings] sha_pinning_required recommendation.` Render the section only if at least one relationship exists.

**Weighting.** `release.yml` is the privileged target — weight findings there above equivalent findings in ordinary CI.

Sort findings within each severity bin worst-first (most exploitable first; policy findings after CVE-rated findings of the same severity). Keep file:line / API-path references intact from each subagent's report.

Close the step with one line: `Aggregated 4 auditor reports: 19 raw findings -> 14 after cross-checks (1 critical, 5 high, 6 medium, 2 low), 6 passes, 3 not checked.`

**Report skeleton** — every heading below is rendered, `### Sequencing` only when rule 4 produced a relationship:

```markdown
## Security Audit Report

<one line: areas audited, areas not checked>

### Critical
### High
### Medium
### Low / Informational
### Already hardened
### Not checked
### Sequencing
```

A filled report:

```markdown
## Security Audit Report

Audited Actions, Release, Repo Settings, Package Manager. Code not checked (config-only repo).

### Critical
- **Deploy secrets reachable from any branch** — `[Repo Settings]` `CLOUDFLARE_API_TOKEN` is a
  repo-level secret and `.github/workflows/deploy.yml:14` references it under a bare `push:`.
  Any branch can exfiltrate production credentials. Move it to a branch-restricted `environment:`
  (checklist item 10 — create the environment first, delete the repo-level copy last).

### High
- **12 unpinned actions** — `[Actions]` `ci.yml:9,17,31`, `release.yml:12,20` use tags. Run
  `pinact run`; a moved tag is arbitrary code holding your token.
- **No tag ruleset on `refs/tags/v*`** — `[Repo Settings]` `release.yml` triggers on `v*` tags and
  nothing blocks `update` or `deletion`, so a tag can be re-pointed after review.
  `gh api -X POST /repos/<owner>/<repo>/rulesets --input tag-ruleset.json`
- **Release-age gate unset** — `[Package Manager]` (policy) `pnpm-workspace.yaml` has no
  `minimumReleaseAge`. Add `minimumReleaseAge: 4320` (minutes), `minimumReleaseAgeStrict: true`.

### Medium
- **`npm publish`, not `npm stage publish`** — `[Release]` `release.yml:41`. Staging is the one
  control a fully compromised CI job cannot forge. Requires npm >= 11.15.0.
- **No workflow linter in CI** — `[Actions]` nothing runs zizmor, so the above regresses silently.

### Low / Informational
- **`allowed_actions: "all"`** — `[Repo Settings]` common and appropriate for a public repo.

### Already hardened
- `[Actions]` `persist-credentials: false` on all six checkouts; workflow-level
  `permissions: contents: read` on every workflow
- `[Repo Settings]` secret scanning and push protection enabled
- `[Release]` credentialed publish job holds only auth, download, `publish --ignore-scripts`

### Not checked
- `[Code]` Skipped — configuration-only repository, no application source
- `[Repo Settings]` `immutable-releases` — `gh api` returned `404` on this plan; state unknown
- `[Release]` publisher-side npm settings (Trusted Publisher pinning, token-based publishing
  disallowed) — not API-auditable; confirm these on npmjs.com yourself

### Sequencing
1. Apply `[Actions]` pin findings -> 2. Re-run this audit -> 3. Enable `sha_pinning_required`.
```

### Step 4: Hand Off Findings

The audit stops here. Step 4 produces two artifacts side by side — a task queue for
downstream work, and a Planned Changes report for the user to read. Do not edit files, run
`gh api` writes, create issues, or invoke `/maintain:repo-hardening`,
`/build:fix-and-reverify`, `/plan:issue-flow`, or any other skill on the user's behalf.

Hosts differ in whether they have a task tracker; where none exists, the Planned Changes
report *is* the handoff and the options below collapse to option 4.

Ask, per **Asking the User**:

1. `Emit tasks + planned-changes report` (Recommended) — one task per finding, plus the report below
2. `Emit tasks flagged for issue filing` — same as 1, with `intended_action: file_issue` metadata
3. `Emit a single summary task` — one task summarising all findings, suitable for a single tracking issue
4. `Skip — just the report`

**All four options render the Planned Changes report** (so the user always sees the change plan and revert commands). Options 1–3 additionally emit tasks.

#### Task emission rules (options 1, 2, 3)

Skip this subsection entirely when the host has no task tracker.

- One task per finding from the Step 3 report (options 1, 2). For option 3, emit a single task whose description is a numbered list of all findings.
- `subject`: short finding title (e.g., "Pin `actions/checkout@v6` to SHA").
- `description`: severity (including any `(policy)` qualifier), source subagent (`[Actions]`, `[Release]`, `[Repo Settings]`, `[Package Manager]`, `[Code]`), file:line or API path, the exact remediation snippet from the report.
- `metadata`: minimum set — `severity`, `source_area`, `change_kind` (`code` for file edits / `server_state` for `gh api` writes), `intended_action` (`fix` / `file_issue` / `summary`). Keep metadata light — the task queue is a handoff, not the audit's persistence layer.
- **Sequencing**: for any pair from Step 3's `### Sequencing` section, record the downstream task as blocked by the upstream one, using whatever dependency field the host's tracker exposes. If it has none, state the ordering in the task description.
- Emit tasks worst-first within each severity, matching the report's order.

#### Planned Changes report

Render directly in the chat output, grouped by source area. It is the audit's plan-of-record,
not an execution transcript — phrasing matters. Use `Recommended command:` and
`Revert command:` (never `Applied:`), because the audit does not observe what actually runs.
Code edits get one line; server-state changes get three.

```markdown
## Security Audit — Planned Changes

Plan-of-record (not an execution transcript). Render of the Step 3 findings as code edits and `gh api` calls a downstream skill or human will apply.

### [Actions] (N planned changes)
- `.github/workflows/ci.yml` — pin 6 `uses:` lines via `pinact run`
- `.github/workflows/release.yml` — add workflow-level `permissions: contents: read`

### [Release] (N planned changes)
- (or: "No changes planned — audit area skipped per Step 1 routing")

### [Repo Settings] (N planned changes)
- Set `default_workflow_permissions: read` on <owner>/<repo>
  - Recommended command: `gh api -X PUT /repos/<owner>/<repo>/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false`
  - Revert command: `gh api -X PUT /repos/<owner>/<repo>/actions/permissions/workflow -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true`
- Enable immutable releases on <owner>/<repo>
  - Recommended command: `gh api -X PUT /repos/<owner>/<repo>/immutable-releases`
  - Revert command: `gh api -X DELETE /repos/<owner>/<repo>/immutable-releases`

### [Package Manager] (N planned changes)
- `pnpm-workspace.yaml` — add `minimumReleaseAge: 4320`, `minimumReleaseAgeStrict: true`

### Deferred or skipped (informational)
- [Actions] `pull_request_target` finding in `ci-fork.yml` — flagged as `informational`, no fix planned
- [Repo Settings] `sha_pinning_required` — depends on `[Actions]` pin changes per Step 3 sequencing
```

**Format rules:**
- Every area gets a section, even if empty, so the user can see which areas had nothing to apply or were skipped.
- Code edits are one line: file path + short description. No `Recommended command:` block — the edit content lives in the task description.
- Server-state changes are three lines: title, `Recommended command:`, `Revert command:`. Both are the literal `gh api` invocations from the Step 3 finding.
- A `### Deferred or skipped` section captures anything not fixed (informational items, sequencing-blocked items). Nothing is silently dropped.

#### Handoff line

After rendering the report and emitting tasks, print one of:

- Option 1: "N tasks emitted. Run `/maintain:repo-hardening` for the `gh api` changes, or `/build:fix-and-reverify` to walk through the file edits."
- Option 2: "N tasks emitted with `file_issue` flag. Run `/plan:issue-flow` per task when you're ready."
- Option 3: "Single summary task emitted. Run `/plan:issue-flow` to file it as a tracking issue."
- Option 4: "No tasks emitted; the report above is the full audit output."

Then stop. Do not invoke any of those skills yourself.

## References

| File | Contents |
|---|---|
| `references/subagent-prompts.md` | Dispatch prompt per audit area, plus the placeholder substitution table |
| `references/severity-table.md` | Severity per finding shape; the release-age gate's four units |
| `references/actions-checklist.md` | Detection, severity, and fix for each workflow check |
| `references/release-checklist.md` | Release trigger, provenance, staged publishing, artifact identity |
| `references/repo-settings-checklist.md` | Exact `gh api` detection and remediation commands, bypass-actor patterns |
| `references/package-manager-checklist.md` | Per-manager field names, units, defaults, and fix examples |
| `references/install-flags.md` | Frozen-lockfile and `--prod` flags per manager, multi-stage Docker |
| `references/code-security-checklist.md` | Injection and unsafe-execution vectors by stack |
