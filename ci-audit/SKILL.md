---
name: ci-audit
description: Analyze GitHub Actions workflows for parallelization, caching, and optimization
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash, Read, Glob, Grep
---

# CI/CD Audit (GitHub Actions)

## Purpose

Analyze GitHub Actions workflows to:
- Identify parallelization opportunities
- Optimize caching strategies
- Reduce CI run time
- Improve workflow efficiency

## When to Use This Skill

Use when the user asks to:
- "Audit my CI/CD"
- "Optimize GitHub Actions"
- "Speed up CI"
- "Review workflow performance"
- "Parallelize CI jobs"

Trigger phrases: "ci audit", "github actions", "workflow optimize", "ci performance"

## Workflow

### Step 1: Find Workflow Files

```bash
fd -t f '\.ya?ml$' .github/workflows/
```

Common workflow files:
- `ci.yml` - Main CI pipeline
- `release.yml` - Release/publish workflow
- `deploy.yml` - Deployment workflow
- `pr.yml` - Pull request checks

### Step 2: Analyze Job Structure

Look for sequential jobs that could run in parallel.

**Problem: Sequential steps in one job**
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm install
      - run: npm run typecheck    # Independent
      - run: npm run lint         # Independent
      - run: npm run format:check # Independent
      - run: npm run build        # Depends on above
      - run: npm run test         # Depends on build
```

**Solution: Parallel jobs**
```yaml
jobs:
  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          cache: 'npm'
      - run: npm ci
      - run: npm run typecheck

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          cache: 'npm'
      - run: npm ci
      - run: npm run lint

  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          cache: 'npm'
      - run: npm ci
      - run: npm run format:check

  build:
    needs: [typecheck, lint, format]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          cache: 'npm'
      - run: npm ci
      - run: npm run build
      - run: npm run test
```

**Time savings:** Independent jobs run simultaneously instead of sequentially.

### Step 3: Check Caching Configuration

#### Node.js/pnpm Caching
```yaml
# Good: Using setup-node cache
- uses: actions/setup-node@v4
  with:
    node-version-file: '.node-version'
    cache: 'pnpm'

# pnpm requires action-setup first
- uses: pnpm/action-setup@v4
- uses: actions/setup-node@v4
  with:
    cache: 'pnpm'
```

#### Custom Caching
```yaml
# Cache node_modules (if not using setup-node cache)
- uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: |
      ${{ runner.os }}-node-

# Turbo cache (for monorepos)
- uses: actions/cache@v4
  with:
    path: .turbo
    key: ${{ runner.os }}-turbo-${{ github.sha }}
    restore-keys: |
      ${{ runner.os }}-turbo-
```

#### Build Artifact Caching
```yaml
# Cache build outputs between jobs
- uses: actions/upload-artifact@v4
  with:
    name: build
    path: dist/

# In dependent job
- uses: actions/download-artifact@v4
  with:
    name: build
    path: dist/
```

### Step 4: Check Concurrency Settings

```yaml
# Good: Cancel outdated runs
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

# For deployment (don't cancel)
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false
```

### Step 5: Check Conditional Execution

#### Path Filters
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'package.json'
      - '.github/workflows/ci.yml'
  pull_request:
    branches: [main]
    paths:
      - 'src/**'
```

#### Job Conditions
```yaml
jobs:
  deploy:
    if: github.ref == 'refs/heads/main'
    # ...

  release:
    if: startsWith(github.ref, 'refs/tags/v')
    # ...
```

### Step 6: Check Matrix Builds

For testing across multiple versions:
```yaml
jobs:
  test:
    strategy:
      matrix:
        node: [18, 20, 22]
        os: [ubuntu-latest, macos-latest]
      fail-fast: false
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
```

### Step 7: Check Runner Selection

| Runner | Use Case |
|--------|----------|
| `ubuntu-latest` | Most Node.js projects |
| `macos-latest` | iOS/macOS builds |
| `windows-latest` | Windows-specific tests |
| Self-hosted | Special requirements |

**Note:** `ubuntu-latest` is fastest and cheapest.

### Step 8: Check Workflow Triggers

```yaml
# Good: Specific triggers
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Avoid: Too broad
on: [push, pull_request]  # Runs twice on PR
```

### Step 9: Check for Optimizations

#### Shallow Clone
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 1  # Default, shallow clone
```

#### Install Optimization
```yaml
# npm
- run: npm ci  # Faster than npm install

# pnpm
- run: pnpm install --frozen-lockfile

# yarn
- run: yarn --frozen-lockfile
```

### Step 10: Generate Report

```markdown
## CI Audit Report

### Parallelization
- [ ] Jobs run sequentially that could be parallel
- [ ] Estimated savings: ~30s per run

### Caching
- [x] Node modules cached via setup-node
- [ ] Missing Turbo cache for monorepo

### Efficiency
- [x] Concurrency with cancel-in-progress
- [ ] No path filters (runs on all changes)

### Recommendations
1. Split CI into parallel jobs (typecheck, lint, format)
2. Add path filters to skip irrelevant runs
3. Use artifact caching for build outputs
```

## Optimized CI Template

```yaml
name: CI

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'package.json'
      - 'pnpm-lock.yaml'
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.node-version'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm typecheck

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.node-version'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint:ci

  build:
    needs: [typecheck, lint]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.node-version'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
      - run: pnpm test:ci
```

## Keywords

github actions, ci, cd, workflow, parallelization, caching, optimization, jobs, pipeline
