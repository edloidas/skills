# Install Flags Cheatsheet

When to use which install command in a CI or release workflow.

**Scope.** This file covers every manager, unlike `package-manager-checklist.md`, which
audits pnpm and bun only. The difference is deliberate: the Release subagent reads whatever
workflow a repo already has, so it must recognize `npm ci` and `yarn install --immutable`
on sight. Recognizing a command is not recommending the manager — when a finding needs a
*replacement* command, write it in the manager the repo actually uses.

## Frozen / Immutable Lockfile

Required in every CI and release workflow. Never use a plain `install` command in automated contexts.

| Manager | Command | Behavior |
|---|---|---|
| npm | `npm ci` | Requires `package-lock.json`. Wipes `node_modules` first. Fails if lockfile is out of sync. |
| pnpm | `pnpm install --frozen-lockfile` | Requires `pnpm-lock.yaml`. Fails if out of sync. |
| yarn 1.x | `yarn install --frozen-lockfile` | Requires `yarn.lock`. Fails if out of sync. |
| yarn 2+ (berry) | `yarn install --immutable` | New flag name in berry. Same guarantee. |
| bun | `bun install --frozen-lockfile` | Requires `bun.lockb`. Fails if out of sync. |

**Why mandatory:** A plain `install` can resolve to different versions than the lockfile if the registry serves a compromised response, if a transitive constraint changed, or if a `*`/`^` range now matches a newer version. Frozen-lockfile means "exactly the lockfile, or fail." That guarantee is what you reviewed in the lockfile commit.

## Production / Skip devDependencies

Use ONLY when producing a runtime artifact. Pair with frozen lockfile.

| Manager | Command |
|---|---|
| npm | `npm ci --omit=dev` |
| pnpm | `pnpm install --prod --frozen-lockfile` |
| yarn 1 | `yarn install --production --frozen-lockfile` |
| yarn 2+ | `NODE_ENV=production yarn install --immutable` |
| bun | `bun install --production --frozen-lockfile` |

### When to use `--prod`

- ✅ **Production Docker runtime layer** — the final stage that runs the app.
- ✅ **Deployable container build** (single-stage).
- ✅ **Tarball releases** that bundle `node_modules`.
- ✅ **Serverless function packaging** (Lambda, Cloudflare Workers) where deps ship with code.

### When NOT to use `--prod`

- ❌ **The build step itself** — needs TypeScript, bundlers, linters, test runners.
- ❌ **CI test/lint/typecheck/format workflows** — all require devDependencies.
- ❌ **npm publish workflows** — publishing a library does not ship `node_modules`; consumers install their own deps. The build before publish needs devDependencies.
- ❌ **Storybook / docs deploy workflows** — Storybook itself is typically a devDependency.

### `--omit=dev` as attack-surface reduction in a build job

The rules above are about *correctness* — `--prod` in a build step breaks the build. There is
one case where skipping devDependencies is a security move rather than a size move, and it
inverts the usual dependency layout.

In a monorepo, keep the build toolchain (compiler, bundler) in the **root `dependencies`**
and keep test/lint tooling in `devDependencies`. The build job then installs production
dependencies only:

```bash
pnpm install --prod --frozen-lockfile --ignore-scripts
# bun:  bun install --production --frozen-lockfile --ignore-scripts
# npm:  npm ci --omit=dev --ignore-scripts
```

The build still has its compiler, but the linters, test runners, and their transitive trees
never enter the job that produces the artifact you publish. On a typical repo that is the
larger half of the dependency graph, and every package in it is code that would otherwise
execute next to the build output.

**Two caveats to report with this recommendation, not after it:**

- Moving a package between `dependencies` and `devDependencies` changes the published
  package metadata. Consumers installing the library will now resolve the build toolchain as
  a real dependency unless the package is `private` or the field is stripped at pack time.
  For a published library this is usually the wrong trade; for a private app or a monorepo
  root that is never published, it is free.
- It only pays off if the build job is genuinely separate from the test job. If one job
  installs everything and then runs build *and* test, the flag changes nothing.

This is a suggestion to raise, not a finding to flag — a repo not doing it is not
misconfigured. Pair it with `release-checklist.md` item 9 (the credentialed publish job
installs nothing at all), which is the stronger version of the same idea.

## Multi-stage Docker Pattern

The canonical safe pattern: full deps for build, prod deps for runtime, deps separated from app code so the layer cache holds.

```dockerfile
# Build stage: full deps, build the app
FROM node:20 AS build
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# Runtime stage: prod deps only, copy build output
FROM node:20-slim AS runtime
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile
COPY --from=build /app/dist ./dist
USER node
CMD ["node", "dist/index.js"]
```

## Common Mistakes

- **`npm install` in CI.** Always `npm ci`. The behavior difference is silent and lockfile drift goes unnoticed for weeks.
- **`--prod` in the build step.** Breaks immediately — `tsc`, `vite`, `esbuild`, `vitest` are all devDeps. Confusing error: "command not found".
- **Forgetting `--frozen-lockfile` next to `--prod`.** They are independent flags. Both belong in runtime install commands. `--prod` alone still allows version drift.
- **Using `--no-optional` to bypass missing optional deps.** Fix the dependency tree; don't silence the error.
- **Running install twice (full, then prod).** Doubles cold install time. Multi-stage Docker does this correctly by separating the two installs into separate layers with different `node_modules`.
- **`NODE_ENV=production npm install`.** With npm 7+, setting `NODE_ENV=production` no longer skips devDeps by default unless `--omit=dev` is also passed. Use the explicit flag.

## Quick Audit

```bash
# Find install commands without frozen-lockfile
grep -hE 'npm install|pnpm install|yarn install|bun install' .github/workflows/*.yml \
  | grep -vE '\-\-frozen-lockfile|\-\-immutable|npm ci|--omit=dev'
```

Any line returned is a candidate finding.
