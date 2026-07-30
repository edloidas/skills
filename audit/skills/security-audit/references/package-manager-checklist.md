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

## 5. minimumReleaseAgeExclude (owned scopes only)

The release-age gate blocks new versions of every package equally, including the team's own internal libraries. For workspaces that publish their own scoped packages, every release of an internal lib is invisible to consumers for 3 days. The exclude list bypasses the gate for trusted scopes — but **only for the team's own org scopes**, never for arbitrary `@scope/*` deps the audit happens to see.

**Owned scope detection.** The audit defines "owned scope" deterministically:

1. Read `name:` from the workspace root `package.json`. If it is `@<prefix>/<pkg>`, the owned prefix is `<prefix>`.
2. Owned scope patterns are `@<prefix>/*` AND any scope matching `@<prefix>-*/*` (so for `enonic`, both `@enonic/*` and `@enonic-types/*`, `@enonic-cli/*` are owned).
3. Already-covered scopes are anything appearing in `minimumReleaseAgeExclude` (pnpm), `minimumReleaseAgeExcludes` (bun), `registries:`/`[install.scopes]`, or `@scope:registry=` in `.npmrc` — these are user-approved and never flagged.

If the workspace root has no scoped name, no owned scopes are detected and items 5–6 emit nothing. Maximum security default: every `@scope/*` package in the lockfile stays under the release-age and dependency-confusion gates.

**Known limitation — owned-scope derivation is narrow by design.** Deriving owned scopes only from `package.json#name` gives clean false-negatives in three cases:

- **Monorepos that publish to multiple unrelated scopes** (e.g., `@my-org/*` for libs and `@my-org-internal/*` for tooling) — only the root-package scope is detected.
- **Repos mid-migration between org names** — the old scope's packages may still be in the lockfile but the root name has moved to the new scope.
- **Repos with an unscoped root name that legitimately own a scope** (e.g., a starter repo that publishes scoped libs from `packages/*`).

In those cases the audit will miss owned scopes and recommend nothing for them. The recovery path is intentional and lightweight: the user manually adds the missing scopes to `minimumReleaseAgeExclude` and `registries:`/`[install.scopes]`. Once present in those configs, the next audit run picks them up as already-covered scopes and the false-negative goes away. The audit accepts this trade-off to avoid the much louder false-positive of flagging every `@types/*` / `@biomejs/*` scope as needing registry config.

### 5a. pnpm

**Detection:** for each owned scope pattern with packages in `pnpm-lock.yaml`, check that `pnpm-workspace.yaml` includes it in `minimumReleaseAgeExclude`.

```yaml
# pnpm-workspace.yaml
minimumReleaseAge: 4320
minimumReleaseAgeExclude:
  - '@enonic/*'
  - '@enonic-types/*'
  - 'react@^19.0.0'   # also accepts name@range; only add public packages here intentionally
```

**Severity:** **medium** if an owned scope has packages in the lockfile but no matching exclude entry; **pass** otherwise. Non-owned scopes never trigger this finding.

**Why:** Without the exclude, the team will paper over the gate by lowering `minimumReleaseAge` repo-wide or by manually deleting the lockfile entry each time — both undo item 4. The "owned scope" gating prevents accidental allowlisting of every dep that happens to share an `@scope/` prefix with public packages.

### 5b. bun

**Field is plural:** `install.minimumReleaseAgeExcludes` (note the `-s`). Same owned-scope gating as pnpm.

```toml
# bunfig.toml
[install]
minimumReleaseAge = 259200
minimumReleaseAgeExcludes = ["@enonic/*", "@enonic-types/*"]
```

## 6. Registry Scope Mapping (Dependency Confusion, owned scopes only)

Same gating as item 5: the audit only flags **owned scopes** (matching `@<prefix>/*` or `@<prefix>-*/*` from the workspace's own `package.json` name) that lack a registry mapping. Public scopes like `@types/*` are never findings here — they correctly resolve from the default registry.

If the workspace has no scoped name, this item emits nothing.

### 6a. pnpm

**Field:** `registries` in `pnpm-workspace.yaml`.

```yaml
registries:
  default: https://registry.npmjs.org/
  '@enonic': https://npm.enonic.example/
```

**Severity:** **high** if an owned scope has packages in the lockfile and no mapping exists; **pass** otherwise.

**Why:** A 2021 dependency-confusion attack on Apple, PayPal, and others worked by publishing a public package with the same name as an internal scoped package. Without explicit scope→registry mapping for the team's own scopes, package managers may resolve from whichever registry returns first — usually the public one, which the attacker controls.

### 6b. bun

bun uses the historical `.npmrc` or `bunfig.toml` `[install.scopes]` for per-scope registry mapping:

```toml
# bunfig.toml
[install.scopes]
"@enonic" = { url = "https://npm.enonic.example/", token = "$NPM_TOKEN_ENONIC" }
```

Same severity and owned-scope gating as pnpm.

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

## 8. Vuln-Override Hygiene (positive signal)

Mature workspaces force-bump transitive deps past known CVE ranges using `overrides:` (pnpm-workspace.yaml top-level, or `package.json#pnpm.overrides`). A long override list is a strong indicator of active supply-chain maintenance — surface it as a positive signal, not silence.

**Detection:** count entries whose left-hand side uses range operators. Plain `lodash: '^4.18.0'` is a transitive-dep alignment; `lodash@<4.17.23: '>=4.18.0'` is a CVE-shape pin (it overrides specifically the vulnerable range).

```bash
yq -r '.overrides // {} | to_entries | .[] | .key' pnpm-workspace.yaml 2>/dev/null \
  | grep -cE '[<>=]|@[<>=]'
```

**Threshold:**
- ≥ 10 CVE-shape entries → emit in the "passes" / "Already hardened" section: `Vuln-override block: N CVE-shape pins in overrides:`.
- < 10 entries → no signal in either direction. A handful of overrides is normal noise.

**What this is NOT.** The audit does not validate the overrides against current CVE databases. That is Dependabot's job — it watches the override list, files PRs to bump it, and reports vulnerable versions still in resolution. The audit's job here is just to recognize that the team has a maintained block, so the report doesn't read identically for "40 careful CVE pins" and "no overrides at all."

**Companion:** `release-checklist.md` item 7 (`dependabot.yml` ecosystem coverage). The override block is only useful when paired with Dependabot watching the npm ecosystem.

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
