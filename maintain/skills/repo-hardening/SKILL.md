---
name: repo-hardening
description: >
  Apply a security hardening baseline to a GitHub repository via gh api — branch and
  tag rulesets, Actions token defaults, secret scanning, Dependabot, private
  vulnerability reporting, CodeQL, and branch-restricted environments for deploy
  secrets. Use when the user asks to harden a repo, protect a branch, lock down
  releases or tags, set up rulesets, move deploy secrets into an environment, or
  bootstrap security settings for a new repository or pipeline.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
user-invocable: true
argument-hint: "[apply|check]"
---

# Repo Hardening: GitHub Security Baseline

## Purpose

Apply a proven hardening baseline to a GitHub repository in one scripted pass. Everything
here is done with `gh api` from the user's machine — no admin UI clicking. The baseline
covers: Actions token defaults, security features, a branch protection ruleset, a release
tag ruleset, and branch-restricted environments for deploy secrets.

This is the **apply** counterpart to the `security-audit` skill: the audit finds and
reports gaps read-only; this skill sets the baseline proactively (new repos, new
pipelines) or after an audit. The audit's reference checklists document the *why* for
every item here in more depth.

## When to Use This Skill

Use when the user asks to:
- "Harden this repo", "secure the repository", "apply security settings"
- "Protect master/main", "set up rulesets", "protect release tags"
- "Move deploy secrets to an environment", "lock down the Cloudflare/Vercel/AWS token"
- "Set up a new repo securely", "bootstrap repo settings"

Do NOT use when the user only wants findings without changes — that is `security-audit`.
Org-level policies, SSO, and GitHub Enterprise controls are out of scope.

## Prerequisites

- `gh` CLI authenticated as a repo **admin** (`gh auth status`; rulesets, environments,
  and settings PATCHes all require admin).
- Resolve the target once: `gh repo view --json nameWithOwner --jq .nameWithOwner`.

## Workflow

### Step 0: Inventory Before Touching Anything

Run the read-only sweep and build a diff of *already set* vs *to apply*. Never apply blind
— existing rulesets or environments may encode deliberate choices, and re-creating them
duplicates rules.

```bash
gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis}'
gh api repos/<owner>/<repo>/actions/permissions/workflow
gh api repos/<owner>/<repo>/rulesets --jq '[.[] | {id, name, target, enforcement}]'
gh api repos/<owner>/<repo>/actions/secrets --jq '[.secrets[].name]'
gh api repos/<owner>/<repo>/environments --jq '[.environments[].name]'
gh api repos/<owner>/<repo>/private-vulnerability-reporting
```

Present the diff and confirm scope with the user before applying (see Asking the User).
Skip every step whose target state is already in place, and say so in the final report.

### Step 1: Actions Token Defaults

```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
```

