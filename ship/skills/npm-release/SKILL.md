---
name: npm-release
description: >
  Release an npm, pnpm, or bun package: version bump, validation, git tagging, and publishing,
  with safety checks and explicit user approval before anything is pushed.
when_to_use: >
  On "release this", "publish a new version", "bump the version", "tag a release", or "ship
  it". For the edloidas/skills repo itself, use skills-release instead.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Glob AskUserQuestion
argument-hint: "[major, minor, or patch]"
---

# pnpm / Bun / npm Package Release Workflow

This skill **writes to external services**. It edits `package.json` and the lockfile, creates a
commit and a signed tag locally, then pushes both to the git remote — and that push publishes
the version, to the npm registry through CI or directly on the manual-publish path. npm does
not allow a published version to be replaced. Steps 0-7 are local and undoable; Step 8 is not.

## Package manager detection

Detect the active package manager by lockfile first. Priority order:

1. `pnpm-lock.yaml` → **pnpm**
2. `bun.lock` or `bun.lockb` → **bun**
3. `package-lock.json` → **npm**

If no lockfile is present, fall back to tool availability in the same preference order: pnpm → bun → npm. If a lockfile is present but its tool is missing, error out — don't silently switch managers.

`release-prepare.sh` runs this check and prints `Package manager: <name>`. Read that output and use the same manager consistently in every later step. All command blocks below list pnpm first, then bun, then npm — pick the one for the detected manager.

## Bundled Scripts

Three helper bash scripts in `scripts/`, executed from the skill directory. They work with any
pnpm/bun/npm project and need no project-specific setup. If the project already ships its own
release scripts, use those instead of these.

| Script | Does | Run at |
| ------ | ---- | ------ |
| `release-prepare.sh` | Checks branch and working tree, detects and prints the package manager, runs the dry-run release | Step 1 |
| `release-analyze.sh` | Finds the last tag, lists and classifies commits since it, prints file-change stats and a bump recommendation | Step 3 |
| `release-execute.sh` | Reads the version from `package.json`, creates the tag if absent, **pushes** commits and tags, prints verification links | Step 8 only — it pushes, so never run it before the Step 7 approval |

```bash
bash scripts/release-prepare.sh
bash scripts/release-analyze.sh
bash scripts/release-execute.sh
```

Prerequisites: `jq` installed (used by `release-analyze.sh` and `release-execute.sh`), and a git
repository with at least one prior commit.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

Questions occur at **Step 0** (ambiguous conventions) and **Step 7** (release approval). Neither
is skippable on your own judgement: ask, and wait for the reply before continuing.

## Release Workflow

Follow these steps in order. Create an in-memory plan at the start.

### Step 0: Read Project Conventions

Read the project's instruction files first, so the release honors local conventions. Check, in order:

1. `CLAUDE.md` at the repo root
2. `AGENTS.md` at the repo root
3. `.agents/` or `.claude/` rule files if they exist

Extract and apply whatever applies to this release:

- **Release commit message format** — e.g. `chore: release v<version>` or a project-specific template. This overrides the default `Release v<version>` used in Step 5.
- **Pre-release prerequisites** — e.g. updating `CHANGELOG.md` via a separate skill, regenerating docs, running a project-specific validation script. Run these **before** bumping the version so `release:dry` in Step 2 can gate on them.
- **Branch policy** — some projects allow releases only from `master`, some from version branches (`x.y`), some restrict by environment.
- **Tag format** — default is `v<version>`. If the project documents something else, use it.
- **Dist-tag policy** — how prerelease versions are routed (`alpha`/`beta`/`rc`/`next`).

If `CLAUDE.md` / `AGENTS.md` doesn't exist or doesn't say anything about releases, fall back to the defaults below. If an instruction is ambiguous, ask the user, per **Asking the User**.

End the step with one line naming what you found, defaults included:
`Conventions: commit "chore: release v<version>", tag v<version>, master only, no CHANGELOG gate`.

### Step 1: Pre-flight Checks

```bash
bash scripts/release-prepare.sh
```

Or manually:

```bash
git branch --show-current   # must be master, main, or the project's documented release branch
git status --porcelain      # must be empty
```

If the branch is wrong or the tree is dirty, name which in one line, suggest `git stash && [retry]`
or committing first, and stop there. Do not stash, commit, or switch branches yourself to clear
the check.

End the step with one line: `Pre-flight: branch master, tree clean, package manager pnpm`.

### Step 2: Validate Release Build

`release-prepare.sh` already ran the dry run — read its output rather than running it twice. To
run it alone:

```bash
pnpm release:dry
# or
bun run release:dry
# or
npm publish --dry-run
```

If it fails, report the error and stop: no version bump, no commit, no tag. Fixing build, lint,
or type errors is separate work the user asks for.

End the step with one line: `Dry run passed: 42 files, 128 kB`.

### Step 3: Analyze Commits for Version Decision

```bash
bash scripts/release-analyze.sh
```

Or manually:

```bash
# Get last version tag
git describe --tags --abbrev=0

# Show commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Show detailed changes if needed
git log $(git describe --tags --abbrev=0)..HEAD --stat
```

| Bump | When |
| ---- | ---- |
| **Major** (x.0.0) | Breaking API changes, removal of public APIs, incompatible behavior changes — post-1.0 only |
| **Minor** (0.x.0) | New features, significant enhancements, API additions; also breaking changes while pre-1.0 |
| **Patch** (0.0.x) | Bug fixes, small improvements, documentation updates, refactoring |

If the commit subjects don't settle it, read the diffs of the files they touch:

```bash
git diff $(git describe --tags --abbrev=0)..HEAD -- [key-files]
```

End the step with one line: `12 commits since v0.15.3 (4 feat, 6 fix, 2 chore) -> recommend minor`.

