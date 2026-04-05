---
name: scripts-audit
description: >
  Analyze package.json scripts for naming, composition, lifecycle hooks,
  consistency, and performance. Use when auditing or designing npm, pnpm,
  or Bun scripts, standardizing script conventions, or checking whether a
  package's public script interface fits its role.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash(jq:*) Read Glob Grep
---

# Scripts Audit

## Purpose

Audit `package.json` scripts to:
- Classify the package with minimal manifest context
- Check whether the script interface fits that package role
- Prefer Vite Plus conventions for app-style repos
- Enforce stable naming and suffix conventions
- Improve composition, CI ergonomics, and performance
- Flag misleading, platform-specific, or overgrown scripts

## When to Use This Skill

Use when the user asks to:
- "Audit my npm scripts"
- "Standardize package.json script names"
- "Decide whether this should be `dev` or `start`"
- "Review build, check, or release scripts"
- "Make root workspace scripts consistent with package scripts"

Trigger phrases: "scripts audit", "package.json scripts", "npm scripts", "pnpm scripts", "bun scripts", "script naming", "script conventions"

## Scope

This is still a **scripts** skill, not a full `package.json` audit.

Read adjacent manifest fields only when they change what "good scripts" means:
- `private`
- `packageManager`
- `workspaces`
- `type`
- `bin`
- `exports`
- `files`
- `engines`

Do **not** drift into dependency hygiene, `exports`, `peerDependencies`, publish metadata, or security scanning unless the user explicitly asks for that broader audit.

## Vite Plus First

If a repo uses `vite-plus`, aliases `vite` to `@voidzero-dev/vite-plus-core`, or invokes `vp` in scripts, treat Vite Plus as the primary app workflow.

Prefer VP-native guidance:
- `build`: `vp run clean && tsgo && vp build`
- `check`: `vp check && vp run typecheck`
- `test`: `vp test --run`
- `test:ci`: `vp test --run --coverage`
- `prepare`: `vp config`

Do not recommend ESLint-specific patterns in this skill. If the repo exposes Biome explicitly, it is fine to mention `biome` scripts as optional non-VP companion scripts, but VP remains the primary app workflow.

## Non-VP Patterns

Non-VP patterns are still worth mentioning when the repo actually uses them:
- Plain `pnpm` script composition is the normal baseline for monorepo roots, publishable libraries, and release flows.
- `biome` scripts are a valid non-VP quality layer, especially in libraries, CLIs, and repos with explicit lint or format commands.
- `prepare: "husky"` is a valid non-VP setup pattern when the repo manages git hooks explicitly.

When VP is detected, do not try to "improve" the repo by replacing VP-native app flows with separate non-VP app scripts unless the user explicitly asks for that direction.

## Workflow

### Step 1: Load Minimal Manifest Context

Read `scripts` plus only the manifest fields that affect script expectations:

```bash
jq '{
  name,
  private,
  packageManager,
  type,
  workspaces,
  bin,
  exports,
  files,
  engines,
  scripts
}' package.json
```

Only inspect `dependencies` or `devDependencies` when they explain a script choice, for example:
- `vite-plus`, `vite` aliased to `@voidzero-dev/vite-plus-core`, `tsgo`, `react` -> Vite Plus app expectations
- `storybook`, `next` -> non-VP app expectations
- `typescript` -> `typecheck`
- `biome`, `prettier`, `husky` -> non-VP quality/setup expectations
- `vitest`, `jest`, `bun:test` -> test naming expectations when the repo is not VP-driven

Extract and categorize scripts by purpose:
- Runtime: `dev`, `start`, `preview`
- Quality: `typecheck`, `lint`, `lint:*`, `format`, `format:*`, `check`, `check:*`
- Build: `build`, `build:*`, `clean`
- Test: `test`, `test:*`, `coverage`
- Release: `prepack`, `prepublishOnly`, `release:*`

### Step 2: Classify Package Role

Use minimal manifest signals to decide what a sensible script surface looks like.