Safe when workflows declare their own `permissions:` blocks (they should — flag any that
don't rather than skipping this step).

### Step 2: Security Features

```bash
gh api -X PATCH repos/<owner>/<repo> --input - <<'EOF'
{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}
EOF
gh api -X PUT repos/<owner>/<repo>/vulnerability-alerts
gh api -X PUT repos/<owner>/<repo>/automated-security-fixes
gh api -X PUT repos/<owner>/<repo>/private-vulnerability-reporting
gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f state=configured
```

Plan-related errors (private repo without Advanced Security) are informational — record
and continue. If the repo has a `SECURITY.md`, verify the reporting channel it advertises
is now actually enabled.

### Step 3: Branch Protection Ruleset

Template: `assets/ruleset-branch.json`. Fill in the required status checks from a recent
green run — check names must match **exactly** as GitHub reports them, including expanded
matrix legs:

```bash
gh api "repos/<owner>/<repo>/commits/$(git rev-parse origin/<default-branch>)/check-runs?per_page=50" \
  --jq '[.check_runs[].name] | unique'
```

Exclude non-blocking checks (benchmarks, deploys) from the required list. Then:

```bash
gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset-branch.json
```

Decisions baked into the template (adjust per answers from Asking the User):
- `~DEFAULT_BRANCH` targets the default branch without hardcoding its name.
- Bypass actor `{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}`
  is Repository Admin — right for a solo maintainer (never blocked, while a leaked
  non-admin token or Actions token still is). For teams, drop the bypass and set
  `required_approving_review_count` to 1+.
- Warn the user: matrix check names are verbatim — reshaping the CI matrix requires a
  matching ruleset update, or merges block (admin bypass still works).

### Step 4: Release Tag Ruleset

Apply when a workflow triggers on tag push (`on.push.tags`), or when the user plans one.
With a tag-triggered publish, tag creation is effectively "publish" — this ruleset is the
single most important control in the file.

Template: `assets/ruleset-tag.json` (restricts `creation`, `update`, `deletion`,
`non_fast_forward` on `refs/tags/v*` to the bypass actors).

```bash
gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset-tag.json
```

The user's local `git tag && git push` flow keeps working through the admin bypass; the
Actions token and non-admin credentials cannot mint release tags.

### Step 5: Deploy Secrets into a Branch-Restricted Environment

Applies when Step 0 found deploy-provider credentials (`CLOUDFLARE_*`, `VERCEL_*`,
`AWS_*`, `NETLIFY_*`, `FLY_*`, …) as repository-level secrets. Why this is critical: a
push-triggered workflow executes the workflow file *from the pushed ref*, so any branch
push can rewrite it to use repo-level secrets — including deploying that branch over
production.

**Order matters; follow exactly:**

1. Create the environment **before** any workflow references it (a workflow run naming a
   nonexistent environment auto-creates it *unprotected*):
```bash
gh api -X PUT repos/<owner>/<repo>/environments/<env-name> --input - <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
gh api -X POST repos/<owner>/<repo>/environments/<env-name>/deployment-branch-policies \
  -f name=<default-branch> -f type=branch
```
2. Secret values are **write-only** — they cannot be copied via API. Have the user
   re-enter them in their own terminal (never paste values into the conversation):
   `gh secret set <NAME> --env <env-name> -R <owner>/<repo>`
3. Update the deploy workflow: split an uncredentialed `build` job (all branches) from a
   `deploy` job with `environment: <env-name>`, gated by
   `if: github.ref == 'refs/heads/<default-branch>'`, consuming the build artifact.
4. **Only after** the workflow change is pushed and env secrets confirmed, delete the
   repo-level copies: `gh secret delete <NAME> -R <owner>/<repo>`. The hole stays open
   until they are gone.

Tell the user the cost up front: branch preview deploys stop working. Restoring them
safely needs a second provider project with its own scoped token in a separate
unprotected environment.

### Step 6: Manual Items — Report, Don't Skip Silently

These cannot be done via `gh`; list them for the user in the final report:

- **npm** (when the repo publishes packages): Trusted Publisher pinned to the exact
  `owner/repo` + workflow filename; Publishing access set to *require 2FA and disallow
  bypass tokens* once OIDC is the only publish path.
- **Provider token scope**: the deploy token itself should be least-privilege (e.g.
  Cloudflare: only `Account · Cloudflare Pages · Edit`). Verified in the provider
  dashboard, not the repo.

### Step 7: Report

End with a compact table: each baseline item → `applied` / `already set` / `skipped
(reason)` / `manual (user)`. Include the exact commands for anything deferred.

## Asking the User

Before applying (after Step 0's inventory), confirm scope in one round. With
`AskUserQuestion` where available; otherwise present the same choices as a numbered list
in chat and wait for a reply:

1. **Ruleset strictness** — Solo (admin bypass, 0 approvals; recommended for
   single-maintainer repos) / Team (no bypass, 1+ approvals) / Skip rulesets.
2. **Deploy secrets** — Migrate to environment now (recommended; previews break) / Leave
   at repo level (records a critical finding in the report).

Required status checks and the environment name are derived from the repo (CI run check
names; provider name like `cloudflare-production`) — state them in the confirmation
rather than asking.

## Common Mistakes

- **Creating the environment after the workflow references it** — GitHub auto-creates it
  unprotected and the branch policy silently never exists.
- **Deleting repo-level secrets before the environment migration is complete** — breaks
  deploys; doing it in the right order but stopping halfway leaves the hole open.
- **Copying check names from workflow YAML instead of a real run** — matrix names in YAML
  are templates (`${{ matrix.node-version }}`); rulesets need the expanded names.
- **Adding a `pull_request` rule with `required_approving_review_count: 1` on a solo
  repo without a bypass** — the maintainer can never merge; nobody else can approve.
- **Enabling `sha_pinning_required` while workflows still use tag refs** — every workflow
  run fails until all `uses:` entries are SHA-pinned. Pin first, then flip.
