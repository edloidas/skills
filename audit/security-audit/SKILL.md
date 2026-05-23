---
name: security-audit
description: Use when the user asks to audit a repository for security risks — supply-chain, CI, release, runtime, secrets, repository settings (rulesets, Actions defaults), or any combination. Aggregates findings from focused subagents across whichever audit areas the repo exposes. Trigger phrases include "audit security", "security audit", "check supply chain", "harden CI", "harden release", "harden settings", "audit rulesets", "review for vulnerabilities".
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Agent
---

# Security Audit

## Purpose

Audit a repository for security risks across whichever areas apply. The skill aggregates findings from focused subagents — one per audit area — and produces a single severity-ordered report.

The architecture is designed to grow. Adding a new audit area means writing a new checklist under `references/` and a new subagent prompt in Step 2 — no change to the aggregation, report, or fix flow.

**Currently implemented:**
- GitHub Actions workflows under `.github/workflows/` — see `references/actions-checklist.md`
- Release configuration (`release.yml`, `package.json`, `dependabot.yml`, npm publishing) — see `references/release-checklist.md`
- Repository settings exposed via the GitHub REST API (Actions defaults, branch and tag rulesets, secret scanning) — see `references/repo-settings-checklist.md`

**Planned (not yet implemented):**
- Non-GitHub CI providers (CircleCI, GitLab CI)
- Container security (Dockerfiles, base-image pinning, multi-stage hygiene)
- Committed-secret scanning beyond GitHub's native feature
- Runtime config (CSP, CORS, security headers in frameworks that ship them)
- Dependency policy (allowed-license check, banned-package list)

For dependency CVE scanning specifically, use `gh dependabot alerts`, `npm audit`, or `pnpm audit` directly — this skill does not duplicate that.

## When to Use

Use when the user asks to:
- "Audit security" / "security audit"
- "Check supply chain" / "review for supply-chain attacks"
- "Harden CI" or "harden actions"
- "Audit release workflow" / "audit npm publishing"
- "Harden settings" / "audit rulesets" / "audit repo settings"

Trigger phrases: `security audit`, `supply chain`, `ci hardening`, `harden actions`, `audit release`, `harden settings`, `audit rulesets`, `pwn request`, `sha pinning`.

**Not for:**
- Generic code review → `review:changes-review`
- CI speed/parallelization → `audit:ci-audit`
- Dependency CVE scanning → run `gh dependabot alerts` / `pnpm audit` directly

## Workflow

### Step 1: Detect Repo Layout

Run in parallel:

```bash
ls .github/workflows/ 2>/dev/null
cat .github/dependabot.yml 2>/dev/null
jq '{packageManager, scripts: (.scripts | keys), publishConfig, private}' package.json 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions/workflow 2>/dev/null
gh api repos/<owner>/<repo>/rulesets 2>/dev/null
gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis}' 2>/dev/null
```

Resolve `<owner>/<repo>` from `gh repo view --json nameWithOwner --jq .nameWithOwner`. If the API calls fail with `404` or auth errors, note it — repo-settings findings will be skipped for that area.

If `.github/workflows/` is absent, skip the Actions subagent. If `package.json` is absent or `private: true`, note it — release findings about provenance change severity. If the GitHub API calls succeed, dispatch the Repo Settings subagent.

### Step 2: Dispatch Audit Subagents in Parallel

Spawn **one subagent per applicable audit area, in a single message** so they run concurrently.

**Claude Code path:** use the `Agent` tool with `subagent_type: general-purpose`.

**Codex path:** use `spawn_agent` with `agent_type: explorer` (read-only repository inspection).

**Fallback:** if subagents are unavailable, run each audit area sequentially in the main agent using the same prompts.

Skip an area if the repo does not expose it (no `.github/workflows/` → skip Actions subagent; no publish config → skip Release subagent). As new audit areas are added under `references/`, add the corresponding subagent dispatch here.

**Before dispatching, replace `{{SKILL_DIR}}` in each prompt template below with the absolute path to this skill's directory (the directory containing the SKILL.md you are following).** Subagents are spawned with the user's CWD, not the skill's, so relative paths to checklists will not resolve.

#### Subagent A — GitHub Actions auditor

Read `references/actions-checklist.md` for the full criteria. Prompt template:

