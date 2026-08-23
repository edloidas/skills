---
name: repo-hardening
description: >
  Apply a security hardening baseline to a GitHub repository via gh api — branch and
  tag rulesets, Actions token defaults, secret scanning, Dependabot, private
  vulnerability reporting, CodeQL, immutable releases, workflow linting, and
  branch-restricted environments for deploy secrets. This is the write half of the pair
  with audit:security-audit, which finds the same gaps read-only. Use when the user asks
  to harden a repo, protect a branch, lock down releases or tags, set up rulesets, move
  deploy secrets into an environment, enable immutable releases, or bootstrap security
  settings for a new repository or pipeline.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
user-invocable: true
argument-hint: "[apply|check]"
---

# Repo Hardening: GitHub Security Baseline

## Purpose

**This skill writes.** It changes repository settings, creates rulesets and
environments, and adds workflow files. Everything is done with `gh api` from the user's
machine — no admin UI clicking. The baseline covers Actions token defaults, security
features, immutable releases, a branch protection ruleset, a release tag ruleset, a
workflow-linting workflow, and branch-restricted environments for deploy secrets.

`audit:security-audit` is the read half of the pair. It detects the same gaps and never
mutates anything — no file edit, no `gh api` write. Its findings are this skill's input.
Run this skill after an audit, or standalone to set the baseline proactively on a new repo
or pipeline. If the user wants gaps listed rather than changes made, that is the skill to
use.

Because this skill writes, Step 0 is not optional: inventory first, show the diff, get
confirmation, and skip anything already in place. The audit's reference checklists
document the *why* for every item here in more depth, and are worth reading when a user
questions an item.

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
gh api repos/<owner>/<repo>/immutable-releases
ls .github/workflows/ 2>/dev/null
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

Then immutable releases, when the repo publishes GitHub Releases or has a tag-triggered
release workflow:

```bash
gh api -X PUT repos/<owner>/<repo>/immutable-releases
```

Once enabled, a published release's tag and assets can no longer be moved or replaced, so
swapping content requires a new version number. Two things to tell the user before
applying: it is **not retroactive** (releases published earlier stay mutable), and any
release automation that edits or re-uploads assets after publishing will start failing.
Revert is `gh api -X DELETE repos/<owner>/<repo>/immutable-releases`.

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

### Step 6: Keep Workflows Linted

Applies when `.github/workflows/` exists. The rulesets and settings above are enforced by
GitHub; the workflow files themselves are not, so nothing stops the next PR from
reintroducing a tag-pinned `uses:` or a `pull_request_target` that checks out PR code.

Clear the existing findings first — do not add a check that fails on day one:

```bash
docker run --rm -t -v "$(pwd):/repo:ro" ghcr.io/zizmorcore/zizmor:latest /repo/.github/workflows
```

If Docker is unavailable, ask the user to run it and paste the output. Fix what it reports,
re-run until clean, then add `.github/workflows/check-workflows.yml`:

```yaml
name: Lint CI workflows
on:
  push:
    branches: ['<default-branch>']
  pull_request:
    branches: ['**']
jobs:
  zizmor:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@<sha>
        with:
          persist-credentials: false
      - uses: zizmorcore/zizmor-action@<sha>
        with:
          advanced-security: false
```

Resolve both `<sha>` values to real 40-char commit SHAs before writing the file — a
workflow-linting workflow that is itself tag-pinned will fail its own check. Set
`advanced-security: false` unless the repo has GitHub Advanced Security, or the SARIF
upload step errors.

If Step 3 added `required_status_checks`, decide with the user whether `Lint CI workflows`
joins the required list. Adding it means a linter regression blocks merges; leaving it out
means the check is advisory. Either is defensible — but if it goes in the ruleset, the
check name must match the workflow's `name:` exactly, or every PR blocks permanently.

Two related items this does not cover, because neither is a `gh api` write:

- **Stale branches** still carrying pre-hardening workflow files. Old refs are reachable by
  `workflow_dispatch` and by `push:` filters that match them, and the Nx compromise ran
  through a workflow version already fixed on the default branch. List them and let the
  user decide:
  ```bash
  git branch -r --format='%(refname:short) %(committerdate:short)' | grep -v HEAD
  ```
  Deleting someone's branch is not this skill's call — report and ask.
- **`sha_pinning_required`** (Actions setting). Flip it only once zizmor reports every
  `uses:` SHA-pinned; enabling it earlier breaks every workflow run. See Common Mistakes.

### Step 7: Manual Items — Report, Don't Skip Silently

These cannot be done via `gh`; list them for the user in the final report:

- **npm** (when the repo publishes packages), at
  `https://www.npmjs.com/package/<name>/access` — give the user the resolved URL, one per
  public package in a monorepo, not a generic "your package settings":
  - Trusted Publisher pinned to the exact `owner/repo` + release workflow filename.
  - **Enable only "Allow npm stage publish"**, so a plain `npm publish` from that workflow
    is rejected and every release has to pass through a maintainer's 2FA approval
    (`npm stage approve <stage-id>`, or Staged Packages on npmjs.com). This is the control
    a fully compromised CI job cannot forge — the workflow holds a legitimate OIDC
    identity, and staging is what stops that identity from being enough. It only binds if
    it is set registry-side; the workflow using `npm stage publish` without this
    restriction is a convention, not a control.
  - Publishing access set to *require 2FA and disallow bypass tokens* once OIDC is the
    only publish path. Warn first: this revokes existing tokens, so any other automation
    publishing with a token breaks.
  - Requires npm CLI >= 11.15.0 and Node >= 22.14.0 in the release workflow. Check the
    workflow's `node-version` before recommending the switch.
- **Provider token scope**: the deploy token itself should be least-privilege (e.g.
  Cloudflare: only `Account · Cloudflare Pages · Edit`). Verified in the provider
  dashboard, not the repo.

### Step 8: Report

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
3. **Immutable releases** — Enable (recommended; not retroactive, and breaks automation
   that re-uploads release assets) / Skip. Ask only when Step 0 found releases or a
   tag-triggered workflow.

Required status checks and the environment name are derived from the repo (CI run check
names; provider name like `cloudflare-production`) — state them in the confirmation
rather than asking. Same for the workflow linter in Step 6: apply it if
`.github/workflows/` exists, and raise the required-check decision there rather than in
this round.

Keep it to one round. If the repo has no deploy secrets and no releases, questions 2 and 3
drop and only ruleset strictness is asked.

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
- **Adding the workflow-linting workflow before clearing its findings** — the first run
  fails and the user's impression is that the hardening broke CI. Run it locally, fix,
  then commit the workflow.
- **Tag-pinning the linter's own actions** — a `check-workflows.yml` using `@v1` fails its
  own SHA-pinning rule. Resolve real SHAs before writing the file.
- **Enabling immutable releases without saying it is not retroactive** — the user assumes
  old releases are sealed too. They are not, and a repo with a long release history keeps
  that exposure on every version published before the flip.
- **Deleting a stale branch on the user's behalf** — report the list and let them decide.
  A branch that looks abandoned may be someone's long-running work.
