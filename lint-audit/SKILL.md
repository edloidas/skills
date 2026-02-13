---
name: lint-audit
description: Analyze ESLint, Biome, and Oxlint configurations for performance, coverage, and tool overlap
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash, Read, Glob, Grep
---

# Lint Configuration Audit

## Purpose

Analyze linting configurations to:
- Identify performance bottlenecks
- Find tool overlap (ESLint vs Biome vs Oxlint)
- Check pattern consistency across scripts
- Recommend optimizations

## When to Use This Skill

Use when the user asks to:
- "Audit my lint config"
- "Optimize ESLint performance"
- "Check for Biome/ESLint overlap"
- "Review linting setup"
- "Speed up linting"

Trigger phrases: "lint audit", "eslint optimize", "biome overlap", "linting performance"

## Workflow

### Step 1: Identify Linting Tools

Search for configuration files:
```bash
# ESLint
fd -t f '(eslint\.config\.(js|ts|mjs|cjs)|\.eslintrc\..*|\.eslintignore)$' --max-depth 2

# Biome
fd -t f 'biome\.json(c)?$' --max-depth 2

# Oxlint
fd -t f '(oxlint\.json|\.oxlintrc\.json)$' --max-depth 2
```

Check package.json for:
- `eslint`, `@eslint/*` dependencies
- `@biomejs/biome` dependency
- `oxlint` dependency

### Step 2: Analyze ESLint Performance

#### Check for Type-Aware Rules
Type-aware rules are the slowest. Look for:
```javascript
// These require TypeScript parsing (slow)
parserOptions: {
  project: true,
  projectService: true,
}
```

If using type-aware rules, ensure they're necessary. Consider moving type checks to `tsc --noEmit` instead.

#### Check Cache Usage
Look in package.json scripts for `--cache` flag:
```json
// Good
"lint": "eslint --cache 'src/**/*.ts'"

// Missing cache (slower)
"lint": "eslint 'src/**/*.ts'"
```

#### Check Parallelization
Look for `--concurrency` flag (ESLint 9+):
```json
"lint": "eslint --cache --concurrency auto 'src/**/*.ts'"
```

### Step 3: Check File Pattern Consistency

Compare patterns across related scripts:

```json
// PROBLEM: Inconsistent patterns
"lint": "eslint '**/*.{ts,tsx}'",           // All files
"lint:fix": "eslint 'src/**/*.{ts,tsx}'",   // Only src
"lint:ci": "eslint 'src/**/*.{ts,tsx}'"     // Only src
```

All lint scripts should use the same file patterns unless there's a specific reason.

### Step 4: Check Tool Overlap (Biome vs ESLint)

If both Biome and ESLint are present, check for duplicate coverage.

**Rules Biome handles that ESLint can disable:**

See `references/biome-eslint-overlap.md` for the full list.

Key categories:
- Formatting (Biome is faster)
- Import sorting
- Basic code quality rules
- TypeScript-specific rules Biome covers

**Recommended ESLint-only rules when using Biome:**
- Type-aware rules (`@typescript-eslint/*` with type info)
- React hooks rules (`eslint-plugin-react-hooks`)
- Accessibility rules (`eslint-plugin-jsx-a11y`)
- Framework-specific rules

### Step 5: Check Ignore Patterns

#### ESLint Flat Config
```javascript
// eslint.config.js
export default [
  {
    ignores: [
      'node_modules/',
      'dist/',
      'build/',
      'coverage/',
      '**/*.d.ts',
    ],
  },
  // ...
];
```

#### Biome
```json
// biome.json
{
  "files": {
    "ignore": ["node_modules", "dist", "build"]
  }
}
```

**Verify:**
- Build outputs are ignored
- Generated files are ignored
- Test coverage reports are ignored
- No unnecessary files are being linted

### Step 6: Measure Actual Performance

Run timing analysis:
```bash
# ESLint with timing
TIMING=1 pnpm exec eslint 'src/**/*.ts'

# Or with time command
time pnpm lint
```

Look for:
- Total time
- Slowest rules (if TIMING=1 supported)
- Files being linted (count)

### Step 7: Check Config File vs CLI Redundancy

Ensure there's no duplication between:
- Config file settings
- CLI arguments in package.json

Example redundancy:
```javascript
// eslint.config.js
{ ignores: ['dist/'] }

// package.json - redundant ignore
"lint": "eslint --ignore-pattern 'dist/' 'src/**/*.ts'"
```

### Step 8: Generate Report

```markdown
## Lint Audit Report

### Tools Detected
- ESLint 9.x (flat config)
- Biome 2.x

### Performance Issues
- [ ] Missing `--cache` flag in lint script
- [ ] Type-aware rules enabled (adds ~3s overhead)

### Consistency Issues
- [ ] Pattern mismatch: lint uses `**/*`, lint:fix uses `src/**/*`

### Tool Overlap
- [ ] 8 ESLint rules duplicate Biome functionality

### Recommendations
1. Add `--cache` to lint script
2. Align file patterns across all lint scripts
3. Disable ESLint rules covered by Biome (see list)
```

## Bundled References

- `references/biome-eslint-overlap.md` - Complete list of overlapping rules

## Output Format

Always provide:
1. **Tools detected** - Which linters are in use
2. **Performance analysis** - Timing and bottlenecks
3. **Consistency check** - Pattern alignment
4. **Overlap analysis** - Duplicate coverage
5. **Actionable recommendations** - Specific changes

## Keywords

eslint, biome, oxlint, linting, performance, cache, rules, overlap, consistency, formatting
