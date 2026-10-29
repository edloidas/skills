# Migration Workflow

Read from `lint-sync` Step 2 when ESLint/Prettier configs are present. Paths are relative to the skill root.

## M1: Get Tool Versions

```bash
pnpm exec eslint --version 2>/dev/null || npx eslint --version 2>/dev/null

# Target-specific
pnpm exec biome --version 2>/dev/null || npx biome --version 2>/dev/null
# or
pnpm exec oxlint --version 2>/dev/null || npx oxlint --version 2>/dev/null
pnpm exec oxfmt --version 2>/dev/null || npx oxfmt --version 2>/dev/null
```

Read the mapping's version with `jq ._meta references/biome-eslint-mapping.json` (or
`oxc-eslint-mapping.json`) → `biomeVersion` / `oxlintVersion`.

Compare installed version against `_meta` version. If installed is newer, warn that mappings may be stale and suggest running `update` mode.

## M2: Gather Active Rules

```bash
# $SCRATCHPAD: the host's scratch directory, or SCRATCHPAD=$(mktemp -d) where it gives none
bash scripts/get-eslint-rules.sh > "$SCRATCHPAD/eslint-rules.json"
bash scripts/get-biome-rules.sh > "$SCRATCHPAD/biome-rules.json"   # or get-oxlint-rules.sh > oxlint-rules.json
```

Each script needs its tool installed in the project and auto-detects the package manager
(pnpm / yarn / bun / npm). If one fails, fall back to reading the configs manually and say in
the report which list came from a config read rather than from the tool.

## M3–M4: Classify Active Rules

Join the two rule lists from M2 against the mapping:

```bash
bash scripts/classify-rules.sh biome "$SCRATCHPAD/eslint-rules.json" "$SCRATCHPAD/biome-rules.json"
# or: bash scripts/classify-rules.sh oxc "$SCRATCHPAD/eslint-rules.json" "$SCRATCHPAD/oxlint-rules.json"
```

It prints JSON with one array per category, the mapping's `_meta` version, and a `summary`
line. Read the mapping files only through `jq` for a single entry; they run to ~16k tokens.

| Category | Meaning | Action |
|----------|---------|--------|
| **DISABLE** | Target has a "same" equivalent and it is active | Safe to turn off in ESLint |
| **REVIEW** | Target has an "inspired" equivalent and it is active (Biome only) | Check behavior before disabling |
| **ENABLE_TARGET** | Target has an equivalent but it is not active | Can switch by enabling in target config |
| **ESLINT_ONLY** | No target equivalent exists | Must keep in ESLint |
| **TYPE_AWARE** | Unmapped, and needs TypeScript type info | Expensive; check whether the target supports it |

Mapped rows carry `typeAware: true` where the target rule needs type info — Oxlint runs those
through tsgolint. Lookup is exact name, then `eslint-plugin-<plugin>/<rule>`, then
`@scope/plugin/rule` collapsed to `@scope/rule`. Biome matches the active rule by name only,
not category, because a rule promoted out of nursery keeps its name.

For Oxc, also load `references/oxc-defaults.json`.

End the phase with the script's `summary` line: `142 active ESLint rules -> 61 DISABLE, 12 REVIEW, 24 ENABLE_TARGET, 38 ESLINT_ONLY, 7 TYPE_AWARE`.

## M5: Prettier Migration Analysis

If Prettier config found:

**Biome:** `biome migrate prettier --write` maps the Prettier options; recommend it rather than
mapping by hand, and look up any option it leaves out through `references/docs.md`.

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

## M6: Oxc Config Initialization (Oxc Only)

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

## M7: Performance Analysis (Audit Mode Only)

```bash
TIMING=1 pnpm exec eslint 'src/**/*.{ts,tsx}' 2>&1 | tee "$SCRATCHPAD/eslint-timing.txt"
```

Cross-reference slowest rules against mapping and type-aware list.

## M8: Generate Migration Report


See Report Templates below. Then stop: the report and the ready-to-paste
config are the deliverable. Do not edit the ESLint config, write the target config, or run
either linter to check the result unless the user asks for the changes to be applied.

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
