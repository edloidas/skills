# Repository Settings Security Checklist

Detailed criteria for the Repo Settings audit subagent. These are settings exposed via the GitHub REST API, not workflow file content. Fixes are `gh api -X PUT` / `POST` calls, not PRs.

Throughout this checklist, `<owner>/<repo>` is the target repository. All `gh api` calls assume the current user has admin scope on the repo.

## 1. Default `GITHUB_TOKEN` Permissions

**Detection:**
```bash
gh api repos/<owner>/<repo>/actions/permissions/workflow
```

Look for `default_workflow_permissions` and `can_approve_pull_request_reviews`.

**Severity:** high if `write` or `can_approve_pull_request_reviews: true`.

**Why:** Any workflow that doesn't declare its own `permissions:` block inherits this default. With `write`, a malicious or buggy workflow can mutate the repo. With `can_approve_pull_request_reviews: true`, workflows can approve their own PRs and merge them past branch protection's approval rule.

**Fix:**
```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

**Companion check:** `actions-checklist.md` item 2 (workflow-level `permissions:`). The two together implement defence in depth: explicit workflow-level `permissions:` on every file PLUS a `read` default for anything new.

## 2. `sha_pinning_required`

**Detection:**
```bash
gh api repos/<owner>/<repo>/actions/permissions
```

Look for `sha_pinning_required`.

**Severity:** high if `false` AND `actions-checklist.md` item 1 has already been remediated. Low if workflows are not yet SHA-pinned.

**Why:** Runtime guard that refuses to start any workflow run containing a tag-pinned `uses:` line. Prevents regression: once enabled, no contributor can land a PR that introduces `@v1`-style pinning, because the workflow run breaks immediately on the failing PR.

**Fix:**
```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions \
  -F enabled=true \
  -f allowed_actions=all \
  -F sha_pinning_required=true
