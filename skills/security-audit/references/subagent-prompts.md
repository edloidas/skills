# Audit Subagent Prompts

Dispatch prompts for each audit area. The orchestrator computes the placeholders in SKILL.md
Step 1, substitutes them in Step 2, and dispatches one subagent per applicable area. A new audit
area adds a checklist under `references/` and a prompt here — never a mutation.

**Substitutions the orchestrator must perform before dispatch:**

| Placeholder | Computed in | Used by |
|---|---|---|
| `{{SKILL_DIR}}` | absolute path to the skill directory containing SKILL.md | all |
| `{{RELEASE_PUBLISHES_TO_NPM}}` | Step 1, release-target context below | B |
| `{{DETECTED_BUILD_SYSTEMS}}` | Step 1, release-target context below | B |
| `{{ORG_PREFIX}}` | Step 1, org-scope context below (may be empty) | D |
| `{{ALREADY_COVERED_SCOPES}}` | Step 1, org-scope context below | D |
| `{{CODE_SECURITY_CHECKLIST}}` | inlined body of `code-security-checklist.md` | E |

**Org-scope context, for Subagent D:**

- `org_prefix` — derived from `package.json` `name:`. If the name is `@<prefix>/<pkg>`, the prefix is `<prefix>`. If the name is unscoped, leave `org_prefix` empty (no org scopes will be flagged).
- `org_scope_patterns` — given a non-empty `org_prefix`, owned scopes are `@<prefix>/*` AND any scope matching `@<prefix>-*/*` (e.g., for `enonic`: `@enonic/*`, `@enonic-types/*`, `@enonic-cli/*`).
- `already_covered_scopes` — union of: `minimumReleaseAgeExclude` from `pnpm-workspace.yaml` (use `yq`), `minimumReleaseAgeExcludes` from `bunfig.toml`, `registries:` keys from `pnpm-workspace.yaml`, `[install.scopes]` keys from `bunfig.toml`, and `@<scope>:registry=` lines from `.npmrc`.

These pre-approve scopes the team has already decided to trust. Subagent D treats them as covered and emits no finding for missing config.

**Release-target context, for Subagent B:**

- `release_publishes_to_npm` — `true` if any of these exist (the audit does not care WHICH non-npm publisher is used, only whether npm is involved): a `release.yml` / `release.yaml` in `.github/workflows/` containing a literal `npm publish`, `npm stage publish`, `pnpm publish`, `yarn publish`, or `bun publish`; a `publishConfig.registry` field in `package.json`; or a `scripts.publish` value containing any of those commands.
- `detected_build_systems` — assembled from root file presence: `npm` if `package.json` + any lockfile, `gradle` if `build.gradle`/`build.gradle.kts`, `maven` if `pom.xml`, `cargo` if `Cargo.toml`, `pip` if `requirements.txt`/`pyproject.toml`, `docker` if `Dockerfile`. `github-actions` is always added when `.github/workflows/` exists. This drives item 7 (dependabot ecosystem coverage) so the audit recommends the right ecosystems regardless of stack.

Subagents are spawned with the user's CWD, not the skill's — `{{SKILL_DIR}}` is why relative
checklist paths resolve. Every prompt ends with "Do not edit files": no subagent mutates
anything, and none of them executes a `gh api` write.

## Subagent A — GitHub Actions auditor

Full criteria: `actions-checklist.md`.

````
You are auditing GitHub Actions workflows for supply-chain hardening.

Read every file under `.github/workflows/`. For each, evaluate:

