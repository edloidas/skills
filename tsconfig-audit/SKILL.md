---
name: tsconfig-audit
description: Analyze TypeScript configurations for performance, safety, and modern best practices
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash, Read, Glob, Grep
---

# TSConfig Audit

## Purpose

Analyze TypeScript configuration files (`tsconfig.json` and related configs) for:
- Performance optimizations
- Type safety improvements
- Modern TypeScript 5.x features
- Project structure best practices

## When to Use This Skill

Use when the user asks to:
- "Audit my TypeScript config"
- "Optimize tsconfig"
- "Check TypeScript settings"
- "Review tsconfig for performance"
- "Update TypeScript configuration"

Trigger phrases: "tsconfig audit", "typescript config", "tsconfig optimize", "ts config review"

## Workflow

### Step 1: Find Configuration Files

Search for TypeScript configuration files:
```bash
fd -t f 'tsconfig.*\.json$' --max-depth 3
```

Look for:
- `tsconfig.json` (root config)
- `tsconfig.app.json` (application code)
- `tsconfig.node.json` (Node.js/build tools)
- `tsconfig.test.json` (test files)

### Step 2: Analyze Performance Options

Check for these performance-related options:

| Option | Recommended | Purpose |
|--------|-------------|---------|
| `incremental` | `true` | Enable incremental compilation |
| `tsBuildInfoFile` | Set path | Store build info for faster rebuilds |
| `skipLibCheck` | `true` | Skip type checking declaration files |
| `isolatedModules` | `true` | Better parallelization, esbuild/Vite compat |

**Missing `incremental`:**
```json
"incremental": true,
"tsBuildInfoFile": "./node_modules/.tmp/tsconfig.tsbuildinfo"
```

**Missing `isolatedModules`:**
Important for projects using Vite, esbuild, or other transpilers:
```json
"isolatedModules": true
```

### Step 3: Analyze Safety Options

Check strict mode and additional safety options:

| Option | Recommended | Purpose |
|--------|-------------|---------|
| `strict` | `true` | Enable all strict type-checking |
| `noUncheckedIndexedAccess` | `true` | Add `undefined` to index signatures |
| `noImplicitOverride` | `true` | Require `override` keyword |
| `forceConsistentCasingInFileNames` | `true` | Consistent file casing (CI safety) |
| `noFallthroughCasesInSwitch` | `true` | Prevent switch fallthrough bugs |
| `noUncheckedSideEffectImports` | `true` | Check side-effect imports (TS 5.5+) |
| `erasableSyntaxOnly` | `true` | Only allow erasable type syntax (TS 5.5+) |

**High-impact additions:**
```json
"forceConsistentCasingInFileNames": true,
"noImplicitOverride": true,
"noUncheckedIndexedAccess": true
```

Note: `noUncheckedIndexedAccess` may require code changes where array/object access needs explicit undefined checks.

### Step 4: Analyze Module Settings

Check module resolution configuration:

| Option | Modern Value | Purpose |
|--------|--------------|---------|
| `moduleResolution` | `"bundler"` | For Vite/webpack/esbuild projects |
| `module` | `"ESNext"` | Latest ES module features |
| `target` | `"ES2022"` or later | Modern JS output |
| `verbatimModuleSyntax` | `true` | Preserve import/export syntax |
| `moduleDetection` | `"force"` | Treat all files as modules |

**For bundler-based projects (Vite, webpack):**
```json
"moduleResolution": "bundler",
"verbatimModuleSyntax": true,
"moduleDetection": "force"
```

### Step 5: Check Project References

For multi-config setups, verify:
- Root `tsconfig.json` uses `references` array
- Each referenced config has `composite: true` or appropriate settings
- Separate configs for different environments (app, node, test)

**Good pattern:**
```json
// tsconfig.json (root)
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
```

### Step 6: Check Include/Exclude Patterns

Verify patterns are efficient:
- `include` should be specific, not `["**/*"]`
- `exclude` should cover build outputs, node_modules
- Config files should have minimal scope

**Example efficient patterns:**
```json
// tsconfig.app.json
"include": ["src/**/*"],
"exclude": ["node_modules", "dist", "**/*.test.ts"]

// tsconfig.node.json
"include": ["vite.config.ts", "eslint.config.ts"]
```

### Step 7: Check for Outdated Options

Flag deprecated or outdated options:

| Outdated | Replacement |
|----------|-------------|
| `moduleResolution: "node"` | `"bundler"` or `"node16"` |
| `importsNotUsedAsValues` | `verbatimModuleSyntax` |
| `preserveValueImports` | `verbatimModuleSyntax` |
| `target: "ES5"` | `"ES2022"` (unless targeting old browsers) |

### Step 8: Generate Report

Present findings in a structured format:

```markdown
## TSConfig Audit Report

### Performance
- [ ] Missing `incremental: true`
- [x] Has `skipLibCheck: true`

### Safety
- [x] `strict: true` enabled
- [ ] Missing `noUncheckedIndexedAccess`

### Module Settings
- [x] Modern `moduleResolution: "bundler"`

### Recommendations
1. Add `incremental: true` for faster rebuilds
2. Add `noUncheckedIndexedAccess: true` (may need code changes)
```

## Output Format

Always provide:
1. **Current state** - What's configured now
2. **Issues found** - Problems or missing optimizations
3. **Recommendations** - Specific changes with code snippets
4. **Impact notes** - Which changes may require code modifications

## Keywords

typescript, tsconfig, configuration, performance, strict, incremental, safety, module resolution, project references