```

**Sequencing warning:** Enabling this BEFORE workflows are SHA-pinned will break every workflow run. Verify `actions-checklist.md` item 1 is satisfied (every `uses:` is a 40-char hex SHA) before flipping this on.

**Companion check:** `actions-checklist.md` item 1 (per-file SHA pinning).

## 3. `allowed_actions`

**Detection:** same call as item 2, look for `allowed_actions`.

**Severity:** informational.

**Why:** `"all"` allows any GitHub Action to run. `"selected"` restricts to a curated allow-list. Most repos run with `"all"`. `"selected"` is appropriate for high-security environments (publishing infrastructure, secrets-heavy releases) but adds friction.

**Fix:** Only restrict if the security posture requires it. Configure via the GitHub UI under Settings → Actions → General → "Allow select actions".

## 4. Branch Protection Rulesets

**Detection:**
```bash
gh api repos/<owner>/<repo>/rulesets
# Then for each ruleset of target=branch:
gh api repos/<owner>/<repo>/rulesets/<id>
```

Audit findings:

- **Default branch not in any branch ruleset** — critical.
- **Active release-source branches (e.g., `x.y` version branches) not covered** — high.
- **Force-push permitted on protected branches (no `non_fast_forward` rule)** — high.
- **Branch deletion permitted (no `deletion` rule)** — medium.
- **No `required_status_checks` rule on the default branch** — medium.
- **No `required_linear_history` rule** — low (process choice).

**Severity:** see per-finding above.

**Why:** Rulesets are the only mechanism that prevents direct pushes to release-source branches. The release workflow may have a tag-precheck (`release-checklist.md` item 2) requiring tags to be reachable from trusted branches — that precheck is undermined if the trusted branches themselves are unprotected.

**Fix pattern — create or extend the protection ruleset:**

```bash
gh api -X PUT repos/<owner>/<repo>/rulesets/<existing_id> --input - <<'EOF'
{
  "name": "Protect default and version branches",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH", "refs/heads/1.0"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "CI", "integration_id": 15368}]}},
    {"type": "required_linear_history"}
  ],
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}
  ]
}
EOF
```

`integration_id: 15368` is GitHub Actions (the most common status-check provider). The branch pattern uses fnmatch — `*` matches anything including `/`, so prefer explicit paths over broad globs.

**Listing all version branches:** prefer explicit `refs/heads/<version>` over a glob like `refs/heads/?.*`. Patterns with `?` and `*` can accidentally catch unrelated branches. Add new release branches to the include list as they are cut.

## 5. PR Approval Rule

**Detection:** in the rulesets above, look for the `pull_request` rule and its `required_approving_review_count`.

**Severity:** medium if `0` on a release-source branch.

**Why:** Without required approvals, any contributor with write access can self-merge an unreviewed PR. For one-maintainer repos this is process choice, not security — but for any repo with multiple contributors it is a real gap.

**Fix:** add or update the `pull_request` rule:

```json
{"type": "pull_request", "parameters": {
  "required_approving_review_count": 1,
  "dismiss_stale_reviews_on_push": false,
  "required_reviewers": [],
  "require_code_owner_review": false,
  "require_last_push_approval": false,
  "required_review_thread_resolution": false,
  "allowed_merge_methods": ["squash", "rebase"]
}}
```

**Coupling with Dependabot auto-merge:** see section "Bypass actor patterns" below — naively adding the approval rule breaks Dependabot auto-merge unless bypass is configured correctly.

## 6. Tag Protection Rulesets

**Detection:**
```bash
gh api repos/<owner>/<repo>/rulesets --jq '.[] | select(.target=="tag")'
```

**Severity:** high if release workflow triggers on `v*` tag push AND no tag ruleset exists.

**Why:** With no tag protection, anyone with repo write access can push a `v*` tag from any commit, which triggers the release workflow. Even with a precheck (`release-checklist.md` item 2) that requires the tagged commit to be on master/version branches, an unprotected tag namespace lets attackers move existing release tags to malicious commits via `--force`.

**Fix:**
```bash
gh api -X POST repos/<owner>/<repo>/rulesets --input - <<'EOF'
{
  "name": "Protect release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": {
    "ref_name": {"include": ["refs/tags/v*"], "exclude": []}
  },
  "rules": [
    {"type": "creation"},
    {"type": "update"},
    {"type": "deletion"}
  ],
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}
  ]
}
EOF
```

`creation` blocks new tags, `update` blocks rewriting existing tags, `deletion` blocks deletion. Together they preserve the tag-as-immutable-release-marker contract.

**Tag pattern scope:** match the regex in `release-checklist.md` item 2 — if the release workflow triggers on `v*`, protect `refs/tags/v*`. If it also accepts `alpha-*` or other patterns, extend the include list.

## 7. Secret Scanning and Push Protection

**Detection:**
```bash
gh api repos/<owner>/<repo> --jq '.security_and_analysis'
```

Look for `secret_scanning.status` and `secret_scanning_push_protection.status`.

**Severity:** medium if either is `disabled` AND the plan supports them (free for public, enterprise for private).

**Why:** Secret scanning detects committed credentials post-push; push protection blocks them at `git push` time. Catches accidental API key / token commits before they need rotation. Free for public repos; available for private repos in GitHub Enterprise plans.

**Fix (where supported):**
```bash
gh api -X PATCH repos/<owner>/<repo> --input - <<'EOF'
{
  "security_and_analysis": {
    "secret_scanning": {"status": "enabled"},
    "secret_scanning_push_protection": {"status": "enabled"}
  }
}
EOF
```

If the API returns a plan-related error (private repo without the required plan), record as informational and skip.

## 8. Dependabot Updates, Vulnerability Reporting, CodeQL

**Detection:**
```bash
gh api repos/<owner>/<repo> --jq '.security_and_analysis.dependabot_security_updates.status'
gh api repos/<owner>/<repo>/private-vulnerability-reporting --jq '.enabled'
gh api repos/<owner>/<repo>/code-scanning/default-setup --jq '.state'
```

**Severity:** medium each — but **high** when `SECURITY.md` advertises private vulnerability reporting while the feature is disabled: the documented reporting channel is a dead end, and researchers fall back to public issues.

**Why:** Dependabot security updates turn alerts into PRs instead of a dashboard nobody checks. Private vulnerability reporting is the intake half of any security policy. CodeQL default setup is zero-maintenance code scanning for supported languages.

**Fix (one call each, admin token):**
```bash
gh api -X PUT repos/<owner>/<repo>/vulnerability-alerts          # prerequisite for the next line
gh api -X PUT repos/<owner>/<repo>/automated-security-fixes
gh api -X PUT repos/<owner>/<repo>/private-vulnerability-reporting
gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f state=configured
```

Cross-check `SECURITY.md` in the same pass: whatever channel it names must actually be enabled.

## 9. Required Status Check Coverage

**Detection:** for every branch covered by a branch ruleset, every required status check in that ruleset must be produced by a workflow whose trigger filter actually fires on that branch.

```bash
# Step 1: list protected branches and their required checks
gh api repos/<owner>/<repo>/rulesets --jq '.[] | select(.target=="branch") | .id' \
  | while read -r id; do
      gh api "repos/<owner>/<repo>/rulesets/$id" \
        --jq '{branches: .conditions.ref_name.include, checks: [.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context]}'
    done