| Role | Typical signals | Script expectations |
|------|------------------|---------------------|
| App | `private: true`, frontend/dev tooling, `vite-plus`, `vp`, `tsgo`, `dev` or `build` | Prefer VP-native `build`, `check`, `test`, `test:ci`, `prepare`; `dev` is recommended, `preview` is optional |
| Monorepo root | `workspaces`, `pnpm --filter`, `turbo`, `nx` | Root scripts should mostly delegate and mirror leaf package names |
| Publishable library | `exports`, `files`, `bin`, not private | `build`, `typecheck`, `lint`, `format:check`, `test`, `prepublishOnly`, optional `size` or `release:dry` |
| Service / bot / CLI | `start` script, runtime entrypoint, maybe private | `start`, `check`, `test`; `build` is optional if runtime executes source directly |

If the package is ambiguous, say so and audit against the closest role instead of inventing missing requirements.

### Step 3: Check Whether the Public Script Interface Fits the Role

Do not demand the same scripts from every package.

#### App

Healthy default surface:

```json
{
  "dev": "vp dev",
  "build": "vp run clean && tsgo && vp build",
  "clean": "rm -rf dist coverage reports",
  "check": "vp check && vp run typecheck",
  "typecheck": "tsgo --noEmit",
  "test": "vp test --run",
  "test:ci": "vp test --run --coverage",
  "prepare": "vp config"
}
```

If the repo is VP-driven, separate `lint`, `lint:fix`, `format`, and `format:check` scripts are optional. Keep them only when they expose distinct Biome behavior the team actually uses.

#### Monorepo root

Root scripts should preserve the same public contract as the main package they expose:

```json
{
  "build": "pnpm --filter @edloidas/example run build",
  "check": "pnpm --filter @edloidas/example run check",
  "test": "pnpm --filter @edloidas/example run test",
  "test:ci": "pnpm --filter @edloidas/example run test:ci",
  "dev": "pnpm --filter @edloidas/example exec vp dev"
}
```

Prefer delegation over re-implementing leaf commands in the root package.

#### Publishable library

Healthy default surface:

```json
{
  "build": "pnpm clean && pnpm build:*",
  "clean": "rm -rf dist coverage",
  "typecheck": "tsc --noEmit",
  "lint": "biome lint .",
  "format:check": "biome format .",
  "test": "vitest run",
  "validate": "pnpm check && pnpm build && pnpm test:ci",
  "prepublishOnly": "pnpm validate"
}
```

#### Service / bot / CLI

Healthy default surface:

```json
{
  "start": "bun src/index.ts",
  "check": "bun run typecheck && bun run lint && bun run format:check",
  "test": "bun test"
}
```

`build` is optional here if the runtime already executes the source directly.

### Step 4: Check Naming Conventions

Prefer a small stable vocabulary of public script names:

| Script | Meaning |
|--------|---------|
| `dev` | Interactive local development server |
| `start` | Runtime entrypoint for an app, service, or CLI |
| `build` | Production or distributable build |
| `clean` | Remove generated artifacts |
| `typecheck` | Static type checking only |
| `lint` | Non-mutating lint pass |
| `lint:fix` | Lint pass with writes |
| `format` | Formatter with writes |
| `format:check` | Formatter verification only |
| `test` | Default test run |
| `test:watch` | Interactive watch mode |
| `test:ci` | Deterministic CI-oriented test run |
| `coverage` | Coverage-focused test run |
| `check` | Fast preflight quality gate |
| `check:fix` | Mutating version of the quality gate |
| `preview` | Preview built output |
| `validate` | Slower release gate |
| `release:dry` | Dry-run publish or release path |

