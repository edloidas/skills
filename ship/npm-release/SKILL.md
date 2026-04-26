---
name: npm-release
description: This skill should be used when the user asks to release, publish, or create a new version of an npm/pnpm/bun package. It guides through version bumping, validation, git tagging, and publishing with proper safety checks and user approval.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Glob AskUserQuestion
argument-hint: "[major, minor, or patch]"
---

# pnpm / Bun / npm Package Release Workflow

## Package manager detection

Detect the active package manager by lockfile first. Priority order:

1. `pnpm-lock.yaml` → **pnpm**
2. `bun.lock` or `bun.lockb` → **bun**
3. `package-lock.json` → **npm**

If no lockfile is present, fall back to tool availability in the same preference order: pnpm → bun → npm. If a lockfile is present but its tool is missing, error out — don't silently switch managers.

`release-prepare.sh` runs this check and prints `Package manager: <name>`. Read that output and use the same manager consistently in every later step. All command blocks below list pnpm first, then bun, then npm — pick the one for the detected manager.

## Purpose

Automate the release process for pnpm / bun / npm packages with:

- Pre-flight validation and safety checks
- Intelligent version bump recommendations
- Git workflow automation (commit, tag, push)
- User approval before publishing
- CI/CD integration support

## When to Use This Skill

Use this skill when the user:

- Asks to "release", "publish", or "create a new version"
- Wants to bump the package version
- Needs to create a release tag
- Mentions releasing to npm registry

## Bundled Scripts

This skill includes three helper bash scripts in the `scripts/` directory:

1. **release-prepare.sh** - Validates git status, branch, and runs dry-run build
2. **release-analyze.sh** - Analyzes commits since last tag and suggests version bump
3. **release-execute.sh** - Creates git tag and pushes to remote

To use bundled scripts, execute them from the skill directory:

```bash
bash scripts/release-prepare.sh
bash scripts/release-analyze.sh
bash scripts/release-execute.sh
```

These scripts work with any pnpm/bun/npm project and don't require project-specific setup.

## Prerequisites
- `jq` installed (used by release-analyze.sh and release-execute.sh)
- Git repository with at least one prior commit

## Asking the User

User prompts occur at **Step 0** (ambiguous conventions) and **Step 7** (release approval). At each prompt site, in order:

1. Try `AskUserQuestion`. If its schema is deferred, load it first via `ToolSearch` with query `select:AskUserQuestion`, then call it.
2. If the tool is unavailable or the call errors, fall back to chat: post a short numbered list (2–5 options, recommended first) and wait for the reply. See Step 7 for the canonical format.

Do not proceed past either prompt without a user reply. Never guess ambiguous conventions. Never push without approval.

## Release Workflow

Follow these steps in order. Create an in-memory plan at the start.

### Step 0: Read Project Conventions

Before doing anything else, read the project's instruction files to honor local conventions. Check, in order:

1. `CLAUDE.md` at the repo root
2. `AGENTS.md` at the repo root
3. `.agents/` or `.claude/` rule files if they exist

Extract and apply whatever applies to this release:

- **Release commit message format** — e.g. `chore: release v<version>` or a project-specific template. This overrides the default `Release v<version>` used in Step 5.
- **Pre-release prerequisites** — e.g. updating `CHANGELOG.md` via a separate skill, regenerating docs, running a project-specific validation script. Run these **before** bumping the version so `release:dry` in Step 2 can gate on them.
- **Branch policy** — some projects allow releases only from `master`, some from version branches (`x.y`), some restrict by environment.
- **Tag format** — default is `v<version>`. If the project documents something else, use it.
- **Dist-tag policy** — how prerelease versions are routed (`alpha`/`beta`/`rc`/`next`).

