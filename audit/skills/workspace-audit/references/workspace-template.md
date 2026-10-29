## Optimized pnpm Workspace Template (10.26+)

### pnpm-workspace.yaml
```yaml
packages:
  - 'packages/*'
  - 'apps/*'

catalog:
  # Pin all shared deps here — use catalog: in each package, never hardcode versions
  react: ^19.0.0
  react-dom: ^19.0.0
  typescript: ^5.0.0
  vite: ^6.0.0
  vitest: ^3.0.0
  # npm: aliases swap a package name for a different implementation:
  # vite: npm:@org/custom-vite-fork@^1.0.0

# Enforce all packages use catalog: for any dep defined in the catalog (10.12.1+)
catalogMode: force

# Remove unused catalog entries on install (10.15+)
cleanupUnusedCatalogs: true

# Supply-chain settings follow security-audit's package-manager checklist (pnpm 10.26+).
# Release-age gate in minutes: 4320 = 72h, the audit's floor
minimumReleaseAge: 4320
minimumReleaseAgeStrict: true
# minimumReleaseAgeExclude:
#   - '@myorg/*'

# Fail the install when a version's publish evidence is weaker than earlier releases (10.21+)
trustPolicy: no-downgrade

# Dependency build scripts are denied by default; this map is the audit log
allowBuilds:
  esbuild: true    # bundler ships a native binary via postinstall
  sharp: false
strictDepBuilds: true

# Force transitive consumers to use catalog versions
overrides:
  vite: 'catalog:'
  vitest: 'catalog:'

# Suppress peer dep warnings for packages with flexible peer requirements
# peerDependencyRules:
#   allowAny:
#     - vite
#   allowedVersions:
#     vite: '*'
```

### Root package.json
```json
{
  "name": "my-monorepo",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "pnpm -r run build",
    "test": "pnpm -r run test",
    "check": "pnpm -r run check"
  },
  "engines": {
    "node": ">= 22.0.0",
    "pnpm": ">= 10.26.0"
  }
}
```

### Individual package/app package.json
```json
{
  "name": "@myorg/app",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "react": "catalog:",
    "react-dom": "catalog:"
  },
  "devDependencies": {
    "vite": "catalog:",
    "vitest": "catalog:",
    "typescript": "catalog:"
  }
}
```

### .npmrc

Only include settings that meaningfully change behavior. Most copy-pasted `.npmrc` settings are already defaults in pnpm 10 or are superseded by the workspace protocol.

```ini
# Private registry for scoped packages (if needed)
# @myorg:registry=https://npm.myorg.com/

# Windows cross-platform script compatibility
# shell-emulator=true
```

**Avoid:**
- `auto-install-peers=true` — default in pnpm 9+
- `prefer-frozen-lockfile=true` — default in pnpm 10; use `--frozen-lockfile` CLI flag in CI for hard-fail
- `prefer-workspace-packages=true` — superseded by `workspace:` protocol
