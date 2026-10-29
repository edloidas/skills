# Role Templates

One pattern family per package role. Audit against the family Step 2 selected and ignore the others.

## App (Vite Plus)

```json
{
  "dev": "vp dev",
  "build": "vp run clean && tsgo && vp build",
  "clean": "rm -rf dist coverage reports",
  "typecheck": "tsgo --noEmit",
  "check": "vp check && vp run typecheck",
  "test": "vp test --run",
  "test:ci": "vp test --run --coverage",
  "prepare": "vp config"
}
```

Separate `lint`, `lint:fix`, `format`, and `format:check` scripts are optional in a VP-driven repo. Keep them only when they expose distinct Biome behavior the team actually uses:

```json
{
  "lint": "biome check .",
  "lint:fix": "biome check --write .",
  "format": "biome format --write .",
  "format:check": "biome format ."
}
```

## Monorepo root (pnpm)

```json
{
  "build": "pnpm --filter @edloidas/example run build",
  "check": "pnpm --filter @edloidas/example run check",
  "test": "pnpm --filter @edloidas/example run test",
  "test:ci": "pnpm --filter @edloidas/example run test:ci",
  "dev": "pnpm --filter @edloidas/example exec vp dev",
  "prepare": "pnpm --filter @edloidas/example run prepare"
}
```

Prefer delegation over re-implementing leaf commands in the root package.

## Publishable library (non-VP)

```json
{
  "clean": "rm -rf dist coverage",
  "typecheck": "tsc --noEmit",
  "lint": "biome lint .",
  "lint:fix": "biome lint --write .",
  "format": "biome format --write .",
  "format:check": "biome format .",
  "check": "pnpm typecheck && pnpm lint && pnpm format:check",
  "check:fix": "pnpm typecheck && pnpm lint:fix && pnpm format",
  "build": "pnpm clean && pnpm build:*",
  "test": "vitest run",
  "test:watch": "vitest",
  "test:ci": "vitest run --coverage",
  "validate": "pnpm check && pnpm build && pnpm test:ci",
  "release:dry": "pnpm publish --dry-run --no-git-checks",
  "prepublishOnly": "pnpm validate"
}
```

## Service / bot / CLI (non-VP)

```json
{
  "start": "bun src/index.ts",
  "typecheck": "tsc --noEmit",
  "lint": "biome lint .",
  "lint:fix": "biome lint --write .",
  "format": "biome format --write .",
  "format:check": "biome format .",
  "check": "bun run typecheck && bun run lint && bun run format:check",
  "check:fix": "bun run typecheck && bun run lint:fix && bun run format",
  "test": "bun test",
  "test:watch": "bun test --watch",
  "validate": "bun run check && bun run test"
}
```

`build` is optional here if the runtime already executes the source directly.
