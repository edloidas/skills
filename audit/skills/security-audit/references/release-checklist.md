# Release Workflow Security Checklist

Detailed criteria for the Release audit subagent.

## 0. Release Target Detection

The audit cares about one question per item: does this release publish to npm? If yes, npm-specific items (provenance, `--prod` in runtime contexts) apply. If no — regardless of whether the alternative is Gradle, Maven, Cargo, goreleaser, a Docker registry, or anything else — those items are silently dropped.

**`release_publishes_to_npm` is `true` if any of these signals exist:**

- A `release.yml` / `release.yaml` in `.github/workflows/` contains a literal `npm publish`, `pnpm publish`, `yarn publish`, or `bun publish` invocation.
- `package.json` has `publishConfig.registry`.
- `package.json` `scripts.publish` value contains any of the four publish commands above.

If none match, the audit treats this repo as a non-npm publisher and skips items 4, 5, and 10 entirely. The remaining items (trigger scope, precheck, frozen lockfile, token usage, dependabot ecosystem coverage, artifact identity, minimal credentialed jobs) apply to any release workflow.

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

**Detection:** release workflow publishes without verifying the tagged commit is reachable from a trusted branch — or a precheck exists but *skips* downstream jobs instead of failing the run.

**Severity:** high if missing; medium for skip-instead-of-fail.

**Why:** Without a precheck, anyone with tag-push access can ship arbitrary code by pushing a `v*` tag to any commit (including a force-pushed feature branch). The precheck binds release tags to commits that already passed review on the trusted branches.

**Skip-to-green is a defect, not a variant.** A precheck that emits an `allowed` output and gates downstream jobs with `if: needs.precheck.outputs.allowed == 'true'` produces a **green workflow** on an ineligible tag — every job "succeeds" by being skipped, and no one is alerted that a release attempt was rejected. The precheck must `exit 1` so the run goes red and downstream jobs fail through `needs`.

**Fix pattern:**
```yaml
jobs:
  precheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
        with:
          fetch-depth: 0          # all branch refs, so --contains sees every branch
          persist-credentials: false
      - shell: bash
        run: |
          contains="$(git branch -r --contains "${GITHUB_SHA}" | sed 's/^[ *]*//')"
          if [ -z "${contains}" ]; then
            echo "::error::Could not resolve any branch containing ${GITHUB_SHA} — refusing to release."
            exit 1
          fi
          if ! echo "${contains}" | grep -Eq '^origin/(main|master|[0-9]+\.[0-9]+)$'; then
            echo "::error::Tag ${GITHUB_REF_NAME} is not on a trusted branch — refusing to release."
            exit 1
          fi

  publish:
    needs: precheck   # precheck failure fails this job too — no `if:` gate
```

Two details that look cosmetic but are not:

- **Anchor the grep.** An unanchored `(main|master|…)$` also matches `origin/hackmain` or `feature/master` — any branch *ending* in a trusted name passes the gate.
- **No `git fetch … || true`.** Checkout with `fetch-depth: 0` already fetched every branch ref; a re-fetch with a swallowed exit code adds nothing and masks failures. If a fetch is genuinely needed, let it fail loudly.

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
- npm CLI with Trusted Publishing: provenance is generated automatically once the job has `id-token: write` — no `--provenance` flag needed. The explicit flag is only required for legacy token-based publishes.
- pnpm: provenance is automatic when OIDC + Trusted Publishers are configured.
- Bun cannot publish via OIDC Trusted Publishing (oven-sh/bun#15601) — Bun-built packages should still publish the packed tarball with the npm CLI.

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

## 8. Artifact Identity — Smoke What Ships

**Applies when the workflow publishes a packed artifact (npm tarball, archive, image).**

**Detection:** the artifact that gets published is not the same bytes that were inspected, tested, or smoked. Common shapes:

- `npm pack` runs after the test suite, and a test rebuilds `dist/` along the way — so the packed output comes from a state no check ever executed.
- The validate job packs one tarball for inspection; the publish job packs a fresh one.
- attw/publint/smoke checks run against the working tree or a rebuilt `dist/`, never against the packed tarball itself.
- Packing runs on whatever npm the runner image ships that week (no pinned `setup-node` before `npm pack`).

**Severity:** medium-high — every upstream check attests to a state of the tree, not to the file that ships.

**Fix pattern:** pack **once** → upload as a workflow artifact → a dedicated smoke job downloads that exact artifact, installs it in a scratch project, and exercises the public entry points (ESM import, `require(esm)` where claimed, installed bin, browser bundle where claimed) → the publish job downloads the same artifact and publishes it verbatim (`npm publish <file>.tgz --ignore-scripts`). Pin the packing toolchain with `setup-node` + explicit `node-version`. The smoke job holds no credentials, so a full dev-dependency install there (e.g. for a lockfile-pinned esbuild) is safe.

**Companion:** item 9 — the publish job stays minimal precisely because smoking happened elsewhere.

## 9. Minimal Credentialed Publish Job

**Detection:** the job holding `id-token: write` or a registry token also runs `actions/checkout`, dependency install, build, or test steps.

**Severity:** medium

**Why:** Everything that executes next to the publishing identity is in the blast radius — dev dependencies, lifecycle scripts, build plugins. A compromised transitive dependency running inside the credentialed job can publish arbitrary code; the same compromise in an uncredentialed job cannot.

**Fix:** the publish job should contain exactly: registry auth setup (`setup-node` with `registry-url`), artifact download, and the publish command with `--ignore-scripts`. No checkout, no install, no cache. All building, checking, and smoking happens in earlier uncredentialed jobs (items 2 and 8).

**Cache is part of this finding.** `actions/setup-node` restores a dependency cache by default when `cache:` is set, and an `actions/cache` step does the same explicitly. Cache scope is the whole repository (see `actions-checklist.md` item 5), so an entry poisoned by a fork PR or a lower-privilege workflow can be restored *inside* the credentialed job. Disable it there:

```yaml
- uses: actions/setup-node@<sha>
  with:
    node-version: 24
    registry-url: https://registry.npmjs.org
    package-manager-cache: false   # slower, but no cache can reach the publish identity
```

A cache miss costs seconds in a job that installs nothing. Flag `cache:` or any `actions/cache` step in the credentialed job as **high** — it reopens the exact bridge item 5 exists to close.

## 10. Publisher-Side Settings (npm)

**Applies when `release_publishes_to_npm` is `true`.** Not auditable via `gh` — these live on npmjs.com's package settings page. Report as ask-the-user verification items:

- **Trusted Publisher pinned exactly** to `owner/repo` + the release workflow filename. A publisher scoped wider than the one workflow widens who can mint publishes.
- **Publishing access** set to *Require two-factor authentication and disallow bypass 2fa tokens* once OIDC is the only publish path. This kills the token fallback entirely and does not affect Trusted Publishing.

**Why:** the tag ruleset and workflow hardening protect the OIDC path, but a leaked legacy automation token bypasses all of it unless token publishing is disallowed registry-side.

## 11. Staged Publishing

**Applies when `release_publishes_to_npm` is `true`.**

**Scope note.** `package-manager-checklist.md` supports pnpm and bun only as *installers*. That has no bearing here. Publishing to the npm registry is in scope for every project, and the publish command should be `npm` even when pnpm or bun installs the tree — one tool in the credentialed job rather than two, and npm is where staged publishing lives. The exception is a project relying on a pnpm-only packing feature (the `workspace:` protocol, a `beforePacking` hook in `.pnpmfile.cjs`); there, use `pnpm publish` and check first that the pinned pnpm version supports staged publishing rather than silently dropping to an unstaged publish.

**Detection:** the publish step runs `npm publish` rather than `npm stage publish`. Also check the npm CLI version the workflow resolves to — staged publishing needs npm >= 11.15.0 and Node >= 22.14.0.

**Severity:**
- `npm publish` where the package's Trusted Publisher is configured stage-only — **high**. The release will be rejected at publish time; this is a broken pipeline as well as a weaker one.
- `npm publish` with no stage-only restriction — **medium (policy)**. Nothing is currently failing, but the release path has no human gate.
- `npm stage publish` present with a stage-only Trusted Publisher — pass.

**Why:** provenance and Trusted Publishing prove *which workflow* produced an artifact. Neither proves the artifact is one a maintainer intended to ship. A compromised CI job — poisoned cache, malicious transitive build dependency, altered workflow on a stale branch — holds a legitimate OIDC identity and can publish immediately. Staged publishing splits that: CI stages the release, and a maintainer approves it with 2FA before it becomes installable. The approval requires proof of presence and cannot use an OIDC token, so it is the one step in the chain that compromised CI cannot forge.

**Fix:** in the workflow, change the publish command:

```yaml
- name: Stage the release
  run: npm stage publish --ignore-scripts
```

`npm stage publish` never prompts for 2FA regardless of token type, so it is safe in a non-interactive job. The maintainer then approves out of band:

```bash
npm stage list                    # see what is waiting
npm stage view <stage-id>         # inspect before approving
npm stage approve <stage-id>      # 2FA; or use Staged Packages on npmjs.com
npm stage reject <stage-id>
```

Every subcommand other than `publish` requires interactive authentication and cannot run from CI — that is the design, not a limitation.

**Registry-side half.** Restricting the Trusted Publisher to stage-only is what makes the control binding; without it, a `npm publish` still succeeds and the stage step is merely a convention. That is a publisher-side setting (item 10) and is applied by `repo-hardening` Step 6, not here. Report it as a paired item: the workflow change and the registry restriction are only useful together.

**Not for every project.** A package with a single maintainer who releases from CI on a tag push gains a real gate. A package with automated dependency-bump releases (changesets, semantic-release on merge) gains a manual step in a flow designed not to have one — say so in the finding rather than recommending it blindly. Note also that `--provenance` and staged publishing are complementary, not alternatives: keep item 5's recommendation either way.
