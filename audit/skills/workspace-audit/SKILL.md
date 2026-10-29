---
name: workspace-audit
description: >
  Audit a pnpm 10+ workspace for configuration and monorepo problems: dependency placement,
  workspace protocol usage, hoisting, catalog configuration, build order, overrides and
  peer-dependency rules, and .npmrc settings that are now defaults. Reads and reports only.
when_to_use: >
  When setting up or cleaning up a pnpm monorepo, diagnosing why a dependency resolves oddly
  across packages, or reviewing `pnpm-workspace.yaml`. Also on "audit the workspace", "check
  the monorepo setup", "pnpm catalog", "hoisting", or when wiring build order through
  Turborepo or Nx.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(pnpm dedupe --check) Bash(pnpm -r ls:*) Bash(turbo run build --dry-run:*) Bash(npx syncpack list-mismatches:*) Bash(npx madge --circular:*) Read Glob Grep
---

# Workspace Audit (pnpm 10+)

## Purpose

**This skill reads and reports; it never edits the workspace.** Every command below is a read or a
dry run (`pnpm dedupe --check`, `turbo run build --dry-run`, `syncpack list-mismatches`), so no
config file, lockfile, or `node_modules` tree changes. The one command that would write is
`pnpm -r run build` in Step 6 — it is there for a user who asks for it, not for the audit.

Scoped to pnpm 10+ deliberately: catalogs, `catalogMode`, `overrides` and the rest are
pnpm's own fields, and none of it transfers to npm, yarn or bun. On a repo whose lockfile is
`package-lock.json`, `yarn.lock` or `bun.lock`, say so and stop rather than translating the advice.

Supply-chain fields belong to `security-audit`, which grades them against its own floor:
build-script allowlists (`allowBuilds`, the 10.0–10.25 split keys), `strictDepBuilds`, `minimumReleaseAge`,
`trustPolicy`, and `blockExoticSubdeps`. Do not grade them here; Step 1 records which are set.

## Workflow

Done means: the Step 10 report is printed, with every step either reported or listed under
**Not checked** — or Step 1 printed `Not a pnpm workspace` and stopped.

Steps 2–9 each close with one line carrying their counts, such as `Step 5: 6 shared deps, 1
hardcoded, catalogMode unset.` A step with nothing to check says why in that line.

### Step 1: Identify Workspace Type

Glob the repo root for `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock`, `nx.json`,
and `turbo.json`. If no `pnpm-lock.yaml` exists, print `Not a pnpm workspace — <lockfile> found.`
and stop.

Read `pnpm-workspace.yaml` and the root `package.json`. The `packageManager` field gives the exact
pnpm version; `engines` may pin it too. Audit advice below assumes pnpm 10+; call out version-gated
settings when the project is on an older minor.

Start a **not-checked list** here and carry it to Step 10. Every step below that cannot run goes
in it with its reason: an absent `.npmrc` or `turbo.json`, a `pnpm` binary too old for a
version-gated field, an `npx` tool (`syncpack`, `madge`) that is not installed or refused to
fetch. A report that names only the findings reads as a full audit of everything else.

While reading `pnpm-workspace.yaml`, record which of the supply-chain fields above are set and
which are missing, by key name only. They go under **Handed to security-audit** in the report.

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

Grep every `package.json` under the `packages:` globs for the workspace's own scope (`"@myorg/`),
and flag each hit whose range does not start with `workspace:`.

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

#### Audit checks

**The rule: a third-party dep used by two or more packages is declared once in the catalog and
referenced as `catalog:` everywhere.** A hardcoded version in an individual package is the finding.

- `catalogMode: force` (10.12.1+) makes pnpm enforce that rule at install time. Flag it as unset
  wherever a shared dep exists.
- Avoid `@latest` in catalog entries — defeats reproducibility and conflicts with `minimumReleaseAge`
- `npm:` aliases must be intentional and version-pinned (not `@latest`)
- `cleanupUnusedCatalogs: true` (10.15+) — automatically removes stale catalog entries on install; flag if catalog has grown large and this is not set

### Step 6: Check Build Order

Verify cross-package dependencies are declared as `workspace:*` (Step 3's shape) in each consumer:

```bash
turbo run build --dry-run   # if Turbo is used — prints the order, builds nothing
pnpm -r ls --depth -1       # topological package list
```

`pnpm -r run build` proves the order end to end but writes build output, so the audit does not run
it. Offer it as a follow-up when the declared graph looks wrong.

### Step 7: Check Dependency Rules

Both belong in `pnpm-workspace.yaml`.

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

### Step 8: Check .npmrc

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

### Step 9: Check for Common Issues

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
For each key under `catalog:` and each named catalog, grep the workspace's `package.json` files for
`"<key>": "catalog:`. A key nothing references is stale. Recommend `cleanupUnusedCatalogs: true`,
which prunes such keys on the user's next install — the audit does not run that install.

### Step 10: Generate Report

One section per step group, `[x]` for what holds and `[ ]` for each finding, then a numbered
**Recommendations** list ordered worst-first, then **Handed to security-audit**, then **Not checked** — one line per entry on the
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

### Dependency Rules
- [x] `overrides` pins `vite` and `vitest` to `catalog:`
- [ ] `peerDependencyRules.allowAny: ['*']` — suppresses every peer warning; name the packages

### Configuration
- [ ] .npmrc sets `prefer-frozen-lockfile=true` (pnpm 10 default) and
      `auto-install-peers=true` (pnpm 9+ default) — both no-ops, delete them
- [x] `@acme:registry=https://npm.acme.dev/` is a legitimate .npmrc entry

### Recommendations
1. Replace the two hardcoded `@acme/ui` versions with `workspace:*`
2. Move `vite` into the catalog and set `catalogMode: force`
3. Replace `allowAny: ['*']` with the packages that need it
4. Delete the two redundant .npmrc lines

### Handed to security-audit
- Set: `onlyBuiltDependencies`. Missing: `minimumReleaseAge`, `strictDepBuilds`, `trustPolicy`.
  Ungraded here — run `security-audit` to grade them

### Not checked
- Circular dependencies — `npx madge` could not fetch; the registry is behind a proxy
- Build order — no `nx.json`, and `turbo run build --dry-run` needs an install this audit
  does not perform
```

Then stop. Report the findings; do not edit `pnpm-workspace.yaml`, a `package.json`, or .npmrc,
and do not run `pnpm install` or `pnpm dedupe` without `--check`.

See `references/workspace-template.md` for an optimized pnpm-workspace.yaml template.
