# Release Workflow Security Checklist

Detailed criteria for the Release audit subagent.

## 1. Trigger Scope

**Detection:** `release.yml` (or equivalent) triggers on `push: branches:` instead of tags.

**Severity:** critical if it triggers on `main`/`master`; high if a non-default branch.

**Why:** Any commit to the trigger branch becomes a release. There is no human gate between merge and ship. A single bad PR (or a compromised reviewer account) ships to npm immediately.

**Fix:**
```yaml
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
```

## 2. Tag/Commit Precheck

**Detection:** release workflow publishes without verifying the tagged commit is reachable from a trusted branch.

**Severity:** high

**Why:** Without a precheck, anyone with tag-push access can ship arbitrary code by pushing a `v*` tag to any commit (including a force-pushed feature branch). The precheck binds release tags to commits that already passed review on the trusted branches.

**Fix pattern:**
```yaml
jobs:
  precheck:
    runs-on: ubuntu-latest
    outputs:
      allowed: ${{ steps.contains.outputs.allowed }}
    steps:
      - uses: actions/checkout@<sha>
        with:
          fetch-depth: 0
          persist-credentials: false
      - id: contains
        shell: bash
        run: |
          git fetch --quiet origin '+refs/heads/*:refs/remotes/origin/*' || true
          contains="$(git branch -r --contains "${GITHUB_SHA}")"
          if echo "$contains" | grep -Eq '(main|master|[0-9]+\.[0-9]+)$'; then
            echo "allowed=true" >> "$GITHUB_OUTPUT"
          else
            echo "allowed=false" >> "$GITHUB_OUTPUT"
          fi

  publish:
    needs: precheck
    if: needs.precheck.outputs.allowed == 'true'
```

## 3. Frozen Lockfile

**Detection:** install step uses `npm install`, `pnpm install`, `yarn install`, or `bun install` without the frozen/immutable flag.

**Severity:** high in release workflow; medium elsewhere.

**Why:** Without frozen lockfile, the package manager may resolve a different version than what's committed. A compromised or rerouted registry response can swap in malicious code. Frozen lockfile means "exactly the lockfile or fail" — no surprise versions ship.

**Fix:** See `install-flags.md` for the per-manager command.

## 4. `--prod` / Production Flag

**Detection:** install step in a workflow that produces a runtime artifact (Docker runtime layer, deployable bundle, tarball with bundled `node_modules`) that does NOT use `--prod`.

**Severity:** low-medium

**Why:** Runtime artifacts that include devDependencies have a larger attack surface — every dev tool (linters, type checkers, test runners) is reachable code in production. None of it is needed at runtime.

**Fix:** Add `--prod` (or manager equivalent) to the install step in runtime-only contexts. See `install-flags.md`.

**Anti-pattern:** `--prod` in the build step itself. Will break — build needs dev tooling.

**Anti-pattern:** `--prod` in npm publish workflows. Publishing a library does NOT ship `node_modules`; consumers install their own deps. The build before publish needs devDependencies.

## 5. npm Provenance

**Detection:** public npm package published without `--provenance` or via legacy `NPM_TOKEN` instead of Trusted Publishers (OIDC).

**Severity:** medium

**Why:** Provenance binds the published artifact to a specific workflow run, repo, and commit, verifiable via sigstore. Consumers can confirm the published code came from the claimed source.

**Fix:**
- npm CLI: add `--provenance` and use `id-token: write` + Trusted Publishers.
- pnpm: provenance is automatic when OIDC + Trusted Publishers are configured.

**Exception:** Private packages cannot use sigstore provenance — the source repo must be public. For private packages, document this in `release.yml`:
```yaml
# Provenance is disabled because the source repository is private; npm
# provenance via sigstore requires a public GitHub repository.
```

## 6. Token Usage

**Detection:**
- `${{ secrets.NPM_TOKEN }}` referenced in `env:` — acceptable.
- Hardcoded tokens in workflow YAML — critical.
- Tokens accepted as `workflow_dispatch` inputs — high (logged in run history).
- `GH_TOKEN: ${{ github.token }}` for gh-cli operations — acceptable.

**Severity:** critical for hardcoded, high for input-passed, none for properly referenced secrets / OIDC.

**Fix:** Use repo secrets, GitHub App tokens, or OIDC. Never accept tokens as workflow inputs.

## 7. `dependabot.yml` Coverage

**Detection:** `.github/dependabot.yml` does not contain `package-ecosystem: "github-actions"`.

**Severity:** medium

**Why:** Without Dependabot watching actions, SHA pins go stale. Upstream security fixes don't auto-arrive, and a known-vulnerable action version keeps running for months.

**Fix:**
```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  groups:
    actions:
      patterns: ["*"]
```

Grouping into one PR per week keeps noise low while preserving the update cadence.