1. SHA pinning — every `uses:` must be a 40-char commit SHA with version comment.
2. Workflow-level `permissions:` — must be explicit, default to `contents: read`.
3. `actions/checkout` — must set `persist-credentials: false` unless the workflow performs `git push`.
4. `pull_request_target` — flag every use. Critical if it checks out or executes PR-supplied code; safe otherwise.
5. `actions/cache` keys — must include `${{ github.sha }}` or `hashFiles(...)` for entropy.
6. `id-token: write` (OIDC) — restrict to publish/deploy workflows only.
7. Third-party action sources — list non-first-party actions.
8. Push-triggered deploys holding secrets — deploy-provider secrets referenced in a broad `push:`-triggered workflow without an `environment:` on the job. Critical for production targets; remediation is owned by the Repo Settings audit (its item 10) — report and cross-reference.
9. Workflow static analysis in CI — is a workflow linter (zizmor) run on the workflows themselves? Absence is a medium finding: items 1-8 are exactly what such a linter enforces continuously, and a one-off audit does not prevent regression.
10. Stale branches carrying old workflow versions — a branch whose `.github/workflows/` still contains a vulnerability already fixed on the default branch. `pull_request_target` and `workflow_run` execute the workflow file from the *base* ref, but other triggers can reach a stale ref. High when a stale branch carries a `pull_request_target` checkout of PR code, or a credentialed job that has since been split.

Read the full checklist at `{{SKILL_DIR}}/references/actions-checklist.md`.

Report findings as a bullet list, grouped by severity (critical | high | medium | low | informational). For each finding: file:line — description — recommended fix. Include a "passes" section listing what is already hardened. Do not edit files.

**Additionally emit a structured "Workflow Trigger Map" at the end of your report**, in this exact format — Step 3 uses it to cross-check against the Repo Settings audit's ruleset findings:

```
WORKFLOW_TRIGGER_MAP
- <workflow-name-from-name-field>:
    file: <relative path>
    push_branches: [<branch>, ...]   # from on.push.branches; "*" for unfiltered; "none" if no push trigger
    pr_branches:   [<branch>, ...]   # from on.pull_request.branches; same conventions
```

Emit one entry per workflow file. This is data, not a finding — do not bin it by severity.
````

## Subagent B — Release auditor

Full criteria: `release-checklist.md` and `install-flags.md`.

````
You are auditing release configuration for supply-chain hardening.

**Release target context** (substituted at dispatch): `release_publishes_to_npm = {{RELEASE_PUBLISHES_TO_NPM}}` and `detected_build_systems = {{DETECTED_BUILD_SYSTEMS}}`. If `release_publishes_to_npm` is `false`, skip exactly the npm-only items listed in item 0 of `{{SKILL_DIR}}/references/release-checklist.md` and name them in the report header: "npm publish not detected — items <n, n, …> skipped." Every other item applies.

Read `.github/workflows/release.yml` (or equivalent), `package.json`, `.github/dependabot.yml`, and any publishing scripts. Evaluate:

1. Release trigger scope — only `tags: ['v*']` or `workflow_dispatch`, never `push: branches`.
2. Tag/commit precheck — workflow verifies the tagged commit is reachable from a trusted branch.
3. Frozen lockfile — `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`, `bun install --frozen-lockfile`. Applies whenever the workflow runs a Node install step, regardless of what gets published.
4. `--prod` flag — only in runtime-artifact contexts (Docker runtime layer, deployable tarball). Not in build/test/publish steps.
5. npm provenance — for public packages, Trusted Publishers (OIDC) and `--provenance` or pnpm OIDC.
6. Token usage — secrets or OIDC only. No hardcoded tokens, no workflow_dispatch input tokens.
7. `dependabot.yml` ecosystem coverage — always require `package-ecosystem: "github-actions"`. For each entry in `detected_build_systems` other than `github-actions`, recommend the matching Dependabot ecosystem: `npm` covers npm/pnpm/yarn/bun; `gradle`, `maven`, `cargo`, `pip`, `docker` map 1:1. Do NOT require `npm` when `release_publishes_to_npm` is false unless a Node lockfile is present (then it covers dev-dep updates).
8. Artifact identity — the published artifact must be the exact bytes that were smoked/inspected: pack once, upload, smoke the downloaded artifact in a scratch project, publish that same artifact. Flag re-packing in the publish job, tests that rebuild the packed output, and unpinned packing toolchains. (Applies to any packed artifact.)
9. Minimal credentialed publish job — the job holding `id-token: write` or registry tokens must contain only auth setup, artifact download, and the publish command with `--ignore-scripts`. No checkout, no install, no build. Also flag dependency caching in that job (`cache:` on `actions/setup-node`, or any `actions/cache` step): set `package-manager-cache: false` so a poisoned cache entry cannot reach the credentialed job.
10. Publisher-side npm settings — not API-auditable; emit as ask-the-user items: Trusted Publisher pinned to exact repo + workflow filename, and token-based publishing disallowed (require 2FA, no bypass tokens) once OIDC is the only path.
11. Staged publishing — the publish step should run `npm stage publish`, not `npm publish`. Staged publishing holds the release in a staging area until a maintainer approves it with 2FA (`npm stage approve <stage-id>`, or the Staged Packages page on npmjs.com), which is the one control a fully compromised CI job cannot forge. Requires npm CLI >= 11.15.0 and Node >= 22.14.0. Plain `npm publish` in a workflow whose package has no stage-only Trusted Publisher restriction = medium; `npm publish` where the package *does* restrict to stage-only = high (the release will be rejected at publish time).

