# Workspace Template (pnpm 10.26+)

Workspace-section reference: the target shape Steps 4–5 audit against.

## pnpm-workspace.yaml
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

# Supply-chain settings: graded by security-audit, not by package-audit — Step 1 only records
# which keys are set. Shown so the template is complete (pnpm 10.26+).
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

## Root package.json

`private: true`, `engines` pinning `node` and `pnpm` (`>= 10.26.0` for the fields above), and
scripts that delegate — the Monorepo root family in `role-templates.md`.

## Individual package/app package.json
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

## .npmrc

Only include settings that change behavior. Most copy-pasted `.npmrc` lines are pnpm defaults
or superseded by the workspace protocol — Step 5 flags these:

| Setting | Issue |
|---|---|
| `auto-install-peers=true` | Default in pnpm 9+ — redundant |
| `prefer-frozen-lockfile=true` | Default in pnpm 10 — redundant; use `--frozen-lockfile` in CI for hard-fail behavior |
| `prefer-workspace-packages=true` | Superseded by the `workspace:` protocol |
| `strict-peer-dependencies=true` | Not a default; keep only when hard failures on peer mismatches are wanted |

Legitimate entries:

```ini
# Private registry for scoped packages
# @myorg:registry=https://npm.myorg.com/

# Windows cross-platform script compatibility
# shell-emulator=true
```
