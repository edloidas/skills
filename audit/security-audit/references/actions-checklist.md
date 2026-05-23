# GitHub Actions Security Checklist

Detailed criteria for the Actions audit subagent. Each item: detection → severity → why → fix → exceptions.

## 1. SHA Pinning

**Detection:** any `uses:` line where the part after `@` is not a 40-char hex string.

```bash
grep -hE 'uses: [^@]+@' .github/workflows/*.yml \
  | grep -vE '@[a-f0-9]{40}( |$)' \
  | grep -v '^[[:space:]]*#'
```

**Severity:** high

**Why:** Floating tags can be moved by anyone who compromises the upstream action's repo. Both the TanStack npm compromise and the million repo poisoning used tag-floating as their entry point.

**Fix:** Run `pinact run` (`brew install pinact`). It rewrites every `uses:` to `<repo>@<sha> # <tag>` in place.

**Exceptions:**
- Reusable workflows from the same org (`./.github/workflows/reusable.yml` or `<org>/<same-repo>/.github/workflows/...`).
- `actions/*` from GitHub itself — pinning is still recommended but lower priority than third-party actions.

**Companion:** `repo-settings-checklist.md` item 2 (`sha_pinning_required`). Enabling that setting after the per-file pass guarantees no future PR can regress to tag-pinned actions.

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
