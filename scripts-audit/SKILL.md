---
name: scripts-audit
description: Analyze package.json scripts for consistency, performance, and best practices
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep
---

# Package.json Scripts Audit

## Purpose

Analyze package.json scripts to:
- Find pattern inconsistencies
- Identify performance optimizations
- Check for missing standard scripts
- Verify command completeness

## When to Use This Skill

Use when the user asks to:
- "Audit my npm scripts"
- "Check package.json scripts"
- "Optimize build scripts"
- "Review scripts for consistency"

Trigger phrases: "scripts audit", "package.json scripts", "npm scripts", "pnpm scripts"

## Workflow

### Step 1: Read Package.json Scripts

```bash
cat package.json | jq '.scripts'
```

Extract and categorize scripts by purpose:
- Build scripts (build, build:*, compile)
- Test scripts (test, test:*, coverage)
- Lint scripts (lint, lint:*, format)
- Dev scripts (dev, start, serve)
- Utility scripts (clean, prepare, prepack)

### Step 2: Check Pattern Consistency

Look for the same tool invoked with different patterns:

**Problem example:**
```json
{
  "lint": "eslint '**/*.{ts,tsx}'",
  "lint:fix": "eslint 'src/**/*.{ts,tsx}' --fix",
  "lint:ci": "eslint 'src/**/*.{ts,tsx}'"
}
```

**Issues:**
- `lint` uses `**/*` (all files)
- `lint:fix` and `lint:ci` use `src/**/*` (source only)
- Running `lint` checks more files than `lint:fix`

**Fixed:**
```json
{
  "lint": "eslint 'src/**/*.{ts,tsx}'",
  "lint:fix": "eslint 'src/**/*.{ts,tsx}' --fix",
  "lint:ci": "eslint --no-cache 'src/**/*.{ts,tsx}'"
}
```

### Step 3: Check for Missing Flags

#### Cache Flags
```json
// Missing cache (slower)
"lint": "eslint 'src/**/*.ts'"

// With cache (faster)
"lint": "eslint --cache 'src/**/*.ts'"
```

#### Parallelization
```json
// Sequential
"build": "pnpm build:lib && pnpm build:css"

// Parallel with pnpm
"build": "pnpm /^build:.*$/"
// Or with --color for output
"build": "pnpm --color /^build:.*$/"
```

#### CI-specific flags
```json
// Dev (use cache)
"lint": "eslint --cache 'src/**/*.ts'"

// CI (no cache, strict)
"lint:ci": "eslint --no-cache 'src/**/*.ts' --max-warnings 0"
```

### Step 4: Check for Standard Scripts

Verify presence of common scripts:

| Script | Purpose | Required |
|--------|---------|----------|
| `build` | Production build | Yes |
| `dev` or `start` | Development server | Yes |
| `test` | Run tests | Recommended |
| `lint` | Run linter | Yes |
| `format` | Format code | Recommended |
| `clean` | Remove build artifacts | Recommended |
| `typecheck` | TypeScript checking | If using TS |

**Missing script examples:**
```json
{
  // Missing clean script
  "build": "vite build",

  // Should add:
  "clean": "rm -rf dist coverage",
  "build": "pnpm clean && vite build"
}
```

### Step 5: Check Composite Scripts

Verify composite scripts run in optimal order:

```json
// Good: typecheck before lint (fail fast)
"check": "pnpm typecheck && pnpm lint && pnpm format:check"

// Good: parallel when independent
"check": "concurrently 'pnpm typecheck' 'pnpm lint' 'pnpm format:check'"
```

Check `prepublishOnly` and `prepack` scripts:
```json
{
  "prepublishOnly": "pnpm check && pnpm build && pnpm size"
}
```

### Step 6: Check for Redundant Commands

Look for:
- Same command defined multiple ways
- Unused scripts
- Scripts that could be combined

**Redundancy example:**
```json
{
  "test": "jest",
  "test:unit": "jest",        // Same as test?
  "test:watch": "jest --watch"
}
```

### Step 7: Check Tool-Specific Best Practices

#### ESLint
```json
{
  "lint": "eslint --cache --concurrency auto 'src/**/*.ts'",
  "lint:fix": "eslint --cache --fix 'src/**/*.ts'",
  "lint:ci": "eslint --no-cache --max-warnings 0 'src/**/*.ts'"
}
```

#### Biome
```json
{
  "format": "biome format --write .",
  "format:check": "biome format .",
  "lint": "biome check .",
  "lint:fix": "biome check --write ."
}
```

#### TypeScript
```json
{
  "typecheck": "tsc --noEmit",
  // Or with project references
  "typecheck": "tsc --build --noEmit"
}
```

#### Vite
```json
{
  "dev": "vite",
  "build": "vite build",
  "preview": "vite preview"
}
```

### Step 8: Check Pre/Post Hooks

Verify hooks are used appropriately:

```json
{
  "prepare": "husky",              // Good: setup git hooks
  "prepack": "pnpm build",         // Good: ensure built before pack
  "prepublishOnly": "pnpm check"   // Good: verify before publish
}
```

**Avoid:**
- `pretest` that duplicates CI setup
- `postinstall` for build steps (use `prepare`)

### Step 9: Generate Report

```markdown
## Scripts Audit Report

### Consistency Issues
- [ ] Pattern mismatch in lint scripts

### Performance Issues
- [ ] Missing `--cache` in lint script
- [ ] Sequential build could be parallel

### Missing Scripts
- [ ] No `clean` script
- [ ] No `format:check` script

### Recommendations
1. Align lint patterns: change `lint` to use `src/**/*`
2. Add `--cache` flag to lint script
3. Add clean script: `"clean": "rm -rf dist"`
```

## Common Patterns

### Minimal Setup
```json
{
  "dev": "vite",
  "build": "vite build",
  "lint": "eslint --cache .",
  "format": "prettier --write .",
  "test": "vitest"
}
```

### Full Setup with Biome
```json
{
  "dev": "vite",
  "build": "pnpm clean && vite build",
  "clean": "rm -rf dist",
  "check": "pnpm typecheck && pnpm lint && pnpm format:check",
  "check:fix": "pnpm typecheck && pnpm lint:fix && pnpm format",
  "typecheck": "tsc --noEmit",
  "lint": "biome check . && eslint --cache 'src/**/*.ts'",
  "lint:fix": "biome check --write . && eslint --cache --fix 'src/**/*.ts'",
  "lint:ci": "biome check . && eslint --no-cache 'src/**/*.ts'",
  "format": "biome format --write .",
  "format:check": "biome format .",
  "test": "vitest",
  "test:ci": "vitest run --coverage",
  "prepare": "husky"
}
```

## Keywords

package.json, scripts, npm, pnpm, consistency, performance, build, lint, format, test
