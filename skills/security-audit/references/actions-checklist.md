# GitHub Actions Security Checklist

Detailed criteria for the Actions audit subagent. Each item: detection → severity → why → fix → exceptions.

## 1. SHA Pinning

**Detection:** classify every `uses:` line by what follows the `@`:

| Pin shape | Example | Severity |
|---|---|---|
| 40-char hex SHA | `actions/checkout@a81bbbf8298c0fa03ea29cdc473d45769f953675` | **pass** |
| Version tag (`@v<digits>` / `@v<digits>.<digits>` / `@<semver>`) | `actions/checkout@v6`, `gradle/actions/setup-gradle@v4.0.1` | **high** |
| Branch / floating ref (anything else: `@master`, `@main`, `@latest`, named branches) | `enonic/release-tools/release@master` | **critical** |

```bash
grep -hE 'uses: [^@]+@' .github/workflows/*.yml \
  | grep -v '^[[:space:]]*#' \
  | awk -F'@' '
      {
        ref=$2; sub(/[[:space:]].*$/, "", ref);
        if (ref ~ /^[a-f0-9]{40}$/) print "PASS  " $0;
        else if (ref ~ /^v?[0-9]+(\.[0-9]+){0,2}([-.][a-zA-Z0-9]+)?$/) print "TAG   " $0;
        else print "BRANCH " $0;
      }
    '
```

**Why two non-pass tiers:** moving a tag requires `git push --tags --force` (auditable, deliberate, and many CI policies block it). Moving a branch happens on every merge — a single compromised maintainer commit poisons the action. Branch pinning is therefore **categorically more dangerous** than tag pinning, not just a notch worse. Tag-pinning is the floor most repos sit at; branch-pinning is the failure mode that demands urgent action.

The TanStack npm compromise and the "million repo" poisoning both used floating refs as their entry point — branches in some cases, force-moved tags in others.

**Fix:** Run `pinact run` (`brew install pinact`). It rewrites every `uses:` to `<repo>@<sha> # <tag-or-branch-at-resolve-time>` in place. Branch pins resolve to whatever commit the branch currently points at — pair the fix with a deliberate review of the action's recent commit history before merging.

**Exceptions:**
- Reusable workflows from the same repo (`./.github/workflows/reusable.yml`) — these resolve to the calling commit, not to a moving ref. Not a finding.
- First-party-org actions are **not** softened. An action owned by your own org pinned to `@master` is treated the same as a third-party action pinned to `@master`: critical. Trust does not change the mechanism by which a compromised commit ships.

**Companion:** `repo-settings-checklist.md` item 2 (`sha_pinning_required`). Enabling that setting after every workflow's `uses:` is on a SHA guarantees no future PR can reintroduce a tag or branch pin.

## 2. Workflow-level `permissions:`

**Detection:** workflow file has no top-level `permissions:` block.

```bash
for f in .github/workflows/*.yml; do
  grep -q '^permissions:' "$f" || echo "MISSING: $f"
done
```

**Severity:** medium

**Why:** Without explicit `permissions:`, the workflow inherits repo defaults. Repo defaults vary — some orgs default to write-all on `GITHUB_TOKEN`. Least-privilege is `contents: read` at workflow level, with per-job overrides.

**Fix:**
```yaml
permissions:
  contents: read
```

Then expand per-job as needed (`pages: write`, `id-token: write`, `pull-requests: write`).

**Companion:** `repo-settings-checklist.md` item 1 (`default_workflow_permissions`). Setting that to `read` ensures workflows without an explicit `permissions:` block still default to least-privilege.

## 3. `actions/checkout` Credentials

**Detection:** any `actions/checkout` step without `persist-credentials: false`, in a workflow that does NOT run `git push`.

**Severity:** medium

**Why:** By default, `actions/checkout` writes `GITHUB_TOKEN` into `.git/config`. Subsequent steps and third-party actions can `cat .git/config` or `git config --get` to read it.

**Fix:**
```yaml
- uses: actions/checkout@<sha>
  with:
    persist-credentials: false
```

**Exceptions:**
- Workflows that perform `git push` (gh-pages deploy via push, automated commits).
- Workflows that explicitly need git remote auth in later steps.

To check if a workflow pushes: `grep -E 'git push|git commit.*push' <workflow.yml>`.

## 4. `pull_request_target` Trigger

**Detection:**
```bash
grep -l 'pull_request_target' .github/workflows/*.yml
```

**Severity:** depends on workflow body.

- **Critical** — workflow does `actions/checkout` of the PR ref (`ref: ${{ github.event.pull_request.head.ref }}` or `head.sha`) AND runs PR-supplied code (install, build, test, custom scripts). This is the "Pwn Request" pattern from TanStack.
- **High** — workflow does `actions/checkout` of the PR ref but only runs trusted actions (no install of PR-supplied package.json). Still risky if any of those actions execute repo files.
- **Safe / informational** — workflow only reads labels, posts comments, calls `dependabot/fetch-metadata`, runs `gh pr merge`, etc., with no PR-code execution.

**Why:** `pull_request_target` runs in the BASE repo context with secrets and write tokens. Checking out and running PR-supplied code in that context = arbitrary code execution with repo privileges. The TanStack attack chain started here.

**Fix (critical case):** Split into two workflows:
- A `pull_request` workflow that runs the untrusted PR code without secrets / with read-only token.
- A `pull_request_target` workflow that handles labels/comments without checkout.

**Fix (safe case):** Add a comment on the trigger line explaining why this is safe.
```yaml
# Safe: no checkout, no PR code execution. Only reads dependabot metadata
# and calls gh pr merge.
on: pull_request_target
```