Read the full checklists at:
- `{{SKILL_DIR}}/references/release-checklist.md`
- `{{SKILL_DIR}}/references/install-flags.md`

Report findings grouped by severity, same format as the Actions audit. Do not edit files.
````

## Subagent C — Repo Settings auditor

Full criteria: `repo-settings-checklist.md`.

````
You are auditing GitHub repository settings for supply-chain hardening. Findings here are API-driven; fixes are `gh api` calls, not file edits.

Resolve `<owner>/<repo>` via `gh repo view --json nameWithOwner --jq .nameWithOwner` and read the GitHub REST API with `gh api` GET requests to evaluate. Run no other command, and no `gh api` call carrying `-X`/`--method` other than `GET` or any `-f`/`-F`/`--input` field — a field without `-X` makes `gh api` send a POST.

1. Default `GITHUB_TOKEN` permissions — `default_workflow_permissions` must be `read`, `can_approve_pull_request_reviews` must be `false`.
2. `sha_pinning_required` — **report the current value verbatim** (e.g., `sha_pinning_required: false`). Do NOT recommend flipping it independently; whether enabling it is safe depends on the Actions audit verdict (item 1 of Subagent A). Step 3 of the orchestrator combines your report with Subagent A's pin status and emits the recommendation.
3. `allowed_actions` — informational. `"all"` is common; `"selected"` is appropriate for high-security repos.
4. Branch protection rulesets — the default branch and every active release-source branch (e.g., `x.y` version branches) must be covered by rules for `deletion`, `non_fast_forward`, `required_status_checks`, and ideally `required_linear_history`.
5. PR approval rule — `required_approving_review_count >= 1` for multi-contributor repos. Flag the Dependabot interaction (see ruleset-splitting pattern in the checklist).
6. Tag protection rulesets — if the release workflow triggers on `v*` tags, there has to be a tag ruleset blocking `creation`, `update`, and `deletion` on `refs/tags/v*`, with bypass limited to Admins.
7. Secret scanning + push protection — enabled where the plan supports it.
8. Dependabot security updates, private vulnerability reporting, CodeQL default setup — enabled where the plan supports them. **High** if `SECURITY.md` advertises private vulnerability reporting while the API reports it disabled.
9. Deploy secrets reachable from arbitrary branches — deploy-provider credentials stored as repository-level secrets while a broad `push:`-triggered workflow references them. Critical for production targets. Remediation order matters (environment created before the workflow references it; secrets are write-only; repo-level copies deleted last) — follow checklist item 10 exactly.
10. Bypass actor patterns — flag every `bypass_mode: always` actor and warn that bypass is all-or-nothing per ruleset.
11. Immutable releases — `gh api repos/<owner>/<repo>/immutable-releases` reports `{enabled, enforced_by_owner}`. When a release workflow publishes GitHub Releases or tag-triggered artifacts, `enabled: false` is a high finding: without it a tag and its release assets can be moved or replaced after the fact, so a verified-looking version can be swapped underneath consumers. Informational when the repo publishes no releases.

