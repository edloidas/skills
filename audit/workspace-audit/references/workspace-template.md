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
