---
name: lint-sync
description: >
  Migrate ESLint and Prettier to Biome or Oxc (including Vite+), or modernize an existing
  config. Detects source and target configs, compares rules, flags stale nursery rules,
  suggests new features, and generates actionable config changes.
when_to_use: >
  On "sync lint rules", "migrate to Biome", "migrate to Oxlint", "modernize the lint config",
  or "update the formatter". Also when a config still carries nursery rules that have since
  been promoted, or ESLint and Prettier overlap on the same rules.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Glob Grep WebFetch Write AskUserQuestion
argument-hint: "[sync, audit, or update]"
---

# Lint Sync

**Local writes only, and only two of the three modes write.** `sync` and `audit` analyse and
report — no config file changes unless the user asks for the generated patch to be applied.
`update` rewrites the bundled `references/*.json` files in this skill. Nothing is staged,
committed, or pushed, and no remote service is written to.

**Edit mechanic.** A config file that does not exist yet — `.oxlintrc.json`, `.oxfmtrc.json` —
is generated whole from `references/oxc-defaults.json`. Every file that already exists —
`vite.config.ts`, `biome.json`, an ESLint config, a reference JSON in `update` mode — is changed
with targeted edits per hunk, never a whole-file rewrite: a formatter-wide reflow of someone's
`vite.config.ts` buries the rules that actually changed.

## Purpose

Two workflows in one skill:
1. **Migrate** — Move ESLint/Prettier rules to Biome or Oxc with rule-by-rule comparison
2. **Modernize** — Update existing Biome/Oxc configs: promote nursery rules, enable new quality flags, apply latest formatter options

## Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **sync** | No mode or `sync` | Quick overlap check (migrate) or nursery/feature check (modernize). |
| **audit** | `audit` | Full analysis with performance data, coverage stats, migration/modernization checklist. |
| **update** | `update` | Refresh mapping and version reference files from upstream sources. |

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Workflow

### Step 1: Detect All Configs

Find all relevant configuration files:

```bash
# Source tools (ESLint / Prettier)
fd -t f '(eslint\.config\.(js|ts|mjs|cjs)|\.eslintrc\..*)' --max-depth 2
fd -t f '(\.prettierrc(\.(js|cjs|mjs|json|yaml|yml|toml))?|prettier\.config\.(js|cjs|mjs|ts))' --max-depth 2

# Target tools (Biome / Oxc)
fd -t f 'biome\.json(c)?$' --max-depth 2
fd -t f '(\.oxlintrc\.(json|jsonc)|oxlint\.config\.(ts|js))' --max-depth 2
fd -t f '(\.oxfmtrc\.(json|jsonc)|oxfmt\.config\.(ts|js))' --max-depth 2

# Vite+ (unified Oxc config)
fd -t f 'vite\.config\.(ts|js|mjs)$' --max-depth 2
```

**Vite+ detection:** If `vite.config.ts` exists, check if it imports from `'vite-plus'`. Also check `package.json` for `vite-plus` in dependencies. If Vite+ is in use, its `lint` and `fmt` blocks in `vite.config.ts` **replace** standalone `.oxlintrc.json` and `.oxfmtrc.json`. Set `$VITEPLUS=true` and treat Oxc config as found.

```bash
# Quick Vite+ detection
grep -l "from ['\"]vite-plus['\"]" vite.config.ts 2>/dev/null
```

Run every detection command before deciding anything, and end the phase with one line naming
what was found: `Found: eslint.config.ts, .prettierrc, vite.config.ts (Vite+) · no biome.json`.

### Step 2: Determine Workflow

| ESLint/Prettier | Biome | Oxc/Vite+ | Workflow |
|----------------|-------|-----------|----------|
| Found | Found | - | **Migrate** to Biome |
| Found | - | Found | **Migrate** to Oxc |
| Found | Found | Found | Ask user which target |
| Found | - | - | Ask user which target to migrate to |
| - | Found | - | **Modernize** Biome |
| - | - | Found | **Modernize** Oxc |
| - | Found | Found | **Modernize** both (ask which first) |
| - | - | - | Nothing to do — inform user |

**Vite+ counts as Oxc** in the table above. When `$VITEPLUS=true`, all Oxc config reads/writes target the `lint` and `fmt` blocks in `vite.config.ts` instead of standalone config files.

