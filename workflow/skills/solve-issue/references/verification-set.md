# Choosing the Verification Set

## Script detection

Read `package.json` if present. Pick the first script that exists in each group:

| Group      | Candidates (first wins)           |
| ---------- | --------------------------------- |
| Type-check | `typecheck`, `tsc`, `check-types` |
| Lint       | `lint`, `lint:check`              |
| Build      | `build`, `compile`                |
| Unit test  | `test`, `test:unit`               |

Pick the runner from the lockfile:

- `pnpm-lock.yaml` → `pnpm run <script>`
- `bun.lockb` or `bun.lock` → `bun run <script>`
- `yarn.lock` → `yarn <script>`
- else → `npm run <script>`

Install first when `node_modules` is missing, or when the lockfile is newer than the
install marker the package manager wrote inside it — `.package-lock.json` (npm),
`.modules.yaml` (pnpm), `.yarn-state.yml` (Yarn 2+), `.yarn-integrity` (Yarn 1), or the
`node_modules` directory itself where there is none. Stale dependencies fail checks in code
this branch never touched. Use the form that cannot rewrite the lockfile: `pnpm install
--frozen-lockfile`, `bun install --frozen-lockfile`, `yarn install --immutable` when
`.yarnrc.yml` exists (Yarn 2+), else `yarn install --frozen-lockfile`, `npm ci` — plain
`npm install` when there is no lockfile at all. A failed install is not a code defect, so
it skips Phase 3: stop and hand back with its output. Name the install in the Phase 4
closing line.

A repo with no `package.json` declares its checks somewhere else — a `Makefile`, a task
runner, a CI workflow. Read what the repo actually declares rather than assuming a
JavaScript project.

## Scope-aware selection

Use the changed file set from the working tree, taken with the `Fork:` SHA recorded in
Phase 2 by the rule that phase states — never the `<fork>..HEAD` range.

| Changed | Run |
| ------- | --- |
| Source code (`src/`, `lib/`, `app/`, similar) | Type-check + build (if present) + unit tests |
| Only docs, config, CI, or plain text | Lint only, or nothing when lint is not configured |
| Component or presentation layer | Type-check, plus whatever script builds the component harness the repo defines |
| Test files | The unit test script, always — Phase 4.5 re-runs it after applying its verdicts |
