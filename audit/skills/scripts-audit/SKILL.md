---
name: scripts-audit
description: >
  Audit package.json scripts for naming, composition, lifecycle hooks, consistency, and
  performance.
when_to_use: >
  When auditing or designing npm, pnpm, or Bun scripts, standardizing script conventions, or
  checking whether a package's public script interface fits its role. Also on "audit scripts",
  "check package.json scripts", or "clean up my build scripts".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(jq:*) Read Glob Grep
---

# Scripts Audit

## Purpose

Audit a package's `package.json` scripts against the role the package actually plays: naming,
composition, lifecycle hooks, consistency, and performance. Vite Plus conventions are preferred for
app-style repos. **Reports only — it reads the manifest and writes a report; no file in the repo is
touched, so the working tree is byte-identical afterwards.**

## Scope

This is still a **scripts** skill, not a full `package.json` audit.

Read adjacent manifest fields — the ones Step 1's `jq` reads — only as role signals for Step 2, never as audit subjects.

Do **not** drift into dependency hygiene, `exports`, `peerDependencies`, publish metadata, or security scanning unless the user explicitly asks for that broader audit.

## Vite Plus First

If a repo uses `vite-plus`, aliases `vite` to `@voidzero-dev/vite-plus-core`, or invokes `vp` in scripts, treat Vite Plus as the primary app workflow.

Prefer the VP-native commands of the App (Vite Plus) family in `references/role-templates.md` — read it whenever VP is detected, whatever role Step 2 picks.

Do not recommend ESLint-specific patterns in this skill. If the repo exposes Biome explicitly, it is fine to mention `biome` scripts as optional non-VP companion scripts, but VP remains the primary app workflow.

## Non-VP Patterns

Mention non-VP patterns when the repo actually uses them: plain `pnpm` composition is the baseline for monorepo roots, libraries, and release flows, and `biome` scripts are a valid non-VP quality layer.

When VP is detected, do not try to "improve" the repo by replacing VP-native app flows with separate non-VP app scripts unless the user explicitly asks for that direction.

## Workflow

Done means: the Step 9 report, or `Scripts Audit: clean`, is printed.

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

Close detection with one line: `Role: monorepo root · pnpm 9 · 14 scripts · VP not detected`.

### Step 3: Check Whether the Public Script Interface Fits the Role

Do not demand the same scripts from every package. These are pattern families, not one universal
template: audit against the family the Step 2 role selected, and ignore the others.

Read the selected family's template from `references/role-templates.md` — App (Vite Plus),
Monorepo root (pnpm), Publishable library (non-VP), or Service / bot / CLI (non-VP).

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

If a VP repo exposes `test:ci`, it should usually add something CI-specific such as coverage or stricter reporting rather than duplicating `test`.

#### Biome pairing

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

One section per issue class, in the order below. Drop any section with no findings rather than
writing "none".

```markdown
## Scripts Audit Report

`@edloidas/example-root` · monorepo root · pnpm 9 · 14 scripts · VP not detected

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

With nothing to report, the whole report is the header line plus one sentence:

```markdown
## Scripts Audit: clean

`@edloidas/example` · publishable library · pnpm 9 · 11 scripts · VP not detected
The script surface matches the library role; no naming, composition, lifecycle, or consistency issues.
```

Then stop. Do not edit `package.json`, do not offer to apply the recommendations, and do not audit
dependencies, `exports`, or publish metadata on the way past — that is the Scope boundary above.