## 5. Cache Scoping

**Detection:** `actions/cache` step with a key string that lacks `${{ github.sha }}`, `${{ hashFiles(...) }}`, or another high-entropy component.

**Severity:** medium

**Why:** Cache scope is the whole repo. A low-entropy key (`key: deps-${{ runner.os }}`) lets one workflow run pollute the cache that another, privileged workflow restores. This is the bridge the TanStack attack used between the fork PR and the release workflow.

**Fix:** Add `github.sha` or `hashFiles('**/lockfile')` to the cache key.
```yaml
key: deps-${{ runner.os }}-${{ hashFiles('pnpm-lock.yaml') }}-${{ github.sha }}
```

## 6. OIDC (`id-token: write`)

**Detection:** workflow declares `permissions: id-token: write`.

**Severity:** informational — but cross-check.

**Why:** OIDC tokens are exchangeable for credentials at npm (Trusted Publishers), AWS, GCP, Vault, etc. Restrict to the smallest possible workflow scope.

**Fix:** Move `id-token: write` from workflow level to the specific job that publishes/deploys. Confirm test/lint workflows do not request it.

## 7. Third-Party Action Sources

**Detection:** `uses:` entries not in `actions/*` and not in the project's own org.

```bash
grep -hE 'uses: [^@]+@' .github/workflows/*.yml \
  | sed 's|.*uses: ||;s|@.*||' \
  | grep -v '^actions/' \
  | sort -u
```

**Severity:** informational — list them.

**Why:** Each non-first-party action is a trust dependency. Reviewing the list periodically catches "we depend on actions from a one-person repo with no maintainer activity."

**Fix:** For each entry, decide: keep, replace, or move to a vendored copy. Always SHA-pin (item 1).

## 8. Push-Triggered Deploys Holding Secrets

**Detection:** a job references deploy-provider secrets (`secrets.CLOUDFLARE_*`, `secrets.VERCEL_*`, `secrets.AWS_*`, …) in a workflow triggered by `push:` with a broad branch filter, and the job declares no `environment:`.

**Severity:** critical for production deploy targets.

**Why:** push-event workflows execute the workflow file from the pushed ref — any branch push can rewrite the workflow and use repository-level secrets, including deploying that branch over production. Repository-level secrets are readable from every branch's workflow; only environment secrets can be branch-restricted.

**Fix:** split the workflow into an uncredentialed `build` job (all branches) and a `deploy` job gated to the production branch and attached to a branch-restricted environment. Full remediation order (environment creation before workflow reference, write-only secret migration, repo-level secret deletion) lives in `repo-settings-checklist.md` item 10 — the settings auditor owns it; report the workflow-side finding and cross-reference.

## 9. Workflow Static Analysis in CI

**Detection:** no workflow in `.github/workflows/` runs a workflow linter over the workflows themselves. Grep for `zizmor` (the `zizmorcore/zizmor-action` action, or a `docker run … ghcr.io/zizmorcore/zizmor` step).

**Severity:** medium.

**Why:** items 1–8 are exactly what a workflow linter enforces, and a one-off audit does not prevent regression. Without a linter in CI, the next PR can reintroduce a tag-pinned `uses:`, a `pull_request_target` checkout, or a template-injection sink, and nothing fails. This is the difference between "hardened today" and "stays hardened."

**Fix:** run it locally first and clear the findings:

```bash
docker run --rm -t -v "$(pwd):/repo:ro" ghcr.io/zizmorcore/zizmor:latest /repo/.github/workflows
```

Then add a workflow that keeps it enforced. `repo-hardening` Step 3 applies this file:

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
      - uses: actions/checkout@<sha> # pin per item 1
        with:
          persist-credentials: false
      - uses: zizmorcore/zizmor-action@<sha> # pin per item 1
        with:
          advanced-security: false
```

Set `advanced-security: false` unless the repo has GitHub Advanced Security — otherwise the SARIF upload step fails.

**Note:** the linter overlaps this checklist but does not replace it. It has no view of repository settings (item 2 of `repo-settings-checklist.md`), release semantics, or package-manager config, and it cannot know which `pull_request_target` uses are intentional.

## 10. Stale Branches Carrying Old Workflow Versions

**Detection:** list branches whose `.github/workflows/` differs from the default branch, oldest first:

```bash
git fetch --all --prune
for b in $(git branch -r --format='%(refname:short)' | grep -v HEAD); do
  if ! git diff --quiet "origin/$(git rev-parse --abbrev-ref origin/HEAD | cut -d/ -f2)" "$b" -- .github/workflows/ 2>/dev/null; then
    echo "$b  $(git log -1 --format=%cs "$b")"
  fi
done
```

For each branch returned, read its workflow files and apply items 1–8. A branch is a finding only when its copy carries a vulnerability the default branch has already fixed.

**Severity:** high when a stale branch carries a `pull_request_target` that checks out PR code, or a credentialed job that has since been split into build/deploy. Medium for unpinned actions or missing `permissions:` only. Informational for a branch merged and pending deletion.

**Why:** hardening the default branch does not retire the old workflow files. Several triggers can still reach a non-default ref — `workflow_dispatch` with a branch selector, `push:` filters that match the stale branch, and a `schedule:` in a workflow file that exists only there. The Nx compromise ran through a workflow version that had already been fixed on the default branch. Long-lived forks and abandoned release branches are the usual carriers.

**Fix:** delete the branch if it is merged or abandoned (`git push origin --delete <branch>`). If it must stay, forward-port the workflow fix to it. A branch ruleset restricting `creation` does not help here — the branch already exists.