If `CLAUDE.md` / `AGENTS.md` doesn't exist or doesn't say anything about releases, fall back to the defaults below. If an instruction is ambiguous, ask the user — see [Asking the User](#asking-the-user).

### Step 1: Pre-flight Checks

**Verify git status and branch:**

1. Check current branch is `master` or `main` (or other default branch if different)
2. Check for uncommitted changes (staged or unstaged)
3. If there are issues:
   - Reply with a short, clear message explaining the problem
   - Suggest stashing changes and trying again: `git stash && [retry]`
   - Do not proceed further

**Use the bundled script:**

```bash
bash scripts/release-prepare.sh
```

**Or manual checks:**

```bash
# Check branch
git branch --show-current

# Check for changes
git status --porcelain

# Verify build and packaging
pnpm release:dry
# or
bun run release:dry
# or
npm publish --dry-run
```

### Step 2: Validate Release Build

Run dry-run release to ensure everything builds correctly:

```bash
pnpm release:dry
# or
bun run release:dry
# or
npm publish --dry-run
```

If validation fails:

- Report the error to the user
- Do not proceed with release
- Suggest fixing issues first

### Step 3: Analyze Commits for Version Decision

Determine whether to use `major`, `minor`, or `patch` bump by analyzing changes since last release.

**Use the bundled script:**

```bash
bash scripts/release-analyze.sh
```

**Or manual analysis:**

```bash
# Get last version tag
git describe --tags --abbrev=0

# Show commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Show detailed changes if needed
git log $(git describe --tags --abbrev=0)..HEAD --stat
```

**Decision criteria:**

- **Major bump** (x.0.0): Breaking API changes, removal of public APIs, incompatible behavior changes (post-1.0 only)
- **Minor bump** (0.x.0): New features, significant enhancements, API additions, breaking changes (in pre-1.0)
- **Patch bump** (0.0.x): Bug fixes, small improvements, documentation updates, refactoring

If commits don't provide enough context, examine specific diffs:

```bash
git diff $(git describe --tags --abbrev=0)..HEAD -- [key-files]
```

### Step 4: Bump Version

Update `package.json` version. Use the detected package manager; always pass the flag that disables the automatic commit/tag (we create those manually in later steps).

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

**Important:** `--no-git-tag-version` prevents automatic commit/tag creation — we create them explicitly in Steps 5 and 6.

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

### Step 6: Create Git Tag

Tag the release commit with an **annotated** tag (required for `--follow-tags` and standard for releases — preserves tagger, date, and message):

```bash
git tag -a v{{VERSION}} -m "Release v{{VERSION}}"
```

Example: `git tag -a v0.16.0 -m "Release v0.16.0"`

### Step 7: User Review & Approval

**CRITICAL: Always pause here for explicit user approval unless explicitly told to skip.**

Present a summary to the user (each on a new line):

- **Version:** What version is being released (e.g., v0.16.0)
- **Bump type:** Minor or Patch
- **Changes summary:** 2-4 bullet points of key changes based on your analysis
- **What happens next:** Push commits and tags, CI/CD will publish

Ask for approval following [Asking the User](#asking-the-user). Options:

1. `Yes` (Recommended) — Proceed with pushing and releasing
2. `No` — Cancel the release and keep local changes for review

With `AskUserQuestion`, "Other" is added automatically and lets the user provide custom instructions. With the chat fallback, the user can always reply with free text instead of picking a number.

Example `AskUserQuestion` call (after loading its schema via `ToolSearch` if deferred):
```
AskUserQuestion:
  question: "Ready to push v{{VERSION}} and release?"
  header: "Release"
  options:
    - label: "Yes (Recommended)"
      description: "Push commits and tags to trigger CI/CD publishing"
    - label: "No"
      description: "Cancel release (local commit and tag will remain)"
```

Example chat fallback:
```
Ready to push v{{VERSION}}?
1. Yes — push commits and tags to trigger release
2. No — keep local commit and tag for review
```

**If user selects:**
- **Yes** → Proceed to Step 8
- **No** → Inform the user that the local commit and tag remain in place for review. Do not run cleanup automatically. If the user wants to undo the release prep, explain the cleanup steps and ask before performing any destructive git command.
- **Other** → Follow user's custom instructions

### Step 8: Push Release

**Only after user approves:**

**Use the bundled script:**

```bash
bash scripts/release-execute.sh
```

**Or manual push:**

```bash
git push --follow-tags
```

`--follow-tags` pushes commits plus any **annotated** tags reachable from them in a single round-trip. It avoids the torn state of two separate pushes and won't accidentally publish stale local tags from other branches the way `git push --tags` does.

### Step 9: Confirm Completion

Inform the user:

- Release has been pushed
- CI/CD will handle publishing (if configured)
- Provide relevant links:
  - GitHub release page
  - npm package page
  - Any deployment URLs

## Bundled Helper Scripts Details

The three bundled scripts provide complete release workflow support:

### scripts/release-prepare.sh

- Validates current branch is master/main
- Checks for uncommitted changes
- Detects package manager via lockfile first (pnpm → bun → npm), falls back to tool availability, and prints the result
- Runs dry-run release to verify build (`pnpm release:dry` / `bun run release:dry` / `npm publish --dry-run`)
- Provides clear error messages and suggestions

### scripts/release-analyze.sh

- Finds last release tag
- Shows all commits since last release
- Analyzes commit messages for features, fixes, etc.
- Provides version bump recommendation (minor vs patch)
- Shows file change statistics

### scripts/release-execute.sh

- Reads version from package.json
- Creates git tag with v prefix
- Pushes commits and tags to remote
- Confirms before pushing if tag exists
- Shows post-release verification links

## Error Handling

If any step fails:

1. Stop the workflow immediately
2. Report the error clearly to the user
3. Suggest corrective action
4. Do not proceed to next steps

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

If CI/CD is not configured or manual publishing is needed:

```bash
# After pushing tags
pnpm publish --access public
# or
bun publish --access public
# or
npm publish --access public
```

**Note:** Most projects should use CI/CD for publishing to ensure consistency and security.

## Integration Notes

This skill is self-contained and requires no project-specific setup. However:

1. **CI/CD Integration**: Projects should configure GitHub Actions or similar for automated npm publishing
2. **Documentation**: Projects can reference this skill in their CLAUDE.md or README
3. **Custom Scripts**: If projects already have release scripts, use those instead of bundled ones
4. **Flexibility**: All steps can be performed manually if bundled scripts don't fit the workflow

## Keywords

release, publish, version, bump, tag, npm, pnpm, bun, package, deploy, ship, new version, create release
