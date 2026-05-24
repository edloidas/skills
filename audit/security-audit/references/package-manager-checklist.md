# Package Manager Security Checklist

Detailed criteria for the Package Manager audit subagent. Covers install-time supply-chain controls — which manager, lifecycle script execution, release-age gating, registry scoping, and version pinning.

Only two managers meet the bar for modern supply-chain hardening: **pnpm v10.26+** (v11+ recommended) and **bun**. Everything else (npm, yarn 1, yarn berry) lacks at least one of: per-package lifecycle allowlist, release-age gate, or both. Treat their presence as a finding, not a configuration to tune.

**Severity note.** "Critical" in this checklist is used for two distinct things: (a) currently-exploitable misconfigurations like a downgraded `verifyStoreIntegrity`, and (b) the *absence of a hardening primitive that this audit treats as mandatory* — e.g. running on a manager that has no release-age gate at all. Type (b) is a policy floor, not a CVE rating. Calibrate fixes accordingly: type (a) is "drop everything", type (b) is "schedule the migration this sprint."

Defaults and field names below were verified against the current docs at the time of writing:
- pnpm settings: <https://pnpm.io/settings>
- bun trusted dependencies: <https://bun.sh/guides/install/trusted>
- bun install config: <https://bun.com/docs/runtime/bunfig#install>
- bun security scanner: <https://bun.com/docs/install/security-scanner-api>

## 1. Package Manager Choice

**Detection:**

```bash
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
jq -r '.packageManager // "unset"' package.json 2>/dev/null
```

**Severity:**
- `package-lock.json` (npm) or `yarn.lock` (yarn 1/berry) only — **critical (policy floor)** — see the severity note above; npm and yarn are not exploitable by virtue of being installed, but they cannot satisfy items 3–5 of this checklist, so this audit treats their presence as a non-negotiable migration target
- Multiple lockfiles — **high** (ambiguous source of truth; one will silently drift)
- `pnpm-lock.yaml` or `bun.lock` only — **pass**

**Why:** npm and yarn lack a per-package lifecycle-script allowlist (`allowBuilds` / `trustedDependencies`) and a release-age gate (`minimumReleaseAge`). Both are first-line defenses against the two most common npm-ecosystem supply-chain attacks: malicious postinstall scripts and time-of-publish injection. The TanStack and `eslint-config-prettier` 2025 compromises both relied on victims installing within minutes of publish.

**Fix:**
- npm → pnpm: commit a `pnpm-lock.yaml` via `pnpm import` (reads `package-lock.json`), delete the npm lockfile, add `packageManager: "pnpm@11.x"` to `package.json`.
- yarn → pnpm: `pnpm import` reads `yarn.lock`. Same cleanup.
- npm/yarn → bun: `bun install` reads existing lockfiles. Verify the resulting `bun.lock` and remove the old one.

**Exceptions:** Repos that publish to npm as a library and have no `node_modules` build step (pure source-only packages) carry less install-time risk for their own CI, but their consumers do — so this is still a finding, just deprioritized to **medium**.

## 2. pnpm Version Floor

**Detection (only when `pnpm-lock.yaml` exists):**

```bash
jq -r '.packageManager // "unset"' package.json
# Expect: pnpm@11.x or higher (pnpm@10.26+ minimum)
```

Cross-check `pnpm-workspace.yaml` for the v10-era settings listed at the end of this checklist (item 8).

**Severity:**
- `packageManager` unset, OR pins pnpm `< 10.26` — **high** (no `allowBuilds` available at all)
- Pins pnpm `>= 10.26` but `< 11`, AND legacy keys (`onlyBuiltDependencies` etc.) still present — **medium** (config can drift back to the old split layout)
- Pins pnpm `>= 11.0` — **pass**

**Why:** `allowBuilds` shipped in pnpm v10.26 as the unified replacement for four overlapping v10 settings (`onlyBuiltDependencies`, `neverBuiltDependencies`, `ignoredBuiltDependencies`, `ignoreDepScripts`). v11 *removes* the legacy keys entirely, eliminating the chance that a future config edit reintroduces the split layout — which was opt-out and hard to audit. So v10.26 is the floor for capability; v11 is the floor for not regressing.

**Fix:** Pin the version through Corepack so CI and devs share it:

