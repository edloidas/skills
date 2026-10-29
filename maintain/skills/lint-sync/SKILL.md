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

`update` mode skips Steps 1–2 and goes straight to `references/update.md`.

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
3. Skip — Don't migrate; stop at the Step 1 detection line
```

Then read the workflow file the table picked and follow it — one workflow per run:

| Workflow | File | Ends with |
|----------|------|-----------|
| Migrate | `references/migrate.md` (M1–M8, report templates) | the migration report and a ready-to-paste config |
| Modernize | `references/modernize.md` (N1–N7) | the modernize report and a config patch |

`audit` mode runs the same workflow; on Migrate it adds M7 and the audit report section, on
Modernize it adds nothing. Read `references/docs.md` before any web fetch — it holds the Context7 library IDs
and doc URLs for Biome, Oxc, and Vite+.