Read the full checklist at `{{SKILL_DIR}}/references/repo-settings-checklist.md` — it contains the exact `gh api` commands for both detection and remediation, plus well-known actor IDs (Dependabot Integration = 29110, Admin RepositoryRole = 5) and the ruleset-splitting pattern for granular bypass.

Report findings grouped by severity, same format as the Actions audit. For each finding, include the exact `gh api` remediation command as report text — never execute it. Do not edit files.

**Additionally emit a structured "Ruleset Required Checks" map at the end of your report**, in this exact format — Step 3 uses it to cross-check against the Actions audit's Workflow Trigger Map for status-check coverage:

```
RULESET_REQUIRED_CHECKS
- ruleset_id: <id>
  target: branch
  protected_branches: [<branch-pattern-from-ref_name.include>, ...]
  required_checks: [<context-string>, ...]   # empty list if none
```

Emit one entry per branch-target ruleset. This is data, not a finding — do not bin it by severity. Step 3 matches `required_checks` against the Workflow Trigger Map and emits the "BLOCKED-PR" finding when a check is required on a branch no workflow triggers on.
````

## Subagent D — Package Manager auditor

Full criteria: `package-manager-checklist.md`.

````
You are auditing Node.js package-manager configuration for install-time supply-chain hardening.

**This audit supports pnpm and bun only.** If the repo uses npm or yarn, emit one finding — outside the supported set, migrate to pnpm or bun — and skip items 2-9 entirely. Do NOT claim npm or yarn lack these controls: npm has `min-release-age` (11.10+) and deny-by-default install scripts (12+), and yarn berry has `npmMinimalAgeGate` and defaults `enableScripts` to false. The finding is scope, not capability, and saying otherwise to a maintainer who knows their tool discredits the whole report.

This audit distinguishes two kinds of "critical": (a) currently-exploitable misconfigurations (e.g., `verifyStoreIntegrity: false`), and (b) policy floors — the *absence* of a hardening primitive this audit treats as mandatory, including an unsupported manager. Label policy findings as "critical (policy)" or "high (policy)" so consumers can calibrate urgency.

Read whichever of these exist: `package.json`, `pnpm-workspace.yaml`, `.npmrc`, `bunfig.toml`, `pnpm-lock.yaml`, `bun.lock`, `bun.lockb`. Read `.npmrc` and `bunfig.toml` only through the redacting `sed` in the checklist's Quick Audit Block — both can hold registry tokens, and a raw read puts them in the transcript. Also check for `package-lock.json` and `yarn.lock` — their presence is item 1's finding. Then evaluate:

1. Manager and version floor — `yarn.lock` present (any version) = critical (policy), outside the supported set. `package-lock.json` present (any npm version) = critical (policy), same. pnpm below 10.26 or bun below current = high (policy), naming the primitive the version lacks — this is a one-line bump, not a migration. `packageManager` unset = high. Multiple lockfiles = high. When the manager is unsupported, stop here: report the migration and do not emit tuning findings for config files that manager does not read.
2. pnpm version floor detail (pnpm only) — v10.26 is the capability floor (`allowBuilds` ships there); v11 is the no-regression floor, because v11 removes the legacy split keys. If pnpm is between 10.26 and 11 and any of `onlyBuiltDependencies`, `neverBuiltDependencies`, `ignoredBuiltDependencies`, `ignoreDepScripts` is still present = medium; recommend `pnpx codemod run pnpm-v10-to-v11`.
3. Lifecycle script allowlist — both managers deny dependency scripts by default at the floors above; the finding is about the audit log and whether install fails closed.
   - **pnpm:** `allowBuilds` is the audit log; `strictDepBuilds: false` = high (silent skip masks new requests). `allowBuilds` undefined = medium. Entries without justification comments = low.
   - **bun:** does NOT execute lifecycle scripts by default, with a built-in default allowlist. Any `trustedDependencies` entry NOT in Bun's default allowlist and lacking a justification comment = medium. Absence of `trustedDependencies` and `ignoreScripts` is NOT a finding. bun has no fail-closed switch — note that as a limitation of the stack, not as a repo misconfiguration.