Naming rules:
- Prefer one canonical name per concern. Flag synonyms such as `serve` plus `dev`, or `verify` plus `check`, unless they are clearly different tasks.
- Prefer `action:target:variant`, for example `build:ui:css` or `typecheck:node`.
- `:fix` means mutating, `:check` means verification-only, `:watch` means interactive, `:ci` means deterministic strict mode, and `:dry` means no side effects.
- Root scripts should keep the same public names as leaf scripts when delegating.
- Use `dev` for long-running local development workflows. Use `start` for the runtime entrypoint of a service, bot, or CLI.
- In VP repos, `check` is the primary quality command. Separate `lint` or `format` scripts are optional, not mandatory.
- In non-VP repos, explicit `lint`, `format`, and `format:check` scripts are normal and worth keeping clear.

### Step 5: Check Composition

Leaf scripts should do one job well. Composite scripts should compose those leaf scripts instead of duplicating raw command strings everywhere.

Good composition:

```json
{
  "clean": "rm -rf dist coverage reports",
  "typecheck": "tsgo --noEmit",
  "build": "vp run clean && tsgo && vp build",
  "check": "vp check && vp run typecheck",
  "test": "vp test --run",
  "test:ci": "vp test --run --coverage",
  "prepare": "vp config"
}
```

Guidelines:
- `check` should be the fast, repeatable preflight gate.
- `check:fix` should touch the same surfaces as `check`, but with writes enabled where appropriate.
- `validate` should be the slower gate, usually `check && build && test` or `check && build && test:ci`.
- `prepublishOnly` should usually call `validate` or `release:dry` rather than inventing a separate release path.
- Prefer calling scripts from composite scripts. Avoid copying the same raw command string into multiple places.

Move script logic into `scripts/` files when the command becomes hard to review:
- shell conditionals or loops
- multiple `node -e` or `bun -e` snippets
- cross-platform branching
- long inline smoke tests or packaging logic

### Step 6: Check Consistency and Performance

Look for consistency across related variants:

#### Vite Plus mode pairing

```jsonc
// Good
"check": "vp check && vp run typecheck",
"test": "vp test --run",
"test:ci": "vp test --run --coverage"
```

If a VP repo exposes `test:ci`, it should usually add something CI-specific such as coverage or stricter reporting rather than duplicating `test`.

#### Biome pairing

```jsonc
"lint": "biome check .",
"lint:fix": "biome check --write .",
"format": "biome format --write .",
"format:check": "biome format ."
```

If the repo keeps Biome scripts, related variants should usually target the same scope unless the difference is intentional and documented.

#### Runtime consistency

Within one package, prefer one script runner style unless there is a real reason to mix:
- `pnpm run ...`
- `bun run ...`
- `npm run ...`

If the scripts depend on package-manager-specific features such as `pnpm --filter`, `pnpm /^build:.*/`, or Bun-only runtime behavior, call out missing or stale `packageManager` metadata because it affects script usability and reproducibility.

#### Parallelization

When sub-builds are independent, consider runner-native fan-out:

```jsonc
// Sequential
"build": "pnpm build:lib && pnpm build:css"

// Better when independent
"build:ui": "pnpm --color /^build:ui:.*$/"
```

Parallelize only when it preserves readable output and does not break dependency order.

### Step 7: Check Lifecycle Hook Usage

Use package lifecycle hooks for real lifecycle boundaries:

```json
{
  "prepare": "vp config",
  "prepack": "pnpm build",
  "prepublishOnly": "pnpm validate"
}
```

Guidelines:
- In VP repos, `prepare: "vp config"` is a strong default.
- In non-VP repos, `prepare: "husky"` is a valid setup hook when the project manages git hooks explicitly.
- `prepare` is for local setup such as VP configuration or git hooks, not for hidden build work.
- `prepack` is for ensuring distributable artifacts exist before packing.
- `prepublishOnly` is for the final release gate.
- Avoid `postinstall` build steps unless the package truly requires them.

### Step 8: Flag Anti-Patterns

Call out these issues explicitly:
- Placeholder success scripts such as `test: "exit 0"` or `prepack: "echo Packaging..."`.
- Platform-specific helpers hidden behind generic names, for example `analyze: "open dist/stats.html"`. If kept, prefer a more explicit name such as `analyze:open`.
- Root workspace scripts that embed leaf-package implementation instead of delegating.
- Missing paired scripts where the workflow expects them, such as `format` without `format:check`, or `lint` without `lint:fix` when Biome is exposed explicitly.
- VP app repos that skip `prepare: "vp config"` and require manual local setup.
- Duplicate aliases that do the same thing without adding clarity.
- Very long inline script strings that should live in `scripts/`.

