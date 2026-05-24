---
name: security-audit
description: Use when the user asks to audit a repository for security risks — supply-chain, CI, release, runtime, secrets, repository settings (rulesets, Actions defaults), package manager and install-time controls (pnpm/bun lifecycle scripts, release-age gating, dependency confusion), or any combination. Aggregates findings from focused subagents across whichever audit areas the repo exposes. Trigger phrases include "audit security", "security audit", "check supply chain", "harden CI", "harden release", "harden settings", "audit rulesets", "audit install scripts", "audit lifecycle scripts", "audit package manager", "review for vulnerabilities".
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
- Package manager and install-time supply-chain controls (pnpm/bun lifecycle scripts, `minimumReleaseAge`, scope→registry mapping) — see `references/package-manager-checklist.md`

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
- "Audit install scripts" / "audit lifecycle scripts" / "audit package manager"

Trigger phrases: `security audit`, `supply chain`, `ci hardening`, `harden actions`, `audit release`, `harden settings`, `audit rulesets`, `audit install scripts`, `audit package manager`, `minimum release age`, `allowBuilds`, `trustedDependencies`, `pwn request`, `sha pinning`.

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
jq '{packageManager, trustedDependencies, scripts: (.scripts | keys), publishConfig, private}' package.json 2>/dev/null
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
cat pnpm-workspace.yaml 2>/dev/null
cat bunfig.toml 2>/dev/null
cat .npmrc 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions 2>/dev/null
gh api repos/<owner>/<repo>/actions/permissions/workflow 2>/dev/null
gh api repos/<owner>/<repo>/rulesets 2>/dev/null
gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis}' 2>/dev/null
```

Resolve `<owner>/<repo>` from `gh repo view --json nameWithOwner --jq .nameWithOwner`. If the API calls fail with `404` or auth errors, note it — repo-settings findings will be skipped for that area.

If `.github/workflows/` is absent, skip the Actions subagent. If `package.json` is absent or `private: true`, note it — release findings about provenance change severity. If any of `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, or `bun.lockb` exists, dispatch the Package Manager subagent. If the GitHub API calls succeed, dispatch the Repo Settings subagent.

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
9. Required status check coverage — for every branch covered by a branch ruleset, the required status checks named in `required_status_checks` MUST be produced by workflows whose trigger filters actually include that branch. Cross-reference ruleset condition `ref_name.include` against each workflow's `on.pull_request.branches` / `on.push.branches`. Mismatches put every PR to that branch into permanent `BLOCKED` state.

Read the full checklist at `{{SKILL_DIR}}/references/repo-settings-checklist.md` — it contains the exact `gh api` commands for both detection and remediation, plus well-known actor IDs (Dependabot Integration = 29110, Admin RepositoryRole = 5) and the ruleset-splitting pattern for granular bypass.

Report findings grouped by severity, same format as the Actions audit. For each finding, include the exact `gh api` remediation command. Do not execute any commands.
```

#### Subagent D — Package Manager auditor

Read `references/package-manager-checklist.md`. Prompt template:

```
You are auditing Node.js package-manager configuration for install-time supply-chain hardening. The two managers that meet the bar are pnpm v10.26+ (v11+ recommended) and bun. npm and yarn (1 or berry) lack the per-package lifecycle allowlist and release-age gate that this audit requires.

This audit distinguishes two kinds of "critical": (a) currently-exploitable misconfigurations (e.g., `verifyStoreIntegrity: false`), and (b) policy floors — the *absence* of a hardening primitive this audit treats as mandatory (e.g., running on npm/yarn). Label policy findings as "critical (policy)" or "high (policy)" so consumers can calibrate urgency.

Read whichever of these exist: `package.json`, `pnpm-workspace.yaml`, `.npmrc`, `bunfig.toml`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `bun.lockb`. Then evaluate:

1. Manager choice — npm or yarn present? Critical (policy) — they cannot satisfy items 3–5 of this audit. Multiple lockfiles? High — pick one.
2. pnpm version floor — `packageManager` must pin pnpm `>= 10.26` (when `allowBuilds` first shipped); v11+ recommended since v11 removes the legacy split keys. If pnpm `< 11` and legacy keys (`onlyBuiltDependencies`, `neverBuiltDependencies`, `ignoredBuiltDependencies`, `ignoreDepScripts`) are still present, recommend the codemod `pnpx codemod run pnpm-v10-to-v11`.
3. Lifecycle script allowlist:
   - **pnpm:** v10.26+ denies scripts by default for unlisted packages. The finding is about the audit log (`allowBuilds`) and the fail-fast switch (`strictDepBuilds`). `strictDepBuilds: false` = high (silent skip masks new dep requests). `allowBuilds` undefined = medium (gate still on by default, but no written record of approved scripts). Entries without inline justification comments = low.
   - **bun:** does NOT execute lifecycle scripts by default. `trustedDependencies` is an opt-in allowlist, with a built-in default allowlist for known-safe packages. The finding is about manual trust grants: any entry in `trustedDependencies` that is NOT in Bun's default allowlist and lacks a justification comment = medium. Absence of `trustedDependencies` and `ignoreScripts` is NOT a finding — defaults are safe.
4. `minimumReleaseAge` floor — pnpm: ≥ 4320 (minutes; 3 days); v11 default is 1440 (24h); below 4320 = medium (policy). bun: ≥ 259200 (seconds; 3 days); default null = high (policy). Note the unit difference — pnpm minutes, bun seconds.
   - Additionally for pnpm: pin `minimumReleaseAgeStrict: true` defensively (defaults to `true` only when `minimumReleaseAge` is configured). Note that `minimumReleaseAgeIgnoreMissingTime: true` (default) silently skips the gate for packages whose registry omits the `time` field — common on private registries. Recommend setting it to `false` only after confirming the internal registry returns `time`.
