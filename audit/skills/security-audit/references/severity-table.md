# Severity Calibration Table

One row per finding shape, with the severity every subagent must use for it. Step 3 sorts
the aggregated report by these values, so consistency across areas matters more than any
individual row. The per-area checklists carry the reasoning; this file is the lookup.

`(policy)` marks a finding where nothing is currently exploitable but a hardening primitive
this audit treats as mandatory is absent.

## Actions

| Finding | Severity | Fix |
|---|---|---|
| `uses: foo/bar@v1` (version tag) | high | `pinact run` |
| `uses: foo/bar@master` / `@main` / `@latest` (branch ref) | critical | `pinact run` after reviewing the action's recent commits — branch can change on every merge |
| Workflow without `permissions:` | medium | Add `permissions: contents: read` at workflow level |
| `actions/checkout` without `persist-credentials: false` (no `git push`) | medium | Add `with: persist-credentials: false` |
| `pull_request_target` + checkout of PR ref | critical | Split trusted/untrusted parts; remove PR checkout |
| `pull_request_target` without checkout | informational | Document as intentionally safe |
| Cache key without `github.sha` / `hashFiles` | medium | Add high-entropy component |
| No workflow linter in CI | medium | Add a `zizmor` workflow (see `actions-checklist.md` item 9) |
| Stale branch carrying an already-fixed workflow vulnerability | high | Delete the branch, or forward-port the fix |

## Release

npm as a *publish target* is in scope even though npm as an *installer* is not (see Package
manager below): a pnpm or bun project still publishes to the npm registry, and
`npm stage publish` is the right command there regardless of what installs the tree.

| Finding | Severity | Fix |
|---|---|---|
| Release triggers on `push: branches` | critical | Switch to `tags: ['v*']` |
| Unfrozen install in release workflow | high | `pnpm install --frozen-lockfile` / `bun install --frozen-lockfile` |
| Public package without provenance | medium | Enable Trusted Publishers (OIDC) |
| Missing `dependabot.yml` github-actions entry | medium | Add `package-ecosystem: "github-actions"` |
| Dependency cache in the credentialed publish job | high | `package-manager-cache: false`; drop any `actions/cache` step |
| `npm publish` where the package restricts to stage-only | high | Switch to `npm stage publish` — the current command will be rejected |
| `npm publish` with no stage-only restriction configured | medium | Adopt staged publishing (see `release-checklist.md` item 11) |

## Repo settings

| Finding | Severity | Fix |
|---|---|---|
| `default_workflow_permissions: "write"` | high | `gh api -X PUT .../actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false` |
| `sha_pinning_required: false` (after files pinned) | high | `gh api -X PUT .../actions/permissions -F sha_pinning_required=true` |
| Release-source branch without protection ruleset | high | Create/extend branch ruleset (see `repo-settings-checklist.md` item 4) |
| No tag ruleset on `refs/tags/v*` | high | Create tag ruleset blocking `creation`/`update`/`deletion` |
| `required_approving_review_count: 0` (multi-contributor repo) | medium | Add `pull_request` rule with count `1`; split ruleset for Dependabot bypass |
| Secret scanning disabled (plan supports it) | medium | `gh api -X PATCH .../<repo>` with `security_and_analysis.secret_scanning.status: enabled` |
| Required status check named in ruleset but workflow trigger filter excludes the protected branch | high | Add the branch to `on.push.branches` / `on.pull_request.branches`, or drop the check from the ruleset |
| Immutable releases disabled on a repo that publishes releases | high | `gh api -X PUT repos/<owner>/<repo>/immutable-releases` |

## Package manager

Supported managers are **pnpm and bun only**. npm and yarn are out of scope by choice, not
because they lack the controls — say it that way in the report. Floors: pnpm >= 10.26
(11+ recommended), bun current. See `package-manager-checklist.md` item 1.

| Finding | Severity | Fix |
|---|---|---|
| `yarn.lock` present (any version) | critical (policy) | Outside the supported set — `pnpm import` or `bun install`, then delete the old lockfile |
| `package-lock.json` present (any npm version) | critical (policy) | Same — migrate to pnpm or bun |
| pnpm or bun below its floor | high (policy) | Bump `packageManager`; name the missing primitive. One line, not a migration |
| `packageManager` unset | high | Pin it — the floor is otherwise unverifiable across machines |
| Multiple lockfiles present | high | Pick one; delete the rest |
| bun `install.minimumReleaseAge` unset | high (policy) | Set `259200` (seconds) in `bunfig.toml [install]` |
| Release-age gate below 72h (incl. pnpm v11's `1440` default) | medium (policy) | Raise to the 72h value in that manager's unit |
| pnpm `strictDepBuilds: false` | high | Remove the override or set `true` |
| pnpm without `allowBuilds` map | medium | Define `allowBuilds:`; the gate is already on, the map is the audit log |
| pnpm `allowBuilds` entry without a justification comment | low | Add the comment — it is the audit log |
| bun `trustedDependencies` entry not in Bun's default allowlist and uncommented | medium | Add a justification comment or remove the entry |
| Owned `@scope/*` in lockfile without registry mapping | high | Add `registries:` (pnpm) or `[install.scopes]` (bun) |
| Owned `@scope/*` not in the release-age exclude list | medium | pnpm `minimumReleaseAgeExclude` (singular) / bun `minimumReleaseAgeExcludes` (plural) |
| pnpm `verifyStoreIntegrity: false` / `blockExoticSubdeps: false` | high | Remove the override |

Not findings: absence of bun `trustedDependencies` or `ignoreScripts` (defaults are safe);
pnpm `enablePrePostScripts: true` (governs the project's own scripts, not dependency builds).

### Release-age gate: one value, two units

72 hours in each manager's own unit. Copying the value between them is the single most
common error in this audit, and it fails silently in one direction.

| Manager | Key | Unit | 72h value | Default |
|---|---|---|---|---|
| pnpm | `minimumReleaseAge` (`pnpm-workspace.yaml`) | minutes | `4320` | `1440` on v11 |
| bun | `install.minimumReleaseAge` (`bunfig.toml`) | seconds | `259200` | none |

`4320` in bun's field is 72 *minutes* — approximately no protection, and nothing warns.
`259200` in pnpm's field is 180 *days* — nothing installs, which at least fails loudly.
