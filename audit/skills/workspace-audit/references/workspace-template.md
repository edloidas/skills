## Optimized pnpm 10+ Workspace Template

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

# Security: reject packages published less than 24h ago (10.16+)
minimumReleaseAge: 1440
# Exempt bleeding-edge or trusted packages from the age check (10.17+):
# minimumReleaseAgeExclude:
#   - '@org/internal-package'

# Publisher trust enforcement — complements minimumReleaseAge (10.21+)
trustPolicy: audit
# trustPolicyExclude:  # exempt specific packages (10.22+)
#   - '@myorg/internal'

# Restrict exotic (git/file/url) dep sources to direct deps only (10.26+)
blockExoticSubdeps: true

# Build hooks (pnpm 10.0–10.25): choose one model
# Whitelist: only listed packages may run install scripts
onlyBuiltDependencies:
  - esbuild
# Blacklist: skip install scripts for these
# ignoredBuiltDependencies:
#   - unrs-resolver
#   - sharp

# Build hooks (pnpm 10.26+): single map replaces the two settings above
# allowBuilds:
#   esbuild: true
#   unrs-resolver: false
#   sharp: false

# Fail install if any dep runs unchecked build scripts (10.3+)
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
    "pnpm": ">= 10.16.0"
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
