# Release Workflow Security Checklist

Detailed criteria for the Release audit subagent.

## 0. Release Target Detection

The audit cares about one question per item: does this release publish to npm? If yes, npm-specific items (provenance, `--prod` in runtime contexts) apply. If no — regardless of whether the alternative is Gradle, Maven, Cargo, goreleaser, a Docker registry, or anything else — those items are silently dropped.

**`release_publishes_to_npm` is `true` if any of these signals exist:**

- A `release.yml` / `release.yaml` in `.github/workflows/` contains a literal `npm publish`, `pnpm publish`, `yarn publish`, or `bun publish` invocation.
- `package.json` has `publishConfig.registry`.
- `package.json` `scripts.publish` value contains any of the four publish commands above.

If none match, the audit treats this repo as a non-npm publisher and skips items 4 and 5 entirely. The remaining items (trigger scope, precheck, frozen lockfile, token usage, dependabot ecosystem coverage) apply to any release workflow.

**Build-system list** used by item 7 (`detected_build_systems`) is derived from file presence at repo root:

| File(s) present | Adds to list |
|---|---|
| `package.json` + any lockfile | `npm` (Dependabot covers npm/pnpm/yarn/bun under this token) |
| `build.gradle` or `build.gradle.kts` | `gradle` |
| `pom.xml` | `maven` |
| `Cargo.toml` | `cargo` |
| `requirements.txt` or `pyproject.toml` | `pip` |
| `Dockerfile` | `docker` |
| `.github/workflows/` exists | `github-actions` (always) |

Item 7 then asks: for each detected build system, is the matching Dependabot ecosystem entry present? Missing entries are findings; presence of an entry for a build system that isn't detected is a soft note, not an issue.

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

**Companion:** `repo-settings-checklist.md` item 6 (tag protection ruleset). The trigger scope alone does not prevent attackers from pushing `v*` tags to arbitrary commits; the tag ruleset is what restricts who can create, move, or delete tags in the release namespace.

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

**Applies only when `release_publishes_to_npm` is `true` (see item 0).** For non-npm release models, the npm runtime-artifact concept doesn't apply — skip this item.

**Detection:** install step in a workflow that produces a runtime artifact (Docker runtime layer, deployable bundle, tarball with bundled `node_modules`) that does NOT use `--prod`.

**Severity:** low-medium

**Why:** Runtime artifacts that include devDependencies have a larger attack surface — every dev tool (linters, type checkers, test runners) is reachable code in production. None of it is needed at runtime.

**Fix:** Add `--prod` (or manager equivalent) to the install step in runtime-only contexts. See `install-flags.md`.

**Anti-pattern:** `--prod` in the build step itself. Will break — build needs dev tooling.

**Anti-pattern:** `--prod` in npm publish workflows. Publishing a library does NOT ship `node_modules`; consumers install their own deps. The build before publish needs devDependencies.

## 5. npm Provenance

**Applies only when `release_publishes_to_npm` is `true` (see item 0).** Provenance is an npm-registry feature; for Gradle/Maven/Cargo/Go/Docker publishers, the analogous sigstore concerns differ and are out of scope here.

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

**Detection:** For each entry in `detected_build_systems` (see item 0), the corresponding `package-ecosystem` value must appear in `.github/dependabot.yml`. `github-actions` is always required when `.github/workflows/` exists. The other mappings:

| Detected | Required `package-ecosystem` |
|---|---|
| `npm` (any of npm/pnpm/yarn/bun) | `npm` |
| `gradle` | `gradle` |
| `maven` | `maven` |
| `cargo` | `cargo` |
| `pip` | `pip` |
| `docker` | `docker` |
| always | `github-actions` |

**Severity:** medium for each missing ecosystem entry.

**Why:** Without Dependabot watching a build system, security fixes don't auto-arrive. The most common omission is `github-actions` itself — SHA pins go stale and a known-vulnerable action version keeps running for months. For non-Node projects this audit doesn't otherwise reach, the `gradle`/`maven`/`cargo` entries are the only supply-chain visibility Dependabot provides.

**Special case — Node lockfile without npm publishing:** if a `package.json` + lockfile is present but `release_publishes_to_npm` is false (Node is used only for tooling/build deps, not publication), still require the `npm` ecosystem entry. The lockfile pinning the team's dev tools needs the same security update visibility regardless of whether anything gets published to npm.

**Fix template:**
```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  groups:
    actions:
      patterns: ["*"]

# Add one block per detected build system, e.g.:
- package-ecosystem: "gradle"
  directory: "/"
  schedule:
    interval: "weekly"
```

Grouping into one PR per week keeps noise low while preserving the update cadence.