```
You are auditing GitHub Actions workflows for supply-chain hardening.

Read every file under `.github/workflows/`. For each, evaluate:

1. SHA pinning — every `uses:` must be a 40-char commit SHA with version comment.
2. Workflow-level `permissions:` — must be explicit, default to `contents: read`.
3. `actions/checkout` — must set `persist-credentials: false` unless the workflow performs `git push`.
4. `pull_request_target` — flag every use. Critical if it checks out or executes PR-supplied code; safe otherwise.
5. `actions/cache` keys — must include `${{ github.sha }}` or `hashFiles(...)` for entropy.
6. `id-token: write` (OIDC) — restrict to publish/deploy workflows only.
7. Third-party action sources — list non-first-party actions.

Read the full checklist at `{{SKILL_DIR}}/references/actions-checklist.md`.

Report findings as a bullet list, grouped by severity (critical | high | medium | low | informational). For each finding: file:line — description — recommended fix. Include a "passes" section listing what is already hardened. Do not edit files.
```

#### Subagent B — Release auditor

Read `references/release-checklist.md` and `references/install-flags.md`. Prompt template:

```
You are auditing release configuration for supply-chain hardening.

Read `.github/workflows/release.yml` (or equivalent), `package.json`, `.github/dependabot.yml`, and any publishing scripts. Evaluate:

1. Release trigger scope — only `tags: ['v*']` or `workflow_dispatch`, never `push: branches`.
2. Tag/commit precheck — workflow verifies the tagged commit is reachable from a trusted branch.
3. Frozen lockfile — `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`, `bun install --frozen-lockfile`.
4. `--prod` flag — only in runtime-artifact contexts (Docker runtime layer, deployable tarball). Not in build/test/publish steps.
5. npm provenance — for public packages, Trusted Publishers (OIDC) and `--provenance` or pnpm OIDC.
6. Token usage — secrets or OIDC only. No hardcoded tokens, no workflow_dispatch input tokens.
7. `dependabot.yml` — must include `package-ecosystem: "github-actions"`.

Read the full checklists at:
- `{{SKILL_DIR}}/references/release-checklist.md`
- `{{SKILL_DIR}}/references/install-flags.md`

Report findings grouped by severity, same format as the Actions audit. Do not edit files.
```

#### Subagent C — Repo Settings auditor

Read `references/repo-settings-checklist.md`. Prompt template:

```
You are auditing GitHub repository settings for supply-chain hardening. Findings here are API-driven; fixes are `gh api` calls, not file edits.

Resolve `<owner>/<repo>` via `gh repo view --json nameWithOwner --jq .nameWithOwner` and call the GitHub REST API to evaluate:

1. Default `GITHUB_TOKEN` permissions — `default_workflow_permissions` must be `read`, `can_approve_pull_request_reviews` must be `false`.
2. `sha_pinning_required` — must be `true`, but ONLY after every workflow's `uses:` line is SHA-pinned (cross-check with the Actions audit). Enabling early breaks all workflow runs.
3. `allowed_actions` — informational. `"all"` is common; `"selected"` is appropriate for high-security repos.
4. Branch protection rulesets — the default branch and every active release-source branch (e.g., `x.y` version branches) must be covered by rules for `deletion`, `non_fast_forward`, `required_status_checks`, and ideally `required_linear_history`.
5. PR approval rule — `required_approving_review_count >= 1` for multi-contributor repos. Flag the Dependabot interaction (see ruleset-splitting pattern in the checklist).
6. Tag protection rulesets — if the release workflow triggers on `v*` tags, there MUST be a tag ruleset blocking `creation`, `update`, and `deletion` on `refs/tags/v*`, with bypass limited to Admins.
7. Secret scanning + push protection — enabled where the plan supports it.
8. Bypass actor patterns — flag every `bypass_mode: always` actor and warn that bypass is all-or-nothing per ruleset.

Read the full checklist at `{{SKILL_DIR}}/references/repo-settings-checklist.md` — it contains the exact `gh api` commands for both detection and remediation, plus well-known actor IDs (Dependabot Integration = 29110, Admin RepositoryRole = 5) and the ruleset-splitting pattern for granular bypass.

Report findings grouped by severity, same format as the Actions audit. For each finding, include the exact `gh api` remediation command. Do not execute any commands.
```

### Step 3: Aggregate Findings

Wait for all dispatched subagents. Merge into a single report:

```markdown
## Security Audit Report

### Critical
- ...

### High
- ...

### Medium
- ...

### Low / Informational
- ...

### Already hardened
- ...
```

