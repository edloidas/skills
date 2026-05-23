---
name: security-audit
description: Use when the user asks to audit a repository for security risks — supply-chain, CI, release, runtime, secrets, or any combination. Aggregates findings from focused subagents across whichever audit areas the repo exposes. Trigger phrases include "audit security", "security audit", "check supply chain", "harden CI", "harden release", "review for vulnerabilities".
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Glob Grep Agent
---

# Security Audit

## Purpose

Audit a repository for security risks across whichever areas apply. The skill aggregates findings from focused subagents — one per audit area — and produces a single severity-ordered report.

The architecture is designed to grow. Adding a new audit area means writing a new checklist under `references/` and a new subagent prompt in Step 2 — no change to the aggregation, report, or fix flow.

**Currently implemented:**
- GitHub Actions workflows under `.github/workflows/` — see `references/actions-checklist.md`
- Release configuration (`release.yml`, `package.json`, `dependabot.yml`, npm publishing) — see `references/release-checklist.md`

**Planned (not yet implemented):**
- Non-GitHub CI providers (CircleCI, GitLab CI)
- Container security (Dockerfiles, base-image pinning, multi-stage hygiene)
- Secret scanning (committed secrets, exposed env files)
- Runtime config (CSP, CORS, security headers in frameworks that ship them)
- Dependency policy (allowed-license check, banned-package list)

For dependency CVE scanning specifically, use `gh dependabot alerts`, `npm audit`, or `pnpm audit` directly — this skill does not duplicate that.

## When to Use

Use when the user asks to:
- "Audit security" / "security audit"
- "Check supply chain" / "review for supply-chain attacks"
- "Harden CI" or "harden actions"
- "Audit release workflow" / "audit npm publishing"

Trigger phrases: `security audit`, `supply chain`, `ci hardening`, `harden actions`, `audit release`, `pwn request`, `sha pinning`.

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
```

If `.github/workflows/` is absent, stop and report that there is no CI to audit. If `package.json` is absent or `private: true`, note it — release findings about provenance change severity.

### Step 2: Dispatch Audit Subagents in Parallel

Spawn **one subagent per applicable audit area, in a single message** so they run concurrently.

**Claude Code path:** use the `Agent` tool with `subagent_type: general-purpose`.

**Codex path:** use `spawn_agent` with `agent_type: explorer` (read-only repository inspection).

**Fallback:** if subagents are unavailable, run each audit area sequentially in the main agent using the same prompts.

Skip an area if the repo does not expose it (no `.github/workflows/` → skip Actions subagent; no publish config → skip Release subagent). As new audit areas are added under `references/`, add the corresponding subagent dispatch here.

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

Read the full checklist at `<repo>/skills/audit/security-audit/references/actions-checklist.md`.

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
- `<repo>/skills/audit/security-audit/references/release-checklist.md`
- `<repo>/skills/audit/security-audit/references/install-flags.md`

Report findings grouped by severity, same format as the Actions audit. Do not edit files.
```

### Step 3: Aggregate Findings

Wait for both subagents. Merge into a single report:

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

## Keywords

security audit, supply chain, github actions, sha pinning, pinact, persist-credentials, pull_request_target, pwn request, release security, npm provenance, oidc, trusted publishers, frozen lockfile, npm ci, prod flag, devDependencies, dependabot, harden ci, cache poisoning
