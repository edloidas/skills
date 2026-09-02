---
name: workspace-audit
description: >
  Audit a pnpm 10+ workspace for configuration and monorepo problems: dependency placement,
  workspace protocol usage, hoisting, catalog configuration, build order and build hooks,
  dependency rules, and .npmrc settings that are now defaults. Reads and reports only.
when_to_use: >
  When setting up or cleaning up a pnpm monorepo, diagnosing why a dependency resolves oddly
  across packages, or reviewing `pnpm-workspace.yaml`. Also on "audit the workspace", "check
  the monorepo setup", "pnpm catalog", "hoisting", or when wiring build order through
  Turborepo or Nx.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(pnpm:*) Bash(npm:*) Bash(node:*) Bash(npx:*) Bash(turbo:*) Read Glob Grep
---

# Workspace Audit (pnpm 10+)

## Purpose

Analyze pnpm workspace configuration — dependency placement, workspace protocol and catalog
usage, build hooks, dependency rules, and cargo-culted `.npmrc` settings.

**This skill reads and reports; it never edits the workspace.** Every command below is a read or a
dry run (`pnpm dedupe --check`, `turbo run build --dry-run`, `syncpack list-mismatches`), so no
config file, lockfile, or `node_modules` tree changes. The one command that would write is
`pnpm -r run build` in Step 6 — it is there for a user who asks for it, not for the audit.

Scoped to pnpm 10+ deliberately: catalogs, `allowBuilds`, `minimumReleaseAge` and the rest are
pnpm's own fields, and none of it transfers to npm, yarn or bun. On a repo whose lockfile is
`package-lock.json`, `yarn.lock` or `bun.lock`, say so and stop rather than translating the advice.

Trigger phrases: "workspace audit", "monorepo", "pnpm workspace", "workspaces"

## Workflow

### Step 1: Identify Workspace Type

```bash
cat pnpm-workspace.yaml 2>/dev/null
cat package.json | jq '.packageManager, .engines'
ls -la nx.json turbo.json 2>/dev/null
```

Check the `packageManager` field — it tells you the exact pnpm version. Audit advice below assumes pnpm 10+; call out version-gated settings when the project is on an older minor.

If no `pnpm-lock.yaml` exists, print `Not a pnpm workspace — <lockfile> found.` and stop.

Start a **not-checked list** here and carry it to Step 11. Every step below that cannot run goes
in it with its reason: an absent `.npmrc` or `turbo.json`, a `pnpm` binary too old for a
version-gated field, an `npx` tool (`syncpack`, `madge`) that is not installed or refused to
fetch. A report that names only the findings reads as a full audit of everything else.

Close the step with one line: `Workspace: pnpm 10.28.1, 7 packages (3 apps, 4 libs), turbo.json present, no nx.json.`

### Step 2: Analyze Workspace Structure

```yaml
# Good: Explicit patterns
packages:
  - 'packages/*'
  - 'apps/*'
  - 'tools/*'

# Avoid: Too broad
packages:
  - '**'
```

**Config-only workspace:** A `pnpm-workspace.yaml` without a `packages:` field is valid for single-package projects that still want catalog, overrides, or build hook config.

### Step 3: Check Workspace Protocol Usage

**Good:**
```json
{
  "dependencies": {
    "@myorg/shared": "workspace:*",
    "@myorg/utils": "workspace:^"
  }
}
```

**Audit:** flag a hardcoded version (`"^1.0.0"`) on an *internal* package — it should be
`workspace:*`. Third-party deps are Step 5's rule, not this one.

```bash
# Find all package.json files and check for org-scoped internal refs
fd -t f 'package.json' packages apps | xargs grep -l '@myorg/'
```

### Step 4: Check Dependency Hoisting

Pnpm uses isolated `node_modules` by default — no hoisting. Check `.npmrc` for overrides:

```ini
hoist=true            # enables hoisting to .pnpm/node_modules
shamefully-hoist=true # makes node_modules flat like npm — last resort
```

**Audit:** `shamefully-hoist=true` is a red flag. It bypasses pnpm's isolation model. Should only be present if a specific tool requires it, with a comment explaining why.

```bash
pnpm dedupe --check
```

### Step 5: Check Catalog Configuration

#### Catalog definition
```yaml
# pnpm-workspace.yaml
catalog:
  react: ^19.0.0
  react-dom: ^19.0.0
  typescript: ^5.0.0
  vite: ^6.0.0
  vitest: ^3.0.0

  # npm: prefix aliases a name to a different package implementation
  # vite: npm:@org/custom-vite-fork@^1.0.0
```

