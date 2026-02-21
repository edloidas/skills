---
name: lint-sync
description: Compare ESLint rules against Biome to find overlaps, recommend disabling redundant rules, and guide migration
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Grep WebFetch Write
user-invocable: true
arguments: "mode"
argument-hint: "[sync, audit, or update]"
---

# Lint Sync: ESLint ↔ Biome Rule Comparison

## Purpose

Deep rule-by-rule comparison between active ESLint and Biome rules. Identifies which ESLint rules Biome already covers and generates actionable config changes.

## When to Use This Skill

Use when the user asks to:
- "Sync ESLint and Biome rules"
- "Which ESLint rules can I disable?"
- "Compare Biome vs ESLint coverage"
- "Migrate from ESLint to Biome"
- "Find redundant lint rules"
- "Audit ESLint/Biome overlap"

Trigger phrases: "lint sync", "lint-sync", "eslint biome overlap", "biome migration", "disable eslint rules"

## Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **sync** | `/lint-sync` or `/lint-sync sync` | Quick overlap check. Shows which ESLint rules Biome covers. |
| **audit** | `/lint-sync audit` | Full analysis with `TIMING=1` performance data, coverage stats, migration checklist. |
| **update** | `/lint-sync update` | Refresh `biome-eslint-mapping.json` from biomejs.dev. |

## Workflow

### Step 1: Detect Environment

Find configuration files and tool versions:

```bash
# Find ESLint config
fd -t f '(eslint\.config\.(js|ts|mjs|cjs)|\.eslintrc\..*)'  --max-depth 2

# Find Biome config
fd -t f 'biome\.json(c)?$' --max-depth 2

# Get versions
pnpm exec eslint --version 2>/dev/null || npx eslint --version 2>/dev/null
pnpm exec biome --version 2>/dev/null || npx biome --version 2>/dev/null
```

Read `references/biome-eslint-mapping.json` and check `_meta.biomeVersion` against installed version. Warn if the mapping may be stale.

### Step 2: Gather Active Rules

Run the helper scripts from this skill's `scripts/` directory:

```bash
# Get active ESLint rules
bash scripts/get-eslint-rules.sh

# Get active Biome rules
bash scripts/get-biome-rules.sh
```

Both produce JSON output. If a script fails, fall back to reading configs manually:
- ESLint: Parse the config file and resolve preset rules
- Biome: Parse `biome.json` or `biome.jsonc` directly

Save outputs to scratchpad for analysis:
```bash
bash scripts/get-eslint-rules.sh > "$SCRATCHPAD/eslint-rules.json"
bash scripts/get-biome-rules.sh > "$SCRATCHPAD/biome-rules.json"
```

### Step 3: Load References

Read the bundled reference files:

```bash
# Complete ESLint → Biome mapping (~275 entries)
cat references/biome-eslint-mapping.json

# Type-aware rules list (~60 entries)
cat references/type-aware-rules.json
```

### Step 4: Cross-Reference (Core Analysis)

For each active ESLint rule, classify it into one of these categories:

| Category | Meaning | Action |
|----------|---------|--------|
| **DISABLE** | Biome has "same" equivalent AND it's enabled in Biome | Safe to turn off in ESLint |
| **REVIEW** | Biome has "inspired" equivalent AND it's enabled in Biome | Check behavior before disabling |
| **ENABLE_BIOME** | Biome has equivalent but it's NOT enabled in Biome | Can switch by enabling in Biome config |
| **ALREADY_OFF** | Already disabled in ESLint, Biome covers it | Validates current setup |
| **ESLINT_ONLY** | No Biome equivalent exists | Must keep in ESLint |
| **TYPE_AWARE** | Requires TypeScript type info | Mark as expensive; no Biome equivalent possible |

**Classification logic:**

```
for each active ESLint rule:
  1. Look up in biome-eslint-mapping.json by ESLint rule name
     - ESLint --print-config uses short plugin names: "jsx-a11y/alt-text"
     - The mapping keys use npm package names: "eslint-plugin-jsx-a11y/alt-text"
     - Resolution order for rule "plugin/rule-name":
       a. Try exact match: "plugin/rule-name"
       b. Try "eslint-plugin-plugin/rule-name" (add eslint-plugin- prefix)
       c. For scoped plugins (@scope/rule), try "@scope/rule" directly
     - Core ESLint rules (no prefix) match directly: "no-debugger"
  2. If no mapping → check type-aware-rules.json → TYPE_AWARE or ESLINT_ONLY
     - For @typescript-eslint/* rules, strip prefix and check type-aware list
  3. If mapping exists:
     a. Check if the Biome rule is active (in biome-rules.json)
        IMPORTANT: Biome 2.x reorganized categories. Match by RULE NAME only
        (the part after the last "/"), not by full path. For example, mapping says
        "style/noUselessRename" but Biome 2.x reports "complexity/noUselessRename".
     b. If active + relationship "same" → DISABLE
     c. If active + relationship "inspired" → REVIEW
     d. If NOT active → ENABLE_BIOME
```

### Step 5: Performance Analysis (Audit Mode Only)

Only when mode is `audit`:

```bash
# Run ESLint with timing
TIMING=1 pnpm exec eslint 'src/**/*.{ts,tsx}' 2>&1 | tee "$SCRATCHPAD/eslint-timing.txt"
```