```json
{
  "packageManager": "pnpm@11.0.0"
}
```

Then run the official migration codemod:

```bash
pnpx codemod run pnpm-v10-to-v11
```

The codemod rewrites the four old keys into `allowBuilds` and moves the result into `pnpm-workspace.yaml`. Review the diff before committing.

**Companion:** item 3 (`allowBuilds`) — on pnpm `< 10.26` the allowlist primitive does not exist; on v10.26 ≤ pnpm `< 11` it exists alongside the legacy keys, which is the failure mode to avoid.

## 3. Lifecycle Script Allowlist

A package that runs `postinstall` runs code on every contributor's laptop and every CI worker, with whatever scope the install user has. Both pnpm v10.26+ and bun deny script execution by default; this section is about whether the *audit log* (the explicit allowlist) exists and whether install **fails closed** when something new wants in.

### 3a. pnpm

**Detection:** `pnpm-workspace.yaml` should contain `allowBuilds` (a map of package matchers → booleans) and pin `strictDepBuilds: true` (default in v11, but pin explicitly so a future downgrade flips it back).

**Default behavior (pnpm v10.26+):** packages not listed in `allowBuilds` are denied script execution. With `strictDepBuilds: true` (v11 default), install **fails non-zero** when an unreviewed dep wants to run scripts; with `false`, pnpm warns and silently skips the script — the dep may then break at runtime in non-obvious ways. So the supply-chain *gate* is on by default; the audit log and the fail-fast behavior are what this finding is about.

**Severity:**
- `strictDepBuilds: false` (explicit downgrade) — **high** — silent skip masks new dep requests; install passes even when a previously-untrusted package starts asking for script execution.
- `allowBuilds` undefined — **medium** — gate is still on (deny-by-default), but there is no written record of which scripts the team has reviewed and approved; the first new dep that needs a build step will break install with no context for the next dev.
- `allowBuilds` has entries with no inline comment justifying each one — **low** — ledger rots; within a quarter nobody remembers why `core-js` was allowed.

**Fix:**

```yaml
# pnpm-workspace.yaml
strictDepBuilds: true
allowBuilds:
  esbuild: true        # build-time native binary; required for vite/tsup
  '@biomejs/biome': true  # native binary
  core-js: false       # famously runs a donation script we do not want
```

Add a one-line comment for every `true`. The comment is the audit log.

### 3b. bun

**Default behavior:** Bun does **not** execute lifecycle scripts (`preinstall`, `install`, `postinstall`) for dependencies by default. Packages must appear in `trustedDependencies` (in `package.json`) **or** in Bun's built-in default allowlist of known-safe packages (`oven-sh/bun/src/install/default-trusted-dependencies.txt`). This means a fresh `bun install` on a typical repo is already in a safe posture.

**Detection:** read `trustedDependencies` from `package.json` and `install.ignoreScripts` from `bunfig.toml`. Cross-reference each entry against Bun's default allowlist.

**Severity:**
- `install.ignoreScripts: true` (full lockdown) — **pass** but verify the build still produces a working artifact; native deps will break.
- `trustedDependencies` lists one or more packages **not** in Bun's default allowlist and without justification comments — **medium** — these are manual trust grants and should be auditable.
- `trustedDependencies` lists packages with justification comments / commit messages — **pass**.
- Neither set, defaults only — **pass** — Bun's default-deny posture covers this.

**Fix (when adding a manual grant):**

```jsonc
// package.json
{
  "trustedDependencies": [
    "sharp"  // native image processing; required by next/image
  ]
}
```