### Step 4: Bump Version

Update `package.json` version. Use the detected package manager; always pass the flag that disables the automatic commit/tag, so this step cannot create either by accident.

```bash
# pnpm
pnpm version minor --no-git-tag-version
pnpm version patch --no-git-tag-version

# Bun (uses bun pm version)
bun pm version minor --no-git-tag-version
bun pm version patch --no-git-tag-version

# npm
npm version minor --no-git-tag-version
npm version patch --no-git-tag-version
```

**Prerelease bumps** (alpha/beta/rc) use `prerelease` with an explicit preid:

```bash
# pnpm / npm
pnpm version prerelease --preid=alpha --no-git-tag-version
npm  version prerelease --preid=alpha --no-git-tag-version
# Bun
bun pm version prerelease --preid=alpha --no-git-tag-version
```

Stop once `package.json` carries the new version. Commit, tag, and push belong to Steps 5, 6,
and 8 — do not run any of them here.

End the step with one line: `Bumped package.json to 0.16.0`.

### Step 5: Commit Version Bump

Use the **release commit message format captured in Step 0**. Only fall back to the generic `Release v<version>` if the project did not specify one.

```bash
# Stage package.json and whichever lockfile exists
git add package.json pnpm-lock.yaml bun.lock bun.lockb package-lock.json 2>/dev/null || true

# Commit with the format from Step 0 (examples — pick ONE):
git commit -m "Release v{{VERSION}}"              # fallback default
git commit -m "chore: release v{{VERSION}}"       # Conventional Commits
git commit -m "release: v{{VERSION}}"             # project-specific alternative
```

If the project uses a non-obvious template (commit body, trailers, sign-off), reproduce it exactly as documented. Never invent a format the project didn't specify.

End the step with one line: `Committed Release v0.16.0 (a1b2c3d)`. The tag is Step 6.

### Step 6: Create Git Tag

Tag the release commit with a **signed** tag (`-s` implies `-a`, so the tag is also annotated — required for `--follow-tags`, preserves tagger/date/message, and provides a verifiable signature regardless of the user's `tag.gpgSign` config):

```bash
git tag -s v{{VERSION}} -m "Release v{{VERSION}}"
```

Example: `git tag -s v0.16.0 -m "Release v0.16.0"`

If the user has no signing key configured, `git tag -s` fails with a gpg/ssh error. In that case, advise them to configure SSH or GPG signing (`user.signingkey`, `gpg.format`) before retrying.

The tag now exists locally only. Do not push it here — Step 7 gates the push.

End the step with one line: `Tagged v0.16.0 (not pushed)`.

### Step 7: User Review & Approval

Pushing the tag publishes the release and cannot be recalled: CI starts from the tag, and npm
refuses to replace a published version. Show the version and the tag, and wait for approval.
Skip this gate only when the user has already told you, in this session, to release without
stopping.

Present a summary, each item on its own line — the version, the bump type, the tag as it stands,
2-4 bullets of key changes from the Step 3 analysis, and what the push will do:

```
Version:  v0.16.0
Bump:     minor
Tag:      v0.16.0 — created locally, not pushed
Changes:
  - Adds `--watch` to the build command (4 commits)
  - Fixes lockfile drift under pnpm 10 (#212)
  - Removes the deprecated `legacy` export — pre-1.0, so minor rather than major
Next:     git push --follow-tags -> CI publishes @acme/widget@0.16.0 to npm
```

Ask for approval, per **Asking the User**:

1. `Yes` (Recommended) — Proceed with pushing and releasing
2. `No` — Cancel the release and keep local changes for review

**If user selects:**
- **Yes** → Proceed to Step 8
- **No** → Inform the user that the local commit and tag remain in place for review. Do not run cleanup automatically. If the user wants to undo the release prep, explain the cleanup steps and ask before performing any destructive git command.
- **Other** → Follow user's custom instructions

### Step 8: Push Release

Only after the user approves:

```bash
bash scripts/release-execute.sh
# or
git push --follow-tags
```

`--follow-tags` pushes commits plus any **annotated** tags reachable from them in a single round-trip. It avoids the torn state of two separate pushes and won't accidentally publish stale local tags from other branches the way `git push --tags` does.

End the step with one line: `Pushed master + v0.16.0`.

### Step 9: Confirm Completion

Report in one block:

- The release is pushed
- Whether CI publishes it. If the repo has no publish workflow, say so — publishing is still owed, see **Advanced: Manual Publishing**
- Links you can construct: GitHub release page, npm package page, any deployment URL

Then stop. Do not start a second release, and do not publish manually on top of a CI workflow
that is already running.

## Error Handling

A failing step ends the workflow where it stands: report the error and the corrective action,
one line each, and do not run the steps after it. Do not retry a failed command with different
flags to get past the failure.

## Common Issues

**Uncommitted changes:**

- Suggest: `git stash` then retry, or commit changes first

**Wrong branch:**

- Suggest: `git checkout master` then retry

**Failed dry-run:**

- Build errors: Fix and retry
- Lint errors: Run the project's lint-fix script (`pnpm lint:fix` / `bun run lint:fix` / `npm run lint:fix`) then retry
- Type errors: Fix TypeScript issues first
- Project-specific gate failures (e.g. missing CHANGELOG section): see what Step 0 surfaced and resolve before retrying

**No tags found:**

- First release: Suggest starting with v0.1.0 or v1.0.0
- Ask user which version to use as baseline

## Advanced: Manual Publishing

Prefer CI/CD for publishing — it keeps the published artifact consistent and keeps the npm token
off local machines. Where CI is not configured, or the user asks for a manual publish:

```bash
# After pushing tags
pnpm publish --access public
# or
bun publish --access public
# or
npm publish --access public
```