4. Release-age gate — floor 72h. **The unit differs between the two managers; this is the most common error in this audit.** pnpm `minimumReleaseAge` = minutes (`4320`); bun `install.minimumReleaseAge` = seconds (`259200`). Unset on bun (no default) or on pnpm < 11 (default 0) = high (policy). Set below 72h, including pnpm v11's `1440` default (which is what unset means on v11) = medium (policy).
   - pnpm only: also pin `minimumReleaseAgeStrict: true` (defaults true only when `minimumReleaseAge` is set), and note that `minimumReleaseAgeIgnoreMissingTime: true` (default) silently skips the gate for packages whose registry omits `time` — common on private registries.
5. Release-age exclusions — **owned scopes only.** The orchestrator has substituted `{{ORG_PREFIX}}` (may be empty) and `{{ALREADY_COVERED_SCOPES}}`. If `{{ORG_PREFIX}}` is non-empty, owned scope patterns are `@{{ORG_PREFIX}}/*` AND `@{{ORG_PREFIX}}-*/*`. For each owned scope in the lockfile NOT in `{{ALREADY_COVERED_SCOPES}}`, flag it (medium). **Never flag non-owned scopes** — the gate is correctly applied to them. pnpm's field is singular (`minimumReleaseAgeExclude`), bun's is plural (`minimumReleaseAgeExcludes`).
6. Scope → registry mapping — **owned scopes only**, same gating as item 5. Only flag owned scopes in the lockfile lacking an entry in `registries:` (pnpm) or `[install.scopes]` (bun), or a `@scope:registry=` line in `.npmrc`. Missing mapping for an owned scope = dependency-confusion vector (high). Public scopes (`@types/*`, `@biomejs/*`) are never findings here.
7. Default downgrades — flag any explicit override of a safe default: pnpm `verifyStoreIntegrity: false`, `blockExoticSubdeps: false`, `strictDepBuilds: false` — all high. Do NOT flag pnpm `enablePrePostScripts: true` (default): it governs the current project's own `prefoo`/`postfoo` scripts, not dependency build scripts.
8. Vuln-override hygiene — if `overrides:` (`pnpm-workspace.yaml` or `pnpm.overrides`) or `resolutions` (bun) contains **10 or more** entries whose left-hand side uses range operators, surface it in "passes" as a positive signal: `Vuln-override block: N CVE-shape pins`. Do NOT validate against current CVE data — that is Dependabot's job. Below the threshold, emit nothing.
9. Trust policy (pnpm only, at or above the floor) — `trustPolicy` unset or `off` = low (policy). `no-downgrade` fails the install when a version carries weaker publish evidence than earlier releases — a hijacked token publishing without provenance. Exemptions go in `trustPolicyExclude`, not in turning it off.

Read the full checklist at `{{SKILL_DIR}}/references/package-manager-checklist.md` — it contains exact field names, the two-manager unit table, defaults, the policy / exploitable distinction, and fix examples.

Report findings grouped by severity, same format as the Actions audit. For each finding, include the exact config snippet needed to remediate, in the syntax of the manager actually in use. Mark policy findings explicitly. Do not edit files.
````

## Subagent E — Application code auditor

Runs only when the repo has application source to audit. Skip for a configuration-only or
docs-only repository. Full criteria: `code-security-checklist.md`.

````
You are auditing application source code for injection and unsafe-execution vectors.

Detect the stack from the files present, then apply only the checks that stack activates.
Read every file you flag before reporting it.

{{CODE_SECURITY_CHECKLIST}}

For each finding report: file:line, the vector, the source expression that reaches it, and
whether a guard is present, absent, or unclear. A sink reached only by a literal is not a
finding. Return findings severity-ordered. Return "No findings." if the code is clean. Do not edit files.
````
