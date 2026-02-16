---
name: skills-release
description: >
  Release workflow for the edloidas/skills collection. Validates git state,
  analyzes commits since last tag, recommends a version bump (major/minor/patch),
  updates plugin.json and marketplace.json, commits, tags, and pushes.
  Use when the user asks to release, version, or tag this skills repository.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Task AskUserQuestion
metadata:
  author: edloidas
---

# Skills Collection Release Workflow

## Purpose

Automate the release process for this skills repository:

- Pre-flight validation and safety checks
- Conventional commit analysis with version bump recommendation
- Version update in all plugin.json and marketplace.json files
- Git commit, tag, and push with user approval gates

## When to Use This Skill

Use this skill when the user:

- Asks to "release", "tag", or "version" this skills collection
- Wants to bump the skills plugin version
- Needs to create a release tag for the repo

**Do not use** for npm packages — use `/npm-release` instead.

## Bundled Scripts

This skill includes three helper scripts in the `scripts/` directory:

1. **release-prepare.sh** — Validates git status, branch, config files, and version consistency
2. **release-analyze.sh** — Analyzes commits since last tag, counts by type, recommends bump
3. **release-execute.sh** — Bumps version, commits, tags, and pushes to remote

Run scripts from the skill directory:

```bash
bash scripts/release-prepare.sh
bash scripts/release-analyze.sh
bash scripts/release-execute.sh 1.1.0
```

## Release Workflow

Follow these steps in order. Stop immediately if any step fails.

### Step 1: Pre-flight Checks

Run the preparation script to validate everything:

```bash
bash scripts/release-prepare.sh
```

This checks:

- Current branch is `master` or `main`
- Working tree is clean (no uncommitted changes)
- `.claude-plugin/marketplace.json` exists
- Each plugin's `.claude-plugin/plugin.json` exists
- `jq` is available
- Versions across all config files match

If checks fail, report the problem and suggest a fix. Do not proceed.

### Step 2: Analyze Commits

Run the analysis script to understand what changed:

```bash
bash scripts/release-analyze.sh
```

This will:

- Find the last release tag (or handle first release)
- List all commits since that tag
- Count commits by conventional type using anchored regex
- Detect breaking changes (`type!:` suffix or `BREAKING CHANGE` in body)
- Show file change statistics
- Print a version bump recommendation

**Version bump criteria:**

| Bump      | When                                                           |
| --------- | -------------------------------------------------------------- |
| **Major** | Breaking changes — `type!:` prefix or `BREAKING CHANGE` body  |
| **Minor** | New features — any `feat:` commits                             |
| **Patch** | Everything else — `fix:`, `docs:`, `refactor:`, `chore:`, etc. |

### Step 3: Confirm Version with User

Present the analysis summary and ask the user to choose a version bump.

**Use the AskUserQuestion tool** with these options:

```
AskUserQuestion:
  question: "Recommended: {{RECOMMENDATION}}. Which version bump for v{{CURRENT}} → v{{NEXT}}?"
  header: "Version"
  options:
    - label: "Major (v{{MAJOR}})"
      description: "Breaking changes — skill removals, renames, config restructuring"
    - label: "Minor (v{{MINOR}})"
      description: "New features — new skills, significant enhancements"
    - label: "Patch (v{{PATCH}})"
      description: "Fixes, docs, refactoring, chore, CI, tests"
    - label: "Cancel"
      description: "Abort the release"
```

Replace `{{CURRENT}}` with current version, and compute `{{MAJOR}}`, `{{MINOR}}`, `{{PATCH}}` by incrementing the appropriate segment (reset lower segments to 0).

If user selects **Cancel**, stop the workflow.

### Step 4: Bump Version

Update all config files using `jq`. The execution script handles this:

```bash
bash scripts/release-execute.sh {{VERSION}}
```

**Important:** In step 4, only run the version bump portion. The execution script also commits, tags, and pushes — but we need a user approval gate before pushing. So instead of running the full script, perform the bump manually:

```bash
VERSION="{{VERSION}}"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")

# Update all marketplace.json plugin entries
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  jq --arg v "$VERSION" --argjson i "$i" '.plugins[$i].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
done

# Update each plugin.json
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"
  jq --arg v "$VERSION" '.version = $v' "$plugin_json" > "$plugin_json.tmp" && mv "$plugin_json.tmp" "$plugin_json"
done
```

Verify all files were updated correctly by reading them back.

### Step 5: Commit Version Bump

Stage and commit the version bump:

```bash
git add .claude-plugin/marketplace.json review/.claude-plugin/plugin.json audit/.claude-plugin/plugin.json workflow/.claude-plugin/plugin.json
git commit -m "Release v{{VERSION}}"
```

### Step 6: Create Git Tag

Tag the release commit:

```bash
git tag v{{VERSION}}
```

### Step 7: User Approval Before Push

**CRITICAL: Always pause here for user approval.**

Present a summary and ask for confirmation.

**Use the AskUserQuestion tool:**

```
AskUserQuestion:
  question: "Ready to push v{{VERSION}} to remote?"
  header: "Push"
  options:
    - label: "Yes"
      description: "Push commits and tag to remote"
    - label: "No"
      description: "Keep local commit and tag, do not push"
```

If user selects **No**, inform them:

- The commit and tag remain local
- To undo: `git reset --hard HEAD~1 && git tag -d v{{VERSION}}`

If user selects **Other**, follow their instructions.

### Step 8: Push Release

Only after user approves:

```bash
git push && git push --tags
```

After pushing, get the remote URL and print:

```
Release v{{VERSION}} pushed successfully.
GitHub Releases: https://github.com/edloidas/skills/releases
```

## Error Handling

If any step fails:

1. Stop the workflow immediately
2. Report the error clearly
3. Suggest corrective action
4. Do not proceed to next steps

## Common Issues

**Uncommitted changes:**
- Suggest: `git stash` then retry, or commit changes first

**Wrong branch:**
- Suggest: `git checkout master` then retry

**Version mismatch between files:**
- Fix manually or bump both to the same version before releasing

**No tags found:**
- First release: The analyze script handles this and recommends MINOR

**Tag already exists:**
- The execute script will refuse to create a duplicate tag
- Either delete the old tag or choose a different version

## Keywords

release, version, bump, tag, skills, publish, deploy, ship, new version, create release