Parse the timing output to identify the slowest rules. Cross-reference against:
- The mapping (can any slow rules be offloaded to Biome?)
- The type-aware rules list (are expensive type-checked rules in use?)

Generate a "top 10 slowest rules" table with recommendations.

### Step 6: Generate Report

#### Sync Mode Report

```markdown
## Lint Sync Report

### Environment
- ESLint: v9.x (flat config)
- Biome: v2.x
- Mapping version: 2026-xx-xx (current / ⚠️ stale)

### Summary
| Category | Count |
|----------|-------|
| DISABLE (safe to remove) | X |
| REVIEW (check before removing) | X |
| ENABLE_BIOME (can migrate) | X |
| ESLINT_ONLY (must keep) | X |
| TYPE_AWARE (expensive, must keep) | X |

### DISABLE — Safe to Turn Off in ESLint
These ESLint rules have identical ("same") Biome equivalents that are already enabled.

| ESLint Rule | Biome Equivalent |
|-------------|-----------------|
| `no-debugger` | `correctness/noDebugger` |
| ... | ... |

### REVIEW — Check Before Disabling
These have "inspired" Biome equivalents. Behavior may differ slightly.

| ESLint Rule | Biome Equivalent | Notes |
|-------------|-----------------|-------|
| ... | ... | ... |

### ENABLE_BIOME — Available to Migrate
Biome has equivalents but they're not enabled. Enable in `biome.json` to replace these.

| ESLint Rule | Biome Equivalent | Relationship |
|-------------|-----------------|--------------|
| ... | ... | same/inspired |

### ESLINT_ONLY — Must Keep
No Biome equivalent. These must remain in ESLint.

| ESLint Rule | Type-Aware? |
|-------------|-------------|
| ... | Yes/No |

### Ready-to-Paste Config

Add to your ESLint config to disable redundant rules:

\`\`\`typescript
// Rules covered by Biome — safe to disable
const biomeCoveredRules = {
  'rule-name': 'off',
  // ...
};
\`\`\`
```

#### Audit Mode Report

Includes everything from sync mode, plus:

```markdown
### Performance Analysis

#### Top 10 Slowest Rules
| Rule | Time (ms) | Type-Aware? | Biome Equivalent? |
|------|-----------|-------------|-------------------|
| ... | ... | ... | ... |

#### Coverage Statistics
- Total active ESLint rules: X
- Covered by Biome: X (Y%)
  - Same behavior: X
  - Inspired: X
- ESLint-only: X (Y%)
- Type-aware: X (Y%)

#### Migration Checklist
- [ ] Disable X rules already covered by Biome
- [ ] Review X "inspired" rules for behavioral differences
- [ ] Consider enabling X additional Biome rules
- [ ] Evaluate if X type-aware rules justify the performance cost
- [ ] Test: run both linters and compare output
```

### Step 7: Update References (Update Mode Only)

When mode is `update`:

#### 7a. Update biome-eslint-mapping.json

1. Fetch the latest mapping from Biome documentation:
```
WebFetch https://biomejs.dev/linter/rules-sources/
```

2. Parse the page content to extract all ESLint → Biome rule mappings

3. Compare with existing `references/biome-eslint-mapping.json`:
   - Show added mappings (new Biome rules)
   - Show removed mappings (deprecated rules)
   - Update `_meta.biomeVersion` and `_meta.updatedAt`

4. Write the updated file:
```bash
# Write updated mapping
cat > references/biome-eslint-mapping.json << 'EOF'
{updated JSON}
EOF
```

5. Report what changed

#### 7b. Update type-aware-rules.json

1. Fetch the latest `disable-type-checked.ts` from typescript-eslint via GitHub API:
```bash
gh api repos/typescript-eslint/typescript-eslint/contents/packages/eslint-plugin/src/configs/flat/disable-type-checked.ts --jq '.content' | base64 -d
```

2. Parse the TypeScript file to extract all `@typescript-eslint/*` rule names (the keys in the rules object, stripping the `@typescript-eslint/` prefix)

3. Compare with existing `references/type-aware-rules.json`:
   - Show added rules (new type-aware rules)
   - Show removed rules (dropped rules)
   - Update `_meta.updatedAt`

4. Write the updated file:
```bash
# Write updated type-aware rules
cat > references/type-aware-rules.json << 'EOF'
{updated JSON}
EOF
```

5. Report what changed

## Important Notes

- The `get-eslint-rules.sh` script requires a project with ESLint installed and configured
- The `get-biome-rules.sh` script requires Biome installed and configured
- Both scripts auto-detect the package manager (pnpm/yarn/bun/npm)
- The biome-eslint-mapping.json may need updating when Biome releases new versions
- Some Biome rules are in `nursery` category — these are experimental and may change
- "inspired" relationships mean behavior may differ; always verify before disabling
- Type-aware rules have NO Biome equivalents — they require TypeScript's type checker
- External repos accessed: `typescript-eslint/typescript-eslint` (public)

## Bundled References

- `references/biome-eslint-mapping.json` — Complete ESLint → Biome rule mapping (~275 entries)
- `references/type-aware-rules.json` — TypeScript-ESLint rules requiring type information (~60 entries)
- `scripts/get-eslint-rules.sh` — Extract active ESLint rules via `--print-config`
- `scripts/get-biome-rules.sh` — Extract active Biome rules via `biome rage --linter`

## Keywords

eslint, biome, lint, rules, sync, overlap, migration, type-aware, performance, disable, redundant