**Maximum lockdown (denies everything, including Bun's default allowlist):**

```toml
# bunfig.toml
[install]
ignoreScripts = true
```

Use only in tightly controlled environments — this breaks any dep that legitimately needs a build step (sharp, esbuild on glibc/musl edge cases, etc.).

## 4. minimumReleaseAge

A 3-day floor is the strongest finding-to-friction ratio in this checklist. Most malicious package releases are detected and unpublished within 24–48 hours; waiting 72h before installing a newly-published version absorbs the entire detection window for free.

This is also where the audit's policy floor differs most visibly from the ecosystem defaults — call it out explicitly when reporting findings.

### 4a. pnpm

**Detection:** `pnpm-workspace.yaml` value of `minimumReleaseAge`. pnpm v11 default is **1440** (24h). The recommended floor is **4320** (72h).

**Severity (policy):**
- Unset on pnpm < 11 (default 0) — **high (policy)** — no protection at all.
- Set to a value below 4320, **including** the v11 default of 1440 — **medium (policy)** — non-trivial protection (24h catches obvious typosquats) but below this audit's 72h floor.
- Set to ≥ 4320 — **pass**.

**Why 4320 specifically:** A short window catches typosquats but misses targeted attacks that ship a clean version, wait for it to be installed, then push a malicious patch. 72h covers most CVE-disclosure-and-takedown cycles. Raising further hits diminishing returns and starts blocking legitimate security patches.

**Fix:**

```yaml
# pnpm-workspace.yaml
minimumReleaseAge: 4320
minimumReleaseAgeStrict: true            # pin defensively — see below
# minimumReleaseAgeIgnoreMissingTime: false  # consider tightening — see below
```

**Two pnpm strictness knobs to know about:**

1. **`minimumReleaseAgeStrict`** — controls fallback behavior when no version satisfies the age constraint. When `true`, resolution fails. When `false`, pnpm falls back to a too-fresh version "so installation can still succeed." Per the docs, this defaults to `true` **only when `minimumReleaseAge` is explicitly configured**, and `false` otherwise. Pin to `true` defensively so a future default change can't quietly flip it.

2. **`minimumReleaseAgeIgnoreMissingTime`** — when `true` (default), pnpm skips the age check for packages whose registry metadata lacks a `time` field. This is the typical state for private registries that don't surface publish timestamps, so internal `@your-org/*` packages bypass the gate silently and implicitly. If you want the bypass to be intentional (only the scopes listed in `minimumReleaseAgeExclude`), set this to `false` — but verify your internal registry actually returns `time`, otherwise installs will fail.

### 4b. bun

**Detection:** `bunfig.toml` value of `install.minimumReleaseAge`. **Note unit difference:** bun is **seconds**, pnpm is **minutes**. Bun has no default (null = disabled). The recommended floor is **259200** (72h in seconds).

**Severity (policy):**
- Unset (default) — **high (policy)**.
- Set below 259200 — **medium (policy)**.
- Set to ≥ 259200 — **pass**.

**Fix:**

```toml
# bunfig.toml
[install]
minimumReleaseAge = 259200
```

Bun does not currently expose `Strict` or `IgnoreMissingTime` equivalents — the gate is best-effort against whatever the registry returns.

**Common Mistake:** copying pnpm's 4320 into bun's setting. 4320 seconds = 72 minutes. That is approximately no protection at all.

## 5. minimumReleaseAgeExclude

The release-age gate blocks new versions of every package equally, including the team's own internal libraries. For workspaces with internal scoped packages (`@your-org/*`), this means every release of an internal lib is invisible to consuming repos for 3 days. Use the exclude list to bypass the gate for trusted scopes.

### 5a. pnpm

**Detection:** if `pnpm-lock.yaml` references a `@scope/*` pattern that matches a private/internal registry (item 6), `pnpm-workspace.yaml` should set `minimumReleaseAgeExclude` to include that scope.

```yaml
# pnpm-workspace.yaml
minimumReleaseAge: 4320
minimumReleaseAgeExclude:
  - '@your-org/*'
  - some-fast-moving-but-trusted-pkg
  - 'react@^19.0.0'   # also accepts name@range
```

**Severity:** **medium** if internal scope is present in lockfile without a matching exclude entry; **pass** otherwise.

**Why:** Without the exclude, the team will paper over the gate by lowering `minimumReleaseAge` repo-wide or by manually deleting the lockfile entry each time — both undo item 4.

### 5b. bun

**Field is plural:** `install.minimumReleaseAgeExcludes` (note the `-s`).

```toml
# bunfig.toml
[install]
minimumReleaseAge = 259200
minimumReleaseAgeExcludes = ["@your-org/*", "@types/bun"]
```

Same severity and fix logic as pnpm.

## 6. Registry Scope Mapping (Dependency Confusion)

**Detection:** if `pnpm-lock.yaml` or `bun.lock` references any `@scope/*` package, the workspace config should map that scope to a specific registry. A missing mapping means pnpm/bun falls back to the public npm registry — the classic dependency confusion vector.

```bash
# Surface scoped deps from lockfiles
grep -hoE '@[a-z0-9-]+/[a-z0-9-]+' pnpm-lock.yaml bun.lock 2>/dev/null | sort -u
```

### 6a. pnpm

**Field:** `registries` in `pnpm-workspace.yaml`.

```yaml
registries:
  default: https://registry.npmjs.org/
  '@your-org': https://npm.your-org.example/
```

**Severity:** **high** if internal-looking scope is in the lockfile and no mapping exists; **pass** otherwise.

**Why:** A 2021 dependency-confusion attack on Apple, PayPal, and others worked by publishing a public package with the same name as an internal scoped package. Without explicit scope→registry mapping, package managers may resolve from whichever registry returns first — usually the public one.

### 6b. bun

bun uses the historical `.npmrc` or `bunfig.toml` `[install.scopes]` for per-scope registry mapping:

```toml
# bunfig.toml
[install.scopes]
"@your-org" = { url = "https://npm.your-org.example/", token = "$NPM_TOKEN_YOUR_ORG" }
```

Same severity and fix logic.

**Companion:** verify the private registry actually requires auth and rejects anonymous reads, otherwise the mapping is cosmetic.

## 7. Defaults Pinning (Defense Against Future Drift)

pnpm and bun ship sensible defaults for several supply-chain settings. Audit only flags **explicit downgrades** — values that override a safe default with a permissive one.

**pnpm — flag any of these:**

| Setting | Safe default | Permissive override |
|---|---|---|
| `verifyStoreIntegrity` | `true` | `false` |
| `blockExoticSubdeps` | `true` | `false` |
| `strictDepBuilds` | `true` (v11+) | `false` |

**bun — note:**

| Setting | Safe default | Notes |
|---|---|---|
| Dependency lifecycle scripts | denied (allowlist + built-in defaults) | covered in item 3b — bun's default is safe |
| `install.ignoreScripts` | `false` | `true` is the safer value if you don't need any scripts |

**Severity:** any explicit downgrade of a pnpm default in the table above is **high**.

**Note on `enablePrePostScripts`:** the pnpm setting `enablePrePostScripts: true` is the default and is sometimes mistaken for a dependency-script control. It is not. It governs whether `pnpm foo` automatically runs `prefoo` / `postfoo` from the **current project's** `package.json` scripts — i.e., user-defined shell-script hooks around `pnpm run` invocations. Dependency build scripts are gated by `allowBuilds` + `strictDepBuilds` (item 3a). Do not treat `enablePrePostScripts` as a supply-chain finding.

**Why:** Most teams won't ever set `verifyStoreIntegrity: false`. When they do, it's usually a stale workaround for a one-off CI issue from years ago, and nobody remembers to flip it back.

## See Also

These are out of scope for this audit but worth knowing:

- **`npm audit signatures`** — verifies sigstore provenance attestations on installed packages. Requires latest npm CLI. pnpm and bun have no direct equivalent; consumers using pnpm/bun for installs cannot currently verify provenance attestations from the install path. Track <https://github.com/pnpm/pnpm/issues/8338> for pnpm progress.
- **`install.security.scanner` (bun)** — plugin model for third-party scanners; auto-disables `auto-install` when set. Ecosystem is young; commercial scanners (Snyk, Socket) ship plugins. Treat as informational until at least one commercial scanner has prod usage in your stack.
- **OpenSSF Scorecard / OSV-Scanner** — out of band scanning that surfaces upstream supply-chain health. Belongs in CI, not in this checklist.

## Quick Audit Block

Run during Step 1 to gather everything the subagent needs:

```bash
# Manager detection
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
jq -r '{packageManager, trustedDependencies}' package.json 2>/dev/null

# pnpm config
cat pnpm-workspace.yaml 2>/dev/null
cat .npmrc 2>/dev/null

# bun config
cat bunfig.toml 2>/dev/null

# Surface scoped deps
grep -hoE '@[a-z0-9-]+/[a-z0-9-]+' pnpm-lock.yaml bun.lock 2>/dev/null | sort -u

# v10 leftovers (only relevant if pnpm)
grep -E 'onlyBuiltDependencies|neverBuiltDependencies|ignoredBuiltDependencies|ignoreDepScripts' \
  pnpm-workspace.yaml package.json .npmrc 2>/dev/null
```