5. `minimumReleaseAgeExclude` — if scoped internal packages (`@your-org/*`) appear in the lockfile, the exclude list should cover them. pnpm field is singular (`minimumReleaseAgeExclude`); bun field is plural (`minimumReleaseAgeExcludes`).
6. Scope → registry mapping — for any `@scope/*` package in the lockfile, `registries:` (pnpm) or `[install.scopes]` (bun) must map the scope to the correct registry. Missing mapping = dependency confusion vector (high).
7. Default downgrades — flag any explicit override of safe defaults: pnpm `verifyStoreIntegrity: false`, `blockExoticSubdeps: false`, `strictDepBuilds: false` — all high. Do NOT flag `enablePrePostScripts: true` (default): it governs `pnpm foo` → `prefoo`/`postfoo` in the current project's scripts, not dependency build scripts.

Read the full checklist at `{{SKILL_DIR}}/references/package-manager-checklist.md` — it contains exact field names, units, defaults, the policy / exploitable distinction, and fix examples for both pnpm and bun.

Report findings grouped by severity, same format as the Actions audit. For each finding, include the exact YAML/TOML snippet needed to remediate. Mark policy findings explicitly. Do not edit files.
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
| Required status check named in ruleset but workflow trigger filter excludes the protected branch | high | Add the branch to `on.push.branches` / `on.pull_request.branches`, or drop the check from the ruleset |
| npm or yarn lockfile present | critical (policy) | Migrate to pnpm (`pnpm import`) or bun; remove old lockfile |
| pnpm `strictDepBuilds: false` | high | Remove the override or set `true` — fail-fast on unreviewed build scripts |
| pnpm without `allowBuilds` map | medium | Define `allowBuilds:` in `pnpm-workspace.yaml`; gate is already on, the map is the audit log |
| bun `trustedDependencies` entry not in Bun's default allowlist and uncommented | medium | Add a justification comment or remove the entry |
| pnpm `minimumReleaseAge` < 4320 (incl. default 1440) | medium (policy) | Set `minimumReleaseAge: 4320` and `minimumReleaseAgeStrict: true` in `pnpm-workspace.yaml` |
| pnpm `minimumReleaseAge` unset on pnpm < 11 | high (policy) | Set `minimumReleaseAge: 4320` (3-day floor) |
| bun `install.minimumReleaseAge` unset | high (policy) | Set `minimumReleaseAge = 259200` in `bunfig.toml [install]` (seconds, not minutes) |
| pnpm < 10.26 in `packageManager` | high | Bump to `pnpm@11.x`; run `pnpx codemod run pnpm-v10-to-v11` |
| pnpm 10.26 ≤ version < 11 with legacy keys still present | medium | Run the codemod and remove `onlyBuiltDependencies` / `neverBuiltDependencies` / `ignoredBuiltDependencies` / `ignoreDepScripts` |
| Internal `@scope/*` in lockfile without `registries:` mapping | high | Add scope→registry mapping in `pnpm-workspace.yaml` or `bunfig.toml [install.scopes]` |
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
- **Adding a required status check without checking the workflow trigger covers the branch.** The check name in the ruleset must match a `name:` in a workflow whose `on:` includes the protected branch. Misalignment makes every PR to that branch permanently BLOCKED.
- **Reporting "bypass is broken" when the red banner is still visible.** The "Review required" warning persists even for users with active bypass — the bypass action is the separate button under the banner (web) or `--admin` flag (CLI), not a change to the banner itself.
- **Copying pnpm's `minimumReleaseAge` value into bun's.** pnpm is **minutes** (4320 = 72h). bun is **seconds** (259200 = 72h). Setting bun's to 4320 gives 72 minutes of protection.
- **Filling `allowBuilds` without comments.** Every `true` entry is an audited grant — the comment explaining why is the audit log. A bare list of names rots into "we don't know why core-js is allowed" within a quarter.
- **Trusting pnpm v11's `minimumReleaseAge: 1440` default.** The default is 24h, not the recommended 72h. Set it explicitly so a future pnpm upgrade can't silently re-lower the floor.
- **Forgetting `minimumReleaseAgeStrict` and `minimumReleaseAgeIgnoreMissingTime`.** Without `Strict: true`, pnpm may fall back to a too-fresh version to keep installation succeeding. `IgnoreMissingTime: true` (default) silently skips the gate for packages whose registry omits the `time` field — the typical private-registry state.
- **Calling bun's lifecycle defaults a finding.** Bun denies dependency lifecycle scripts by default; `trustedDependencies` is an opt-in allowlist with built-in safe defaults. Missing `trustedDependencies` is *not* a finding — only unjustified manual grants are.
- **Treating pnpm `enablePrePostScripts` as a supply-chain control.** It governs `pnpm foo` → `prefoo` / `postfoo` for the current project's own scripts. Dependency build scripts are gated by `allowBuilds` + `strictDepBuilds`.

## Keywords

security audit, supply chain, github actions, sha pinning, pinact, persist-credentials, pull_request_target, pwn request, release security, npm provenance, oidc, trusted publishers, frozen lockfile, npm ci, prod flag, devDependencies, dependabot, harden ci, cache poisoning, branch protection, tag protection, rulesets, bypass actors, sha_pinning_required, default_workflow_permissions, secret scanning, package manager, pnpm, bun, allowBuilds, strictDepBuilds, trustedDependencies, minimumReleaseAge, minimumReleaseAgeExclude, lifecycle scripts, postinstall, dependency confusion, registries, scope mapping