#### Usage in packages
```json
{
  "dependencies": { "react": "catalog:", "react-dom": "catalog:" },
  "devDependencies": { "vite": "catalog:", "vitest": "catalog:", "typescript": "catalog:" }
}
```

#### Audit checks

**The rule: a third-party dep used by two or more packages is declared once in the catalog and
referenced as `catalog:` everywhere.** A hardcoded version in an individual package is the finding.

- `catalogMode: force` (10.12.1+) makes pnpm enforce that rule at install time. Flag it as unset
  wherever a shared dep exists.
- Avoid `@latest` in catalog entries — defeats reproducibility and conflicts with `minimumReleaseAge`
- `npm:` aliases must be intentional and version-pinned (not `@latest`)
- `cleanupUnusedCatalogs: true` (10.15+) — automatically removes stale catalog entries on install; flag if catalog has grown large and this is not set

### Step 6: Check Build Order

Verify cross-package dependencies are declared:

```json
{
  "name": "@myorg/app",
  "dependencies": {
    "@myorg/ui": "workspace:*",
    "@myorg/utils": "workspace:*"
  }
}
```

```bash
turbo run build --dry-run   # if Turbo is used — prints the order, builds nothing
pnpm -r ls --depth -1       # topological package list
```

`pnpm -r run build` proves the order end to end but writes build output, so the audit does not run
it. Offer it as a follow-up when the declared graph looks wrong.

### Step 7: Check Build Hook Configuration

Build hook config belongs in `pnpm-workspace.yaml`, **not** `package.json`.

#### pnpm 10.0–10.25

```yaml
# Blacklist: skip post-install scripts for these
ignoredBuiltDependencies:
  - unrs-resolver
  - sharp

# Whitelist: only these packages may run post-install scripts
onlyBuiltDependencies:
  - esbuild
```

Don't use both together — pick the model that fits the project's security posture.

#### pnpm 10.26+ — `allowBuilds`

Replaces `ignoredBuiltDependencies` and `onlyBuiltDependencies` with a single explicit map:

```yaml
allowBuilds:
  esbuild: true
  unrs-resolver: false
  sharp: false
```

#### `strictDepBuilds` (10.3+)

Fails the install if any dependency tries to run a build script that isn't covered by the allow/ignore config:

```yaml
strictDepBuilds: true
```

**Audit:** If neither `onlyBuiltDependencies` / `allowBuilds` nor `strictDepBuilds` is set, build scripts run unchecked — flag as a supply-chain risk.

### Step 8: Check Dependency Rules

All of these belong in `pnpm-workspace.yaml`.

#### minimumReleaseAge (10.16+) / minimumReleaseAgeExclude (10.17+)

Prevents installing packages published less than N minutes ago:

```yaml
minimumReleaseAge: 1440  # 24 hours

minimumReleaseAgeExclude:
  - '@typescript/native-preview'  # bleeding-edge, exempt by design
```

Audit: missing entirely is a risk signal. `1440` (24h) is a reasonable default.

#### trustPolicy (10.21+)

Enforces publisher trust levels — complements `minimumReleaseAge` with a signature/provenance check:

```yaml
trustPolicy: audit       # audit | warn | off

trustPolicyExclude:      # (10.22+) exempt specific packages
  - '@myorg/internal'

trustPolicyIgnoreAfter: 525600  # (10.27+) ignore trust for packages older than 1 year
```

Audit: flag if `trustPolicy` is absent and the project has `minimumReleaseAge` set — both are supply-chain controls that complement each other.

#### blockExoticSubdeps (10.26+)

Restricts git, file, and URL dependencies to direct dependencies only — prevents transitive exotic sources:

```yaml
blockExoticSubdeps: true
```

Audit: flag if git or file deps appear in the dependency tree and this is not enabled.

#### overrides

Pin or replace transitive dependency versions, including `catalog:` references:

```yaml
overrides:
  vite: 'catalog:'    # force transitive consumers to use the catalog version
  vitest: 'catalog:'
  lodash: '^4.17.21' # pin vulnerable transitive dep
```

Audit: check for outdated pinned versions, or missing overrides where catalog versions are inconsistent across the dep tree.

#### peerDependencyRules

Suppress spurious peer dep warnings — common with custom toolchain forks:

```yaml
peerDependencyRules:
  allowAny:
    - vite
    - vitest
  allowedVersions:
    vite: '*'
    vitest: '*'
```

Audit: flag `allowAny: ['*']` — that's too broad. Specific package names are fine.

### Step 9: Check .npmrc

Most `.npmrc` settings commonly copy-pasted into projects are redundant defaults or belong elsewhere:

