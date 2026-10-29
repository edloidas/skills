# Modernize Workflow

Read from `lint-sync` Step 2 when no ESLint/Prettier config exists but Biome and/or Oxc configs do. Paths are relative to the skill root.

## N1: Read Current Config

Read and parse the tool's config file:
- Biome: `biome.json` or `biome.jsonc`
- Oxc standalone: `.oxlintrc.json` and `.oxfmtrc.json`
- Vite+ (`$VITEPLUS=true`): parse `lint` and `fmt` blocks from `vite.config.ts`

## N2: Get Installed Version

```bash
pnpm exec biome --version 2>/dev/null || npx biome --version 2>/dev/null
# or
pnpm exec oxlint --version 2>/dev/null || npx oxlint --version 2>/dev/null
```

## N3: Load Version History

```bash
cat references/biome-versions.json   # or oxc-versions.json
```

Determine which versions the user has passed through since their config was last updated. Use the installed version to find applicable changes.

## N4: Check Nursery Promotions (Biome)

Scan the user's config for any rules referencing `nursery/` category. Cross-reference against `biome-versions.json` → `promotedFromNursery` entries for the installed version and all prior tracked versions.

For each stale nursery reference found:

| Current (stale) | Should be | Promoted in |
|-----------------|-----------|-------------|
| `nursery/noConsole` | `suspicious/noConsole` | v2.4 |
| `nursery/noSecrets` | `security/noSecrets` | v2.3 |

Generate a ready-to-apply diff or config patch.

## N5: Suggest New Quality Rules

**Biome:** Check `biome-versions.json` for `newRules` in versions newer than user's mapping date. Highlight rules that are:
- Promoted to stable (non-nursery) — safe to enable
- Commonly useful (e.g., `noUnusedExpressions`, `noImportCycles`, `noFloatingPromises`)
- New formatter options (e.g., `trailingNewline` in v2.4)

**Oxc:** Check `oxc-versions.json` for `recommendedConfig` rules not yet in user's config. Suggest:
- Categories worth enabling (`suspicious`, `perf`)
- High-value rules from `oxc-versions.json` → `recommendedConfig.rules`
- New features (type-aware linting, Vue support, config extends)

## N6: Suggest New Formatter Options and Sorting

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

## N7: Generate Modernize Report

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

Then stop: the report and the patch are the deliverable. Do not edit the config or run the
linter unless the user asks for the patch to be applied.