Ask the target choice per **Asking the User**:

```
Which tool would you like to migrate to?
1. Biome (Recommended) — All-in-one linter + formatter, single config file
2. Oxc (Oxlint + Oxfmt) — Separate linter and formatter, ESLint-compatible rule names
3. Skip — Don't migrate, just show the analysis
```

---

## Migration Workflow

Runs when ESLint/Prettier configs are present.

### M1: Get Tool Versions

```bash
pnpm exec eslint --version 2>/dev/null || npx eslint --version 2>/dev/null

# Target-specific
pnpm exec biome --version 2>/dev/null || npx biome --version 2>/dev/null
# or
pnpm exec oxlint --version 2>/dev/null || npx oxlint --version 2>/dev/null
pnpm exec oxfmt --version 2>/dev/null || npx oxfmt --version 2>/dev/null
```

Read the appropriate mapping and check version staleness:
- Biome: `references/biome-eslint-mapping.json` → `_meta.biomeVersion`
- Oxc: `references/oxc-eslint-mapping.json` → `_meta.oxlintVersion`

Compare installed version against `_meta` version. If installed is newer, warn that mappings may be stale and suggest running `update` mode.

### M2: Gather Active Rules

```bash
bash scripts/get-eslint-rules.sh
bash scripts/get-biome-rules.sh   # or get-oxlint-rules.sh
```

Each script needs its tool installed in the project and auto-detects the package manager
(pnpm / yarn / bun / npm). If one fails, fall back to reading the configs manually and say in
the report which list came from a config read rather than from the tool.

### M3: Load References

```bash
cat references/biome-eslint-mapping.json   # or oxc-eslint-mapping.json
cat references/type-aware-rules.json
```

For Oxc, also load `references/oxc-defaults.json`.

### M4: Cross-Reference (Core Analysis)

For each active ESLint rule, classify it:

| Category | Meaning | Action |
|----------|---------|--------|
| **DISABLE** | Target has "same" equivalent AND it's active | Safe to turn off in ESLint |
| **REVIEW** | Target has "inspired" equivalent AND it's active | Check behavior before disabling |
| **ENABLE_TARGET** | Target has equivalent but it's NOT active | Can switch by enabling in target config |
| **ESLINT_ONLY** | No target equivalent exists | Must keep in ESLint |
| **TYPE_AWARE** | Requires TypeScript type info | Expensive; check if target supports it |

**Biome classification:**

```
for each active ESLint rule:
  1. Look up in biome-eslint-mapping.json
     - Resolution: exact → "eslint-plugin-" prefix → scoped (@scope/rule)
     - Core ESLint rules match directly: "no-debugger"
  2. No mapping → check type-aware-rules.json → TYPE_AWARE or ESLINT_ONLY
  3. Mapping exists:
     a. Check if Biome rule is active (match by RULE NAME only, not category)
     b. Active + "same" → DISABLE
     c. Active + "inspired" → REVIEW
     d. Not active → ENABLE_TARGET
```

**Oxc classification:**

```
for each active ESLint rule:
  1. Look up in oxc-eslint-mapping.json (same resolution order)
  2. No mapping → TYPE_AWARE (if in type-aware list) or ESLINT_ONLY
     - Oxlint supports type-aware rules via tsgolint (check "typeAware" field)
  3. Mapping exists:
     a. Check if active; all Oxlint mappings are "same" relationship
     b. Active → DISABLE
     c. Not active → ENABLE_TARGET
```

Classify every active rule before reporting any of them, and end the phase with one line
carrying the counts: `142 active ESLint rules -> 61 DISABLE, 12 REVIEW, 24 ENABLE_TARGET, 38 ESLINT_ONLY, 7 TYPE_AWARE`.

### M5: Prettier Migration Analysis

If Prettier config found:

**Biome:** Map Prettier options → Biome equivalents (see table in `references/docs.md`).
Note: `biome migrate prettier --write` automates this.

**Oxc:** Oxfmt uses Prettier-compatible option names. Key differences:
- `printWidth` defaults to `100` (Prettier: `80`)
- `endOfLine: "auto"` not supported
- Built-in: `sortImports`, `sortTailwindcss`, `sortPackageJson`
Note: `oxfmt --migrate=prettier` automates this.

