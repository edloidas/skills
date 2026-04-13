---
name: lint-sync
description: >
  Migrate ESLint/Prettier to Biome or Oxc (including Vite+), or modernize existing configs.
  Detects source and target configs, compares rules, flags stale nursery rules,
  suggests new features, and generates actionable config changes.
  Use when asked to sync lint rules, migrate linters, modernize configs, or update tool settings.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Glob Grep WebFetch Write AskUserQuestion
user-invocable: true
argument-hint: "[sync, audit, or update]"
---

# Lint Sync

## Purpose

Two workflows in one skill:
1. **Migrate** — Move ESLint/Prettier rules to Biome or Oxc with rule-by-rule comparison
2. **Modernize** — Update existing Biome/Oxc configs: promote nursery rules, enable new quality flags, apply latest formatter options

## When to Use This Skill

Trigger phrases: "lint sync", "lint-sync", "eslint biome overlap", "biome migration", "oxlint migration", "migrate to oxc", "disable eslint rules", "modernize biome config", "update biome rules", "promote nursery rules", "update oxlint config"

## Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **sync** | No mode or `sync` | Quick overlap check (migrate) or nursery/feature check (modernize). |
| **audit** | `audit` | Full analysis with performance data, coverage stats, migration/modernization checklist. |
| **update** | `update` | Refresh mapping and version reference files from upstream sources. |

## Documentation

Before fetching docs from the web, check `references/docs.md` for Context7 library IDs and direct URLs. This saves tokens significantly.

**Context7 IDs for quick lookups:**
- Biome: `/biomejs/website` (5357 snippets)
- Oxc: `/oxc-project/website` (5057 snippets)
- Vite+: `/websites/viteplus_dev` (210 snippets)

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

When asking target choice, use `AskUserQuestion` when available. Otherwise ask
in normal chat with this short numbered list and wait for the user's reply:

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

If a script fails, fall back to reading configs manually.

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

See [Report Templates](#report-templates) below.

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

Check project dependencies first:
```bash
jq -r '.dependencies.tailwindcss // .devDependencies.tailwindcss // empty' package.json
```

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

### U1: Update biome-eslint-mapping.json

1. Fetch `https://biomejs.dev/linter/rules-sources/`
2. Parse ESLint → Biome rule mappings
3. Diff against existing, show added/removed
4. Update `_meta.biomeVersion` and `_meta.updatedAt`

### U2: Update oxc-eslint-mapping.json

1. Fetch `https://oxc.rs/docs/guide/usage/linter/rules`
2. Parse supported rules by plugin
3. Diff against existing, show added/removed
4. Update `_meta.oxlintVersion` and `_meta.updatedAt`

### U3: Update type-aware-rules.json

```bash
gh api repos/typescript-eslint/typescript-eslint/contents/packages/eslint-plugin/src/configs/flat/disable-type-checked.ts --jq '.content' | base64 -d
```

Parse, diff, update `_meta.updatedAt`.

### U4: Update version files

Check Biome and Oxc changelogs for new versions not yet tracked:
- Biome: `https://biomejs.dev/blog/` — look for new `biome-vX-Y` posts
- Oxc: `https://oxc.rs/blog/` — look for new release posts

For each new version found, add entry to `biome-versions.json` or `oxc-versions.json` with:
- Promoted rules
- New rules
- New formatter options
- New features

---

## Report Templates

### Sync Mode (Migration)

```markdown
## Lint Sync Report

### Environment
- ESLint: vX.x (flat/legacy config)
- Target: Biome vX.x / Oxlint vX.x + Oxfmt vX.x
- Mapping version: YYYY-MM-DD (current / stale)
- Prettier config: found / not found

### Summary
| Category | Count |
|----------|-------|
| DISABLE (safe to remove) | X |
| REVIEW (check before removing) | X |
| ENABLE_TARGET (can migrate) | X |
| ESLINT_ONLY (must keep) | X |
| TYPE_AWARE | X |

### DISABLE — Safe to Turn Off in ESLint
| ESLint Rule | Target Equivalent |
|-------------|------------------|

### REVIEW — Check Before Disabling
| ESLint Rule | Target Equivalent | Notes |
|-------------|------------------|-------|

### ENABLE_TARGET — Available to Migrate
| ESLint Rule | Target Equivalent | Relationship |
|-------------|------------------|--------------|

### ESLINT_ONLY — Must Keep
| ESLint Rule | Type-Aware? |
|-------------|-------------|

### Prettier Migration (if applicable)
| Prettier Option | Current Value | Target Option | Target Default | Action |
|----------------|--------------|--------------|----------------|--------|

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

## Important Notes

- Scripts require the respective tools installed in the project
- Scripts auto-detect the package manager (pnpm/yarn/bun/npm)
- Version files track which Biome/Oxc versions introduced which changes
- Modernize workflow uses version files to detect stale nursery refs and suggest new features
- For doc lookups, use Context7 IDs from `references/docs.md` before web search
- **Vite+** projects embed Oxlint/Oxfmt config in `vite.config.ts` (`lint`/`fmt` blocks) — do not create standalone `.oxlintrc.json`/`.oxfmtrc.json` alongside Vite+
- External repos accessed: `typescript-eslint/typescript-eslint` (public)

## Bundled References

- `references/biome-eslint-mapping.json` — ESLint → Biome rule mapping (~260 entries)
- `references/oxc-eslint-mapping.json` — ESLint → Oxlint rule mapping (~520 entries)
- `references/biome-versions.json` — Biome version changelog: promotions, new rules, new options
- `references/oxc-versions.json` — Oxc version changelog: new rules, features, recommended config
- `references/oxc-defaults.json` — Opinionated Oxlint/Oxfmt defaults for initialization
- `references/type-aware-rules.json` — TypeScript-ESLint type-aware rules (~60 entries)
- `references/docs.md` — Context7 library IDs and documentation URLs
- `scripts/get-eslint-rules.sh` — Extract active ESLint rules via `--print-config`
- `scripts/get-biome-rules.sh` — Extract active Biome rules via `biome rage --linter`
- `scripts/get-oxlint-rules.sh` — Extract active Oxlint rules

## Keywords

eslint, biome, oxlint, oxfmt, oxc, prettier, vite-plus, viteplus, lint, rules, sync, overlap, migration, modernize, nursery, promote, type-aware, performance, disable, redundant, formatter, update
