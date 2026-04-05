---
name: workspace-audit
description: Analyze pnpm 10+ workspace configuration and monorepo setup for optimization
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash(pnpm:*) Bash(npm:*) Bash(node:*) Bash(npx:*) Bash(turbo:*) Read Glob Grep
---

# Workspace Audit (pnpm 10+)

## Purpose

Analyze pnpm monorepo workspace configuration to:
- Optimize dependency management
- Check workspace protocol and catalog usage
- Audit build hook and dependency rule configuration
- Identify cargo-culted or outdated settings

## When to Use This Skill

Use when the user asks to:
- "Audit my monorepo"
- "Check workspace configuration"
- "Optimize pnpm workspace"
- "Review monorepo setup"

Trigger phrases: "workspace audit", "monorepo", "pnpm workspace", "workspaces"

## Workflow

### Step 1: Identify Workspace Type

```bash
cat pnpm-workspace.yaml 2>/dev/null
cat package.json | jq '.packageManager, .engines'
ls -la nx.json turbo.json 2>/dev/null
```

Check the `packageManager` field — it tells you the exact pnpm version. Audit advice below assumes pnpm 10+; call out version-gated settings when the project is on an older minor.

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

**Audit:**
- Flag hardcoded versions (`"^1.0.0"`) for internal packages — should use `workspace:*`

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
- All shared deps should use `catalog:`, not hardcoded versions in individual packages
- Avoid `@latest` in catalog entries — defeats reproducibility and conflicts with `minimumReleaseAge`
- `npm:` aliases must be intentional and version-pinned (not `@latest`)
- `catalogMode: force` (10.12.1+) — enforces that all packages use `catalog:` for any dep in the catalog; flag if shared deps exist but this is not enabled
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
pnpm -r run build        # respects topological order
turbo run build --dry-run  # if Turbo is used
```

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

```markdown
## Workspace Audit Report

### Structure
- pnpm version: 10.x
- Packages: 5 (3 apps, 2 libs)

### Workspace Protocol
- [x] workspace:* used for all internal deps
- [ ] 2 packages use hardcoded versions for internal deps

### Catalog
- [x] Shared deps pinned in catalog
- [ ] @latest used in 1 catalog entry — defeats reproducibility
- [ ] catalogMode not set — consider force to enforce catalog usage

### Build Hooks
- [x] onlyBuiltDependencies configured in pnpm-workspace.yaml
- [ ] Build hook config found in package.json — move to pnpm-workspace.yaml
- [ ] strictDepBuilds not set — unchecked build scripts

### Dependency Rules
- [ ] minimumReleaseAge not set (supply-chain risk)
- [ ] trustPolicy not set (complements minimumReleaseAge)
- [x] overrides pin transitive deps to catalog versions
- [ ] blockExoticSubdeps not set — exotic transitive sources unchecked

### Configuration
- [x] .npmrc is minimal — no cargo-culted settings
- [ ] prefer-frozen-lockfile=true in .npmrc — already the default, remove it

### Recommendations
1. Set minimumReleaseAge: 1440 in pnpm-workspace.yaml
2. Set trustPolicy: audit alongside minimumReleaseAge
3. Move build hook config from package.json to pnpm-workspace.yaml
4. Enable strictDepBuilds: true
5. Replace hardcoded internal dep versions with workspace:*
```

See `references/workspace-template.md` for an optimized pnpm-workspace.yaml template.

## Keywords

pnpm, workspace, monorepo, dependencies, hoisting, catalog, turbo, nx
