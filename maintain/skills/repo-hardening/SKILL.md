---
name: repo-hardening
description: >
  Apply a security hardening baseline to a GitHub repository via gh api — branch and tag
  rulesets, Actions token defaults, secret scanning, Dependabot, private vulnerability
  reporting, CodeQL, immutable releases, and branch-restricted environments for deploy
  secrets. The write half of the pair with audit:security-audit, which finds the same gaps
  read-only.
when_to_use: >
  On "harden this repo", "protect the main branch", "lock down releases or tags", "set up
  rulesets", "move deploy secrets into an environment", or "enable immutable releases", and
  when bootstrapping security settings for a new repository or pipeline.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[apply|check]"
---

# Repo Hardening: GitHub Security Baseline

## Purpose

**Writes to an external service, and to local files.** It changes GitHub repository settings,
creates rulesets and environments, deletes repository secrets, and adds a workflow file to the
working tree — all through `gh api` from the user's machine, no admin UI clicking. Several of
those writes are visible to everyone with access to the repo and some (a deleted secret) cannot
be undone from here. Nothing is applied before the Step 0 inventory and the confirmation round
in **Asking the User**. It never stages, commits, or pushes; the workflow file it writes is left
for the user to commit.

The baseline covers Actions token defaults, security features, immutable releases, a branch
protection ruleset, a release tag ruleset, a workflow-linting workflow, and branch-restricted
environments for deploy secrets.

**Edit mechanic.** `check-workflows.yml` in Step 6 is a new file, generated whole from the
template. Every other file touched already exists — notably the deploy workflow in Step 5 — and
is changed with targeted edits per hunk, never a whole-file rewrite, so the diff carries the job
split and nothing else.

`audit:security-audit` is the read half of the pair. It detects the same gaps and never
mutates anything — no file edit, no `gh api` write. Its findings are this skill's input.
Run this skill after an audit, or standalone to set the baseline proactively on a new repo
or pipeline. When the user wants gaps listed rather than changes made, use that skill instead.
Its reference checklists carry the *why* for every item here in more depth, and are worth
reading when a user questions an item.

## When to Use This Skill

Use when the user asks to:
- "Harden this repo", "secure the repository", "apply security settings"
- "Protect master/main", "set up rulesets", "protect release tags"
- "Move deploy secrets to an environment", "lock down the Cloudflare/Vercel/AWS token"
- "Set up a new repo securely", "bootstrap repo settings"

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

Present the diff and end the phase with one line carrying the counts:
`Inventory: 5 already set, 6 to apply, 2 manual, 1 not applicable`.

Then confirm scope per **Asking the User** and wait for the answer. Nothing in Steps 1-6 runs
while that round is open, and no step whose target state is already in place runs at all — those
are reported as `already set`.

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

Take the names from that real run, not from the workflow YAML: a matrix name in YAML is a
template (`${{ matrix.node-version }}`) and the ruleset needs the expanded name. Exclude
non-blocking checks (benchmarks, deploys) from the required list. Then:

```bash
gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset-branch.json
```

Decisions baked into the template (adjust per answers from Asking the User):
- `~DEFAULT_BRANCH` targets the default branch without hardcoding its name.
- Bypass actor `{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}`
  is Repository Admin — right for a solo maintainer (never blocked, while a leaked
  non-admin token or Actions token still is). For teams, drop the bypass and set
  `required_approving_review_count` to 1+. Never both at once on a solo repo: with no bypass
  and one required approval the maintainer can never merge, because nobody else can approve.
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

The order below is load-bearing: each step leaves the hole open until the next one lands, and
one of them is irreversible.

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

#### 6a. Clear the existing findings first

Run zizmor and fix what it reports before adding any check — a linter that fails on day one
reads as the hardening having broken CI:

```bash
docker run --rm -t -v "$(pwd):/repo:ro" ghcr.io/zizmorcore/zizmor:latest /repo/.github/workflows
```

If Docker is unavailable, ask the user to run it and paste the output. Re-run until clean, and
end the phase with one line: `zizmor: 7 findings -> 0 (4 workflows)`. If it could not run at
all, that line says so and Step 8 records the reason.

#### 6b. Add the linting workflow

Write `.github/workflows/check-workflows.yml`:

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
workflow-linting workflow that is itself tag-pinned fails its own check. Set
`advanced-security: false` unless the repo has GitHub Advanced Security, or the SARIF
upload step errors.

#### 6c. Decide whether the check is required

If Step 3 added `required_status_checks`, decide with the user whether `Lint CI workflows`
joins the required list, and put the name in the ruleset exactly as the workflow's `name:`
reads — a mismatch blocks every PR permanently. Adding it means a linter regression blocks
merges; leaving it out means the check is advisory. Either is defensible.

#### 6d. Report these two, do not do them

Neither is a `gh api` write, so both are reported in Step 8 rather than applied:

- **Stale branches** still carrying pre-hardening workflow files. List them and let the user
  decide — deleting someone's branch is not this skill's call:
  ```bash
  git branch -r --format='%(refname:short) %(committerdate:short)' | grep -v HEAD
  ```
  Old refs are reachable by `workflow_dispatch` and by `push:` filters that match them, and the
  Nx compromise ran through a workflow version already fixed on the default branch.
- **`sha_pinning_required`** (Actions setting). Flip it only once zizmor reports every `uses:`
  SHA-pinned; enabling it while any workflow still uses a tag ref fails every run until they
  are all pinned.

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

One row per baseline item — every one of Steps 1-7, including the ones that did not run, each
with a reason. Include the exact command for anything deferred. Then stop: do not re-run the
inventory to confirm, do not commit or push the workflow file, and do not extend the baseline
to org-level settings.

```markdown
| Item                        | Status                                                     |
| --------------------------- | ---------------------------------------------------------- |
| Actions token defaults      | applied (`read`, PR approval off)                          |
| Secret scanning + push prot | already set                                                |
| Dependabot alerts + fixes   | applied                                                    |
| Private vuln reporting      | applied                                                    |
| CodeQL default setup        | skipped — private repo without Advanced Security (403)     |
| Immutable releases          | applied — not retroactive; 11 earlier releases stay mutable |
| Branch ruleset              | applied — 3 required checks, admin bypass (solo)           |
| Tag ruleset                 | applied — `refs/tags/v*`                                   |
| Deploy secrets -> env       | applied — `cloudflare-production`, 2 secrets moved, repo-level copies deleted |
| Workflow linter             | applied — `check-workflows.yml` written, not committed; advisory, not required |
| zizmor sweep                | 7 findings -> 0                                            |
| Stale branches              | manual (user) — 3 remote branches older than 6 months, listed above |
| `sha_pinning_required`      | deferred — `gh api -X PUT repos/o/r/actions/permissions/workflow -F sha_pinning_required=true` |
| npm Trusted Publisher       | manual (user) — https://www.npmjs.com/package/voidvigil/access |
```

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

Before applying (after Step 0's inventory), confirm scope in one round:

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
