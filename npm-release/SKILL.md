---
name: npm-release
description: This skill should be used when the user asks to release, publish, or create a new version of an npm/pnpm package. It guides through version bumping, validation, git tagging, and publishing with proper safety checks and user approval.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Task AskUserQuestion
arguments: "version bump type: major, minor, or patch"
argument-hint: "[version]"
---

# NPM/PNPM Package Release Workflow

## Purpose

Automate the release process for npm/pnpm packages with:

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

These scripts work with any npm/pnpm project and don't require project-specific setup.

## Release Workflow

Follow these steps in order. Create an in-memory plan at the start.

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
npm publish --dry-run
```

### Step 2: Validate Release Build

Run dry-run release to ensure everything builds correctly:

```bash
pnpm release:dry
# or
npm publish --dry-run
```

If validation fails:

- Report the error to the user
- Do not proceed with release
- Suggest fixing issues first

### Step 3: Analyze Commits for Version Decision

Determine whether to use `minor` or `patch` bump by analyzing changes since last release.

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

- **Minor bump** (0.x.0): New features, significant enhancements, API additions, breaking changes (in pre-1.0)
- **Patch bump** (0.0.x): Bug fixes, small improvements, documentation updates, refactoring

If commits don't provide enough context, examine specific diffs:

```bash
git diff $(git describe --tags --abbrev=0)..HEAD -- [key-files]
```

### Step 4: Bump Version

Update package.json version using pnpm or npm:

```bash
# For minor bump
pnpm version minor
# or
npm version minor --no-git-tag-version

# For patch bump
pnpm version patch
# or
npm version patch --no-git-tag-version
```

**Important:** Use `--no-git-tag-version` flag with npm to prevent automatic commit/tag creation (we'll do this manually).

### Step 5: Commit Version Bump

Create a commit with the standardized release message:

```bash
# Read new version from package.json
git add package.json package-lock.json pnpm-lock.yaml

# Commit with release message
git commit -m "Release v{{VERSION}}"
```

Example: If version is `0.16.0`, the commit message should be `Release v0.16.0`

### Step 6: Create Git Tag

Tag the release commit:

```bash
git tag v{{VERSION}}
```

Example: `git tag v0.16.0`

### Step 7: User Review & Approval

**CRITICAL: Always pause here for user approval unless explicitly told to skip.**

Present a summary to the user (each on a new line):

- **Version:** What version is being released (e.g., v0.16.0)
- **Bump type:** Minor or Patch
- **Changes summary:** 2-4 bullet points of key changes based on your analysis
- **What happens next:** Push commits and tags, CI/CD will publish

**Use the AskUserQuestion tool** with these options:

- **Yes** - Proceed with pushing and releasing
- **No** - Cancel the release (keep local changes for review)

The user can also select "Other" to provide custom instructions (e.g., change version type, add more changes first).

Example tool usage:
```
AskUserQuestion:
  question: "Ready to push v{{VERSION}} and release?"
  header: "Release"
  options:
    - label: "Yes"
      description: "Push commits and tags to trigger CI/CD publishing"
    - label: "No"
      description: "Cancel release (local commit and tag will remain)"
```

**If user selects:**
- **Yes** → Proceed to Step 8
- **No** → Inform user that local commit/tag remain and can be reset with `git reset --hard HEAD~1 && git tag -d v{{VERSION}}`
- **Other** → Follow user's custom instructions

### Step 8: Push Release

**Only after user approves:**

**Use the bundled script:**

```bash
bash scripts/release-execute.sh
```

**Or manual push:**

```bash
git push && git push --tags
```

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
- Runs dry-run release to verify build
- Provides clear error messages and suggestions
- Works with both npm and pnpm

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
- Lint errors: Run `pnpm lint:fix` then retry
- Type errors: Fix TypeScript issues first

**No tags found:**

- First release: Suggest starting with v0.1.0 or v1.0.0
- Ask user which version to use as baseline

## Advanced: Manual Publishing

If CI/CD is not configured or manual publishing is needed:

```bash
# After pushing tags
pnpm publish --access public
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

release, publish, version, bump, tag, npm, pnpm, package, deploy, ship, new version, create release