| Setting | Issue |
|---|---|
| `auto-install-peers=true` | Default in pnpm 9+ — redundant |
| `prefer-frozen-lockfile=true` | Default in pnpm 10 — redundant; use `--frozen-lockfile` CLI flag in CI for hard-fail behavior |
| `prefer-workspace-packages=true` | Superseded by `workspace:` protocol |
| `strict-peer-dependencies=true` | Not default; use only if you want hard failures on peer mismatches — evaluate per-project |

**Audit: flag `.npmrc` entries that are no-ops or have better homes.**

Valid reasons to use `.npmrc`:
```ini
# Private registry for scoped packages
@myorg:registry=https://npm.myorg.com/

# Windows cross-platform script compatibility
shell-emulator=true
```

### Step 10: Check for Common Issues

Both tools below are fetched by `npx` and may be unavailable offline or blocked by a registry
policy. Run each, and put any that does not run on the not-checked list with its reason —
`syncpack` and `madge` cover findings no other step produces, so a silent skip leaves a gap the
report would otherwise appear to have covered.

#### Inconsistent dep versions (not in catalog)
```bash
npx syncpack list-mismatches
```

#### Circular dependencies
```bash
npx madge --circular packages/*/src
```

#### Stale catalog entries
Set `cleanupUnusedCatalogs: true` in `pnpm-workspace.yaml`, or run:
```bash
pnpm install  # removes stale entries if cleanupUnusedCatalogs is enabled
```

### Step 11: Generate Report

One section per step group, `[x]` for what holds and `[ ]` for each finding, then a numbered
**Recommendations** list ordered worst-first, then **Not checked** — one line per entry on the
list started in Step 1, with its reason.

A filled report:

```markdown
## Workspace Audit Report

### Structure
- pnpm 10.28.1 (`packageManager`), 7 packages (3 apps, 4 libs), turbo.json present

### Workspace Protocol
- [x] `workspace:*` on 11 of 13 internal refs
- [ ] `apps/web/package.json` and `apps/docs/package.json` pin `@acme/ui: "^2.1.0"` — a published
      version, so a local edit to `packages/ui` is not picked up. Use `workspace:*`

### Catalog
- [x] `react`, `react-dom`, `typescript`, `vitest` declared once and referenced as `catalog:`
- [ ] `vite` is `^7.0.0` in `apps/web` and `^7.1.2` in `apps/docs` — shared, so it belongs in the
      catalog
- [ ] `catalogMode` unset — nothing stops the next package from hardcoding a catalogued dep

### Build Hooks
- [x] `onlyBuiltDependencies: [esbuild, sharp]` in `pnpm-workspace.yaml`
- [ ] pnpm is 10.28, so `onlyBuiltDependencies` is the legacy split key. Migrate to `allowBuilds`
      (`pnpx codemod run pnpm-v10-to-v11`) before the v11 bump removes it
- [ ] `strictDepBuilds` unset — a new dependency requesting a build script is skipped silently

### Dependency Rules
- [ ] `minimumReleaseAge` unset — a package published 40 seconds ago installs. Set `1440`
- [ ] `trustPolicy` unset
- [x] `overrides` pins `vite` and `vitest` to `catalog:`
- [ ] `blockExoticSubdeps` unset while `packages/legacy` pulls a `git:` transitive dep

### Configuration
- [ ] .npmrc sets `prefer-frozen-lockfile=true` (pnpm 10 default) and
      `auto-install-peers=true` (pnpm 9+ default) — both no-ops, delete them
- [x] `@acme:registry=https://npm.acme.dev/` is a legitimate .npmrc entry

### Recommendations
1. Set `minimumReleaseAge: 1440` and `trustPolicy: audit` in `pnpm-workspace.yaml`
2. Enable `strictDepBuilds: true` and migrate to `allowBuilds`
3. Move `vite` into the catalog and set `catalogMode: force`
4. Replace the two hardcoded `@acme/ui` versions with `workspace:*`
5. Enable `blockExoticSubdeps: true` once the `git:` transitive dep in `packages/legacy` is gone
6. Delete the two redundant .npmrc lines

### Not checked
- Circular dependencies — `npx madge` could not fetch; the registry is behind a proxy
- Build order — no `nx.json`, and `turbo run build --dry-run` needs an install this audit
  does not perform
```

Then stop. Report the findings; do not edit `pnpm-workspace.yaml`, a `package.json`, or .npmrc,
and do not run `pnpm install` or `pnpm dedupe` without `--check`.

See `references/workspace-template.md` for an optimized pnpm-workspace.yaml template.