**Import sorting (both targets):** Check if the project uses `eslint-plugin-import` sort rules, `@trivago/prettier-plugin-sort-imports`, `prettier-plugin-organize-imports`, or `@ianvs/prettier-plugin-sort-imports`. If so, recommend enabling the native import sorter:
- Biome: `"organizeImports": { "enabled": true }` in `biome.json`
- Oxfmt: `"sortImports": { ... }` (see defaults in `oxc-defaults.json`)

**Tailwind class sorting (both targets):** Check if `tailwindcss` is in project deps. If so, and if `prettier-plugin-tailwindcss` was in use, recommend enabling native sorting:
- Biome: not built-in — keep the Prettier plugin or use `biome-plugin-tailwindcss` if available
- Oxfmt: `"sortTailwindcss": { ... }` built-in (see `oxc-defaults.json` → `oxfmt_ifTailwind`)

### M6: Oxc Config Initialization (Oxc Only)

If no Oxc config exists, offer to create from `references/oxc-defaults.json`.

**Before writing config, check project dependencies:**

```bash
# Check for React
jq -r '.dependencies.react // .devDependencies.react // empty' package.json
# Check for Tailwind CSS
jq -r '.dependencies.tailwindcss // .devDependencies.tailwindcss // empty' package.json
```

**Config assembly from defaults:**
- Always: `categories`, `rules`, `env`, `options` from `oxlint` section
- Always: `plugins.always` (`eslint`, `typescript`, `unicorn`, `oxc`, `import`)
- If React in deps: add `plugins.ifReact` (`react`, `react-hooks`, `jsx-a11y`)
- Oxfmt: `singleQuote`, `sortImports` from `oxfmt` section
- If Tailwind in deps: merge `oxfmt_ifTailwind` → enables `sortTailwindcss` with class sorting for `className`, `class`, and common helpers (`clsx`, `cn`, `cva`, `tw`, `twMerge`, `twJoin`)

**Vite+ projects (`$VITEPLUS=true`):** Write into `vite.config.ts` `lint` and `fmt` blocks. Do NOT create standalone config files. Example:

```typescript
import { defineConfig } from 'vite-plus';

export default defineConfig({
  lint: {
    categories: { correctness: 'error', suspicious: 'warn', perf: 'warn' },
    plugins: ['eslint', 'typescript', 'unicorn', 'oxc', 'import', 'react', 'react-hooks', 'jsx-a11y'],
    rules: {
      'no-console': 'warn',
      'eqeqeq': 'error',
      'import/no-cycle': 'error',
    },
    options: { typeAware: true, typeCheck: true },
  },
  fmt: {
    singleQuote: true,
    sortImports: { ignoreCase: true, order: 'asc', newlinesBetween: true },
    sortTailwindcss: { functions: ['clsx', 'cn', 'cva', 'tw'] }, // if Tailwind
  },
});
```

**Standalone Oxc projects:** Write `.oxlintrc.json` and `.oxfmtrc.json`.

### M7: Performance Analysis (Audit Mode Only)

```bash
TIMING=1 pnpm exec eslint 'src/**/*.{ts,tsx}' 2>&1 | tee "$SCRATCHPAD/eslint-timing.txt"
```

Cross-reference slowest rules against mapping and type-aware list.

### M8: Generate Migration Report