### Step 9: Generate Report

```markdown
## Scripts Audit Report

### Package Role
- Monorepo root delegating to `@edloidas/example`

### Naming Issues
- `serve` duplicates `dev` without a clearer contract
- `lint:check` should be `lint`

### Composition Issues
- `prepublishOnly` duplicates `check && build && test`; reuse `validate`
- Root `build` re-implements leaf build steps instead of delegating

### Lifecycle Issues
- `prepare` runs a build; move that work to `build` or `prepack`

### Performance / Consistency Issues
- `lint` and `lint:fix` target different file sets
- `test:ci` duplicates `test` instead of adding coverage or stricter CI behavior

### Recommendations
1. Standardize on `build`, `check`, `test`, `test:ci`, and `prepare` as the public VP surface, with `dev` when the repo exposes it.
2. Rename scripts to follow `action:target:variant`.
3. Introduce `validate` and let `prepublishOnly` call it.
4. Move long inline smoke-test logic into `scripts/`.
```

## Common Patterns

Use these as pattern families, not a single universal template. VP app repos should prefer the VP example. Libraries, CLIs, and monorepo roots often use the non-VP `pnpm` or Bun patterns below.

### Vite Plus App

```json
{
  "dev": "vp dev",
  "build": "vp run clean && tsgo && vp build",
  "clean": "rm -rf dist coverage reports",
  "typecheck": "tsgo --noEmit",
  "check": "vp check && vp run typecheck",
  "test": "vp test --run",
  "test:ci": "vp test --run --coverage",
  "prepare": "vp config"
}
```

Optional Biome companion scripts:

```json
{
  "lint": "biome check .",
  "lint:fix": "biome check --write .",
  "format": "biome format --write .",
  "format:check": "biome format ."
}
```

### Monorepo Root (pnpm)

```json
{
  "build": "pnpm --filter @edloidas/example run build",
  "check": "pnpm --filter @edloidas/example run check",
  "test": "pnpm --filter @edloidas/example run test",
  "test:ci": "pnpm --filter @edloidas/example run test:ci",
  "dev": "pnpm --filter @edloidas/example exec vp dev",
  "prepare": "pnpm --filter @edloidas/example run prepare"
}
```

### Non-VP Publishable Library

```json
{
  "clean": "rm -rf dist coverage",
  "typecheck": "tsc --noEmit",
  "lint": "biome lint .",
  "lint:fix": "biome lint --write .",
  "format": "biome format --write .",
  "format:check": "biome format .",
  "check": "pnpm typecheck && pnpm lint && pnpm format:check",
  "check:fix": "pnpm typecheck && pnpm lint:fix && pnpm format",
  "build": "pnpm clean && pnpm build:*",
  "test": "vitest run",
  "test:watch": "vitest",
  "test:ci": "vitest run --coverage",
  "validate": "pnpm check && pnpm build && pnpm test:ci",
  "release:dry": "pnpm publish --dry-run --no-git-checks",
  "prepublishOnly": "pnpm validate"
}
```

### Non-VP Service / CLI

```json
{
  "start": "bun src/index.ts",
  "typecheck": "tsc --noEmit",
  "lint": "biome lint .",
  "lint:fix": "biome lint --write .",
  "format": "biome format --write .",
  "format:check": "biome format .",
  "check": "bun run typecheck && bun run lint && bun run format:check",
  "check:fix": "bun run typecheck && bun run lint:fix && bun run format",
  "test": "bun test",
  "test:watch": "bun test --watch",
  "validate": "bun run check && bun run test"
}
```

## Keywords

package.json, scripts, npm, pnpm, bun, naming, composition, build, lint, format, test, validate, lifecycle
