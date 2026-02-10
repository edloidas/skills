---
name: workspace-audit
description: Analyze pnpm workspace configuration and monorepo setup for optimization
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep
---

# Workspace Audit (pnpm/npm/yarn)

## Purpose

Analyze monorepo workspace configuration to:
- Optimize dependency management
- Check workspace protocol usage
- Verify build order and dependencies
- Audit `.npmrc` settings

## When to Use This Skill

Use when the user asks to:
- "Audit my monorepo"
- "Check workspace configuration"
- "Optimize pnpm workspace"
- "Review monorepo setup"

Trigger phrases: "workspace audit", "monorepo", "pnpm workspace", "workspaces"

## Workflow

### Step 1: Identify Workspace Type

Check for workspace configuration:

```bash
# pnpm
cat pnpm-workspace.yaml 2>/dev/null

# npm/yarn
cat package.json | jq '.workspaces'

# Check for Nx or Turbo
ls -la nx.json turbo.json 2>/dev/null
```

### Step 2: Analyze Workspace Structure

#### pnpm-workspace.yaml
```yaml
# Good: Explicit patterns
packages:
  - 'packages/*'
  - 'apps/*'
  - 'tools/*'

# Avoid: Too broad
packages:
  - '**'
```

#### package.json workspaces (npm/yarn)
```json
{
  "workspaces": [
    "packages/*",
    "apps/*"
  ]
}
```

### Step 3: Check Workspace Protocol Usage

**Good: Using workspace protocol**
```json
// packages/app/package.json
{
  "dependencies": {
    "@myorg/shared": "workspace:*",
    "@myorg/utils": "workspace:^"
  }
}
```

**Problems:**
- `"workspace:*"` - Always uses local version
- Hardcoded versions instead of workspace protocol
- Missing internal dependencies

**Check all package.json files:**
```bash
# Find internal package references
fd -t f 'package.json' packages apps | xargs grep -l '@myorg/'
```

### Step 4: Check Dependency Hoisting

#### .npmrc settings
```ini
# pnpm hoisting settings
hoist=true
shamefully-hoist=true  # Only if needed for compatibility

# Strict mode (recommended)
strict-peer-dependencies=true
auto-install-peers=true

# Performance
prefer-frozen-lockfile=true
```

#### Check for hoisting issues
```bash
# List what's hoisted
pnpm list --depth 0

# Check for duplicate packages
pnpm dedupe --check
```

### Step 5: Check Catalog Usage (pnpm 9+)

**pnpm-workspace.yaml with catalog:**
```yaml
packages:
  - 'packages/*'

catalog:
  react: ^18.2.0
  typescript: ^5.4.0
  vitest: ^1.6.0
```

**Using in packages:**
```json
{
  "dependencies": {
    "react": "catalog:"
  },
  "devDependencies": {
    "typescript": "catalog:",
    "vitest": "catalog:"
  }
}
```

**Benefits:**
- Single source of truth for versions
- Easy version updates
- Consistent versions across packages

### Step 6: Check Build Order

Verify package dependencies are correctly defined:

```json
// packages/app/package.json
{
  "name": "@myorg/app",
  "dependencies": {
    "@myorg/ui": "workspace:*",      // Depends on ui
    "@myorg/utils": "workspace:*"    // Depends on utils
  }
}
```

**Check build order:**
```bash
# pnpm topological sort
pnpm -r exec echo

# Or with Turbo
turbo run build --dry-run
```

### Step 7: Check ignoredBuiltDependencies

Optimize install time by skipping native builds:

```json
// package.json
{
  "pnpm": {
    "ignoredBuiltDependencies": [
      "@tailwindcss/oxide",
      "esbuild",
      "unrs-resolver",
      "sharp"
    ]
  }
}
```

**When to use:**
- Native dependencies that come pre-built
- Dependencies with slow post-install scripts
- Packages that don't need building in dev

### Step 8: Check .npmrc Configuration

**Recommended settings:**
```ini
# Use strict mode
strict-peer-dependencies=true
auto-install-peers=true

# Performance
prefer-frozen-lockfile=true
prefer-workspace-packages=true

# Security
ignore-scripts=false  # Or true if you don't trust scripts

# Registry (if using private)
# @myorg:registry=https://npm.myorg.com/
```

### Step 9: Check for Common Issues

#### Missing workspace: prefix
```json
// BAD: Hardcoded version
"@myorg/utils": "^1.0.0"

// GOOD: Workspace protocol
"@myorg/utils": "workspace:*"
```

#### Circular dependencies
```bash
# Check with madge
npx madge --circular packages/*/src
```

#### Inconsistent versions
```bash
# Check with syncpack
npx syncpack list-mismatches
```

### Step 10: Generate Report

```markdown
## Workspace Audit Report

### Structure
- Type: pnpm workspace
- Packages: 5 (3 apps, 2 libs)

### Workspace Protocol
- [x] Using workspace:* for internal deps
- [ ] 2 packages use hardcoded versions

### Dependencies
- [ ] Missing catalog for shared versions
- [x] No circular dependencies detected

### Configuration
- [x] .npmrc has strict settings
- [ ] Missing ignoredBuiltDependencies

### Recommendations
1. Add catalog to pnpm-workspace.yaml
2. Update @myorg/utils to use workspace:*
3. Add esbuild to ignoredBuiltDependencies
```

## Optimized Workspace Template

### pnpm-workspace.yaml
```yaml
packages:
  - 'packages/*'
  - 'apps/*'

catalog:
  # Framework
  react: ^18.3.0
  react-dom: ^18.3.0

  # Build tools
  typescript: ^5.4.0
  vite: ^5.2.0

  # Testing
  vitest: ^1.6.0

  # Linting
  eslint: ^9.0.0
  '@biomejs/biome': ^1.7.0
```

### Root package.json
```json
{
  "name": "my-monorepo",
  "private": true,
  "scripts": {
    "build": "turbo run build",
    "dev": "turbo run dev",
    "lint": "turbo run lint",
    "test": "turbo run test"
  },
  "devDependencies": {
    "turbo": "^2.0.0"
  },
  "pnpm": {
    "ignoredBuiltDependencies": [
      "esbuild",
      "@tailwindcss/oxide"
    ]
  }
}
```

### .npmrc
```ini
strict-peer-dependencies=true
auto-install-peers=true
prefer-frozen-lockfile=true
prefer-workspace-packages=true
```

## Keywords

pnpm, npm, yarn, workspace, monorepo, dependencies, hoisting, catalog, turbo, nx