See [Report Templates](#report-templates) below. Then stop: the report and the ready-to-paste
config are the deliverable. Do not edit the ESLint config, write the target config, or run
either linter to check the result unless the user asks for the changes to be applied.

---

## Modernize Workflow

Runs when no ESLint/Prettier configs exist but Biome and/or Oxc configs are present.

### N1: Read Current Config

Read and parse the tool's config file:
- Biome: `biome.json` or `biome.jsonc`
- Oxc standalone: `.oxlintrc.json` and `.oxfmtrc.json`
- Vite+ (`$VITEPLUS=true`): parse `lint` and `fmt` blocks from `vite.config.ts`

### N2: Get Installed Version

```bash
pnpm exec biome --version 2>/dev/null || npx biome --version 2>/dev/null
# or
pnpm exec oxlint --version 2>/dev/null || npx oxlint --version 2>/dev/null
```

### N3: Load Version History

```bash
cat references/biome-versions.json   # or oxc-versions.json
```

Determine which versions the user has passed through since their config was last updated. Use the installed version to find applicable changes.

### N4: Check Nursery Promotions (Biome)

Scan the user's config for any rules referencing `nursery/` category. Cross-reference against `biome-versions.json` → `promotedFromNursery` entries for the installed version and all prior tracked versions.

For each stale nursery reference found:

| Current (stale) | Should be | Promoted in |
|-----------------|-----------|-------------|
| `nursery/noConsole` | `suspicious/noConsole` | v2.4 |
| `nursery/noSecrets` | `security/noSecrets` | v2.3 |

Generate a ready-to-apply diff or config patch.

### N5: Suggest New Quality Rules

**Biome:** Check `biome-versions.json` for `newRules` in versions newer than user's mapping date. Highlight rules that are:
- Promoted to stable (non-nursery) — safe to enable
- Commonly useful (e.g., `noUnusedExpressions`, `noImportCycles`, `noFloatingPromises`)
- New formatter options (e.g., `trailingNewline` in v2.4)

**Oxc:** Check `oxc-versions.json` for `recommendedConfig` rules not yet in user's config. Suggest:
- Categories worth enabling (`suspicious`, `perf`)
- High-value rules from `oxc-versions.json` → `recommendedConfig.rules`
- New features (type-aware linting, Vue support, config extends)

### N6: Suggest New Formatter Options and Sorting

Check whether Tailwind is a project dependency first, with the same `jq` query as M6.

**Biome:** Check `biome-versions.json` for `newFormatterOptions`. Highlight useful additions:
- `formatter.trailingNewline` (v2.4)
- `formatter.lineEnding: "auto"` (v2.3)
- `formatter.expand` for array/object control
- `organizeImports.enabled: true` if not already on — replaces import-sort plugins
- Note: Biome does not have built-in Tailwind class sorting

**Oxc/Vite+:** Check if Oxfmt features are underutilized:
- `sortImports` (off by default, high value — replaces import-sort plugins)
- `sortTailwindcss` (if Tailwind in deps — replaces `prettier-plugin-tailwindcss`)
- `jsdoc` formatting (off by default)
- For Vite+: `lint.options.typeAware` and `lint.options.typeCheck` (recommended on)

End the analysis with one line carrying the counts: `3 stale nursery refs, 9 new stable rules,
4 formatter options available`.

### N7: Generate Modernize Report

```markdown
## Modernize Report

### Environment
- Tool: Biome vX.x / Oxlint vX.x / Vite+ vX.x
- Config: biome.json / .oxlintrc.json / vite.config.ts (lint + fmt)
- Reference version: X.x (installed: Y.y)

### Nursery Promotions (Biome)
X rules in your config still reference nursery/ but have been promoted:

| Current | Updated | Version |
|---------|---------|---------|
| `nursery/noSecrets` | `security/noSecrets` | v2.3 |

### New Rules Available
These rules are stable and recommended but not in your config:

| Rule | Category | Description |
|------|----------|-------------|
| `noImportCycles` | suspicious | Detect circular imports |

### New Formatter Options
| Option | Value | Since |
|--------|-------|-------|
| `trailingNewline` | `true` | v2.4 |

### Ready-to-Apply Config Patch
(JSON diff to paste into config)
```

---

## Update Workflow

Refreshes all reference files from upstream.

### U1: Update the ESLint mapping files

| File | Source | `_meta` fields to bump |
|------|--------|------------------------|
| `references/biome-eslint-mapping.json` | `https://biomejs.dev/linter/rules-sources/` | `biomeVersion`, `updatedAt` |
| `references/oxc-eslint-mapping.json` | `https://oxc.rs/docs/guide/usage/linter/rules` | `oxlintVersion`, `updatedAt` |

For each: fetch, parse the rule mappings (Oxc's are grouped by plugin), diff against the
existing file, show what was added and removed, then bump the `_meta` fields.

### U2: Update type-aware-rules.json

```bash
gh api repos/typescript-eslint/typescript-eslint/contents/packages/eslint-plugin/src/configs/flat/disable-type-checked.ts --jq '.content' | base64 -d
```

Parse, diff, update `_meta.updatedAt`.

### U3: Update version files

Check Biome and Oxc changelogs for new versions not yet tracked:
- Biome: `https://biomejs.dev/blog/` — look for new `biome-vX-Y` posts
- Oxc: `https://oxc.rs/blog/` — look for new release posts

For each new version found, add entry to `biome-versions.json` or `oxc-versions.json` with:
- Promoted rules
- New rules
- New formatter options
- New features

End with one line per refreshed file: `biome-eslint-mapping.json: +14 / -3 (v2.4.2)`. Then stop
— `update` maintains this skill's reference files and touches no project config.

---

## Report Templates

### Sync Mode (Migration)

Filled with real values from one run; a table with no rows for this run is kept, showing `_(none)_`.

```markdown
## Lint Sync Report

### Environment
- ESLint: v9.18.0 (flat config)
- Target: Oxlint v1.14.0 + Oxfmt v0.4.2 (via Vite+ 1.0.3, `vite.config.ts`)
- Mapping version: 2025-11-04 (stale — installed Oxlint is newer, run `update`)
- Prettier config: found (`.prettierrc`)

### Summary
| Category | Count |
|----------|-------|
| DISABLE (safe to remove) | 61 |
| REVIEW (check before removing) | 12 |
| ENABLE_TARGET (can migrate) | 24 |
| ESLINT_ONLY (must keep) | 38 |
| TYPE_AWARE | 7 |

### DISABLE — Safe to Turn Off in ESLint
| ESLint Rule | Target Equivalent |
|-------------|------------------|
| `no-debugger` | `oxc/no-debugger` |
| `@typescript-eslint/no-unused-vars` | `typescript/no-unused-vars` |

### REVIEW — Check Before Disabling
| ESLint Rule | Target Equivalent | Notes |
|-------------|------------------|-------|
| `import/no-cycle` | `import/no-cycle` | Inspired; Oxlint ignores `maxDepth` |

### ENABLE_TARGET — Available to Migrate
| ESLint Rule | Target Equivalent | Relationship |
|-------------|------------------|--------------|
| `eqeqeq` | `eslint/eqeqeq` | same (not yet active) |

### ESLINT_ONLY — Must Keep
| ESLint Rule | Type-Aware? |
|-------------|-------------|
| `@typescript-eslint/no-floating-promises` | yes |

### Prettier Migration (if applicable)
| Prettier Option | Current Value | Target Option | Target Default | Action |
|----------------|--------------|--------------|----------------|--------|
| `printWidth` | 80 | `printWidth` | 100 | set explicitly to keep 80 |

### Ready-to-Paste Config
```

### Audit Mode (adds to Sync)

```markdown
### Performance Analysis

#### Top 10 Slowest Rules
| Rule | Time (ms) | Type-Aware? | Target Equivalent? |
|------|-----------|-------------|-------------------|

#### Coverage Statistics
- Total active ESLint rules: X
- Covered by target: X (Y%)
- ESLint-only: X (Y%)
- Type-aware: X (Y%)

#### Migration Checklist
- [ ] Disable X covered rules
- [ ] Review X "inspired" rules (Biome)
- [ ] Enable X additional target rules
- [ ] Migrate Prettier config
- [ ] Run both linters and compare output
```

## Bundled References

- `references/biome-eslint-mapping.json` — ESLint → Biome rule mapping (~260 entries)
- `references/oxc-eslint-mapping.json` — ESLint → Oxlint rule mapping (~520 entries)
- `references/biome-versions.json` — Biome version changelog: promotions, new rules, new options
- `references/oxc-versions.json` — Oxc version changelog: new rules, features, recommended config
- `references/oxc-defaults.json` — Opinionated Oxlint/Oxfmt defaults for initialization
- `references/type-aware-rules.json` — TypeScript-ESLint type-aware rules (~60 entries)
- `references/docs.md` — Context7 library IDs and doc URLs for Biome, Oxc, and Vite+; read it before any web fetch
- `scripts/get-eslint-rules.sh` — Extract active ESLint rules via `--print-config`
- `scripts/get-biome-rules.sh` — Extract active Biome rules via `biome rage --linter`
- `scripts/get-oxlint-rules.sh` — Extract active Oxlint rules