Order by severity. Keep file:line references intact. The "Already hardened" section is important — it tells the user what is already good and prevents over-prescribing.

### Step 4: Offer Fix Approach

Do not auto-apply. When `AskUserQuestion` is available, use it. Otherwise present the same options in normal chat as a numbered list and wait for the user's reply:

1. `Apply fixes now` (Recommended) — work through findings interactively
2. `Open one issue per finding` — invoke `plan:issue-flow` per finding
3. `Open a single tracking issue` — bundle into one issue
4. `Skip — just the report`

If the user picks Apply Now and SHA-pinning is in the findings, prefer `pinact run` over manual edits.

## Quick Reference

| Finding | Severity | Fix |
|---|---|---|
| `uses: foo/bar@v1` (floating tag) | high | `pinact run` |
| Workflow without `permissions:` | medium | Add `permissions: contents: read` at workflow level |
| `actions/checkout` without `persist-credentials: false` (no `git push`) | medium | Add `with: persist-credentials: false` |
| `pull_request_target` + checkout of PR ref | critical | Split trusted/untrusted parts; remove PR checkout |
| `pull_request_target` without checkout | informational | Document as intentionally safe |
| `npm install` in release workflow | high | Replace with `npm ci` |
| Public package without provenance | medium | Enable Trusted Publishers (OIDC) |
| Missing `dependabot.yml` github-actions entry | medium | Add `package-ecosystem: "github-actions"` |
| `default_workflow_permissions: "write"` | high | `gh api -X PUT .../actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false` |
| `sha_pinning_required: false` (after files pinned) | high | `gh api -X PUT .../actions/permissions -F sha_pinning_required=true` |
| Release-source branch without protection ruleset | high | Create/extend branch ruleset (see `repo-settings-checklist.md` item 4) |
| No tag ruleset on `refs/tags/v*` | high | Create tag ruleset blocking `creation`/`update`/`deletion` |
| `required_approving_review_count: 0` (multi-contributor repo) | medium | Add `pull_request` rule with count `1`; split ruleset for Dependabot bypass |
| Secret scanning disabled (plan supports it) | medium | `gh api -X PATCH .../<repo>` with `security_and_analysis.secret_scanning.status: enabled` |
| Cache key without `github.sha` / `hashFiles` | medium | Add high-entropy component |
| Release triggers on `push: branches` | critical | Switch to `tags: ['v*']` |

## Install Flag Cheatsheet

| Manager | Frozen lockfile | Skip devDeps (runtime only) |
|---|---|---|
| npm | `npm ci` | `npm ci --omit=dev` |
| pnpm | `pnpm install --frozen-lockfile` | `pnpm install --prod --frozen-lockfile` |
| yarn 1 | `yarn install --frozen-lockfile` | `yarn install --production --frozen-lockfile` |
| yarn 2+ | `yarn install --immutable` | `NODE_ENV=production yarn install --immutable` |
| bun | `bun install --frozen-lockfile` | `bun install --production --frozen-lockfile` |

`--prod` rule of thumb: production Docker runtime layer or deployable bundle, yes. Build/test/lint/publish, no — they need devDependencies. Full guide in `references/install-flags.md`.

## Common Mistakes

- **Auditing CI harder than release.** `release.yml` is the privileged target; weight findings there higher.
- **Flagging safe `pull_request_target`.** Only critical when it checks out or executes PR code.
- **Recommending `--prod` for build steps.** Will break — build needs dev tooling.
- **Forgetting `--frozen-lockfile` next to `--prod`.** Both belong in runtime install commands.
- **Treating cache scope as a separate cache per workflow.** Cache scope is per-repo; one workflow can poison another's restore.
- **Enabling `sha_pinning_required` before files are pinned.** Breaks every workflow run. Always sequence Actions audit fixes first, then flip the setting.
- **Assuming `bypass_mode: always` is per-rule.** It is per-ruleset. For granular bypass (e.g., Dependabot bypasses approval but not status checks), split the rules across separate rulesets.

## Keywords

security audit, supply chain, github actions, sha pinning, pinact, persist-credentials, pull_request_target, pwn request, release security, npm provenance, oidc, trusted publishers, frozen lockfile, npm ci, prod flag, devDependencies, dependabot, harden ci, cache poisoning, branch protection, tag protection, rulesets, bypass actors, sha_pinning_required, default_workflow_permissions, secret scanning