# Step 2: list workflow names and their trigger.branches filters
grep -A4 '^on:' .github/workflows/*.yml
```

For each (branch, required-check) pair, identify the workflow producing that check and confirm its `on.pull_request.branches` (and `on.push.branches`) includes the protected branch. The check name in the ruleset maps to the workflow's `name:` field at the top of the YAML.

**Severity:** high.

**Why:** A required check that never fires leaves every PR in `mergeStateStatus: BLOCKED`. The only paths to merge are admin bypass (defeats the rule) or a manual workflow edit per PR. We hit this exact pattern when the protection ruleset was extended to cover `1.0` but `ci.yml` still triggered only on `master` — every backport PR needed a one-line trigger fix before CI could fire.

**Fix:** extend the workflow's trigger filter to cover every protected branch the check is required on:

```yaml
on:
  push:
    branches: [master, '1.0']
  pull_request:
    branches: [master, '1.0']
```

Alternative: if the workflow legitimately should not run on the secondary branch, remove that branch from the ruleset's `required_status_checks` parameters instead — same alignment, different direction.

**Matrix legs are named verbatim:** required checks must list matrix job names exactly as they expand at run time (`Node.js Smoke Test (lts/*)`, not the template `Node.js Smoke Test (${{ matrix.node-version }})`). Renaming or reshaping the matrix silently orphans the required check and blocks every PR until the ruleset is updated to match. Flag rulesets whose required checks embed matrix parameters as a maintenance note.

**Companion:** `actions-checklist.md` (workflow trigger filters). The repo-settings auditor has access to both ruleset state and workflow files, so this check belongs here rather than splitting detection across two subagents.

## 10. Deploy Secrets Reachable from Arbitrary Branches

**Detection:**
```bash
gh api repos/<owner>/<repo>/actions/secrets --jq '[.secrets[].name]'
gh api repos/<owner>/<repo>/environments --jq '[.environments[] | {name, protection_rules, deployment_branch_policy}]'
```

Deploy-provider credentials (`CLOUDFLARE_*`, `VERCEL_*`, `AWS_*`, `NETLIFY_*`, `FLY_*`, `RAILWAY_*`, …) stored as **repository-level** secrets and referenced by a workflow triggered on `push:` with a broad branch filter (`'**'` or similar).

**Severity:** critical when the deploy target is production.

**Why:** Push-event workflows execute the workflow file **from the pushed ref**. Anyone who can push any branch can edit the workflow on that branch to do anything with repo-level secrets — deploy their branch over production (e.g. `wrangler pages deploy --branch <production-branch>`) or exfiltrate the token. Default-branch protection does not help; the attack never touches the default branch.

**Fix — move the secrets into a branch-restricted environment, in this order:**

1. **Create the environment before any workflow references it.** A workflow run that names a nonexistent environment auto-creates it **unprotected**:
```bash
gh api -X PUT repos/<owner>/<repo>/environments/<env-name> --input - <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
gh api -X POST repos/<owner>/<repo>/environments/<env-name>/deployment-branch-policies \
  -f name=<default-branch> -f type=branch
```
2. **Secrets are write-only** — values cannot be copied out via API. The user re-enters them: `gh secret set <NAME> --env <env-name> -R <owner>/<repo>`.
3. Update the workflow: split an uncredentialed `build` job (all branches) from a `deploy` job with `environment: <env-name>` and `if: github.ref == 'refs/heads/<default-branch>'`, passing the built output as an artifact.
4. **Only then** delete the repository-level copies: `gh secret delete <NAME> -R <owner>/<repo>`. The hole stays open until they are gone — the environment alone does not stop a pushed-ref workflow from reading repo-level secrets.

**Cost:** branch preview deploys die. Restoring them safely needs a second provider project with its own narrowly-scoped token in a separate unprotected environment — a leaked preview token then cannot touch production.

**Companion — provider-side token scope:** the token itself should be least-privilege (e.g. a Cloudflare token with only `Account · Cloudflare Pages · Edit`, not account-wide). Not auditable from the repo; report as an ask-the-user verification item.

## Bypass Actor Patterns

This is a pattern reference, not a numbered finding. Use it when remediating items 4, 5, 6.

### `bypass_mode: always` is all-or-nothing

A bypass actor with `bypass_mode: always` bypasses **every rule in the ruleset it belongs to**. There is no per-rule granular bypass within a single ruleset. If you need an actor to bypass rule X but not rule Y, the rules must live in **separate rulesets**.

### Well-known actor IDs

| Actor | `actor_type` | `actor_id` | Notes |
|---|---|---|---|
| Repository Admin role | `RepositoryRole` | `5` | Standard admin bypass |
| Repository Maintain role | `RepositoryRole` | `4` | One level below admin |
| Repository Write role | `RepositoryRole` | `3` | Rarely used as bypass |
| Dependabot GitHub App | `Integration` | `29110` | Same ID across all accounts (GitHub-owned app) |
| GitHub Actions | `Integration` | `15368` | Used as `integration_id` for status check sources |

### Granular bypass via ruleset splitting

To grant Dependabot bypass on PR approval **but not** on status checks, split the rules into two rulesets:

**Ruleset 1 — strict rules, no Dependabot bypass:**
```json
{
  "name": "Protect default and version branches",
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_status_checks", "parameters": {...}},
    {"type": "required_linear_history"}
  ],
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}
  ]
}
```

**Ruleset 2 — approval only, Dependabot bypasses:**
```json
{
  "name": "Require PR approval",
  "rules": [
    {"type": "pull_request", "parameters": {"required_approving_review_count": 1, "allowed_merge_methods": ["squash", "rebase"]}}
  ],
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"},
    {"actor_id": 29110, "actor_type": "Integration", "bypass_mode": "always"}
  ]
}
```

Result: Dependabot PRs must still pass status checks before auto-merge fires, but the approval requirement is bypassed.

### Verifying bypass

After applying, fetch the ruleset and inspect:
```bash
gh api repos/<owner>/<repo>/rulesets/<id> --jq '{bypass_actors, current_user_can_bypass}'
```

`current_user_can_bypass: "always"` confirms the calling user can bypass — useful sanity check before requiring approvals.

### How bypass appears in practice

The "Review required" / "Required check missing" red banner stays visible on the PR page **even when the calling user has bypass**. The actual merge action lives under that banner as one of:

- Web UI: a separate button labelled "Merge without waiting for requirements to be met (bypass rules)" appears under the warning. Visible only to users with bypass.
- CLI: `gh pr merge <num> --admin --rebase --delete-branch` (or `--squash`). The `--admin` flag is the explicit bypass token; without it, the merge call fails with the same red-banner error.

If a user reports "the bypass is broken — GitHub still says approval required", the most likely cause is they were looking at the warning rather than the button below it. The bypass is live as long as `current_user_can_bypass` returns `"always"`.

### `--auto` interaction with bypass

`gh pr merge --auto --squash` enables GitHub's auto-merge feature, which fires as soon as **all bypass-adjusted requirements** are satisfied. For an actor in `bypass_actors` (e.g., Dependabot in the approval-only ruleset), this means:

- The required `Test` check still has to pass (Dependabot is not in the status-checks ruleset's bypass list).
- The required approval count is bypassed.
- Auto-merge fires immediately once tests pass — no manual approval needed.

This is the intended outcome of the ruleset-splitting pattern above. Verify after applying by opening a test Dependabot-like PR and watching the merge queue behaviour.

## Quick Audit Block

Run these in parallel during Step 1 to gather everything the subagent needs:

```bash
gh api repos/<owner>/<repo>/actions/permissions
gh api repos/<owner>/<repo>/actions/permissions/workflow
gh api repos/<owner>/<repo>/rulesets
gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis, allow_squash_merge, allow_rebase_merge, delete_branch_on_merge, allow_auto_merge}'
gh api repos/<owner>/<repo>/actions/secrets --jq '[.secrets[].name]'
gh api repos/<owner>/<repo>/environments --jq '[.environments[].name]'
gh api repos/<owner>/<repo>/private-vulnerability-reporting
gh api repos/<owner>/<repo>/code-scanning/default-setup --jq '.state'
```

Then for each ruleset returned, fetch the full body:
```bash
gh api repos/<owner>/<repo>/rulesets/<id>
```
