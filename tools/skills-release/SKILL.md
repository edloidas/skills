---
name: skills-release
description: >
  Release workflow for the edloidas/skills collection. Validates git state, analyzes commits
  since the last tag, recommends a version bump (major/minor/patch), updates Claude and Codex
  packaging metadata, commits, tags, and pushes.
when_to_use: >
  On "release the skills repo", "version this repo", or "tag a skills release". For an
  ordinary npm package, use npm-release instead.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Task AskUserQuestion
metadata:
  author: edloidas
---

# Skills Collection Release Workflow

This skill **writes locally and pushes**. It rewrites every version-bearing manifest,
regenerates the Codex wrapper layer, commits, creates a signed tag, and pushes both to GitHub —
where the tag triggers the release workflow and publishes a GitHub Release that installers
fetch. A pushed tag cannot be recalled. It does not publish to npm; `package.json` here is
`private: true` and exists only as the pi manifest and a version anchor.

For an ordinary npm package, use `/npm-release` instead.

## Bundled Scripts

Helper scripts in `scripts/`, invoked below by path.

| Script | Does | Run at |
| ------ | ---- | ------ |
| `release-prepare.sh` | Validates git state, packaging state, and version consistency across the release files | Step 1 |
| `release-analyze.sh` | Counts commits since the last tag by conventional type, detects removed or renamed skills, recommends a bump | Step 2 |
| `release-bump.sh` | Rewrites the version files, regenerates the Codex wrappers, verifies, commits, and tags — no push | Step 4 |
| `release-execute.sh` | The same flow **plus an unprompted push** | Never in this workflow — it clears the Step 5 gate; it exists for a non-interactive release the user asks for by name |

## Release Workflow

Follow these steps in order.

### Step 1: Pre-flight Checks

```bash
bash .claude/skills/skills-release/scripts/release-prepare.sh
```

It checks the branch, a clean tree, every manifest and the catalog, `jq`, both validators, that
`sync-repo` leaves the tree clean, and that every version-bearing file agrees.

If any check fails, report which one and the fix, and stop there — no analysis, no bump. Do not
commit generated changes yourself to make `sync-repo` come back clean; that is the user's call.

End the step with one line: `Pre-flight passed: 10 plugins, version 5.5.1, tree clean`.

### Step 2: Analyze Commits

```bash
bash .claude/skills/skills-release/scripts/release-analyze.sh
```

It prints commit counts by type, breaking markers, skills removed or renamed since the last tag,
file stats, and a bump recommendation.

**Version bump criteria:**

| Bump      | When                                                           |
| --------- | -------------------------------------------------------------- |
| **Major** | `type!:` prefix, `BREAKING CHANGE` body, **or** any skill removed or renamed since the last tag |
| **Minor** | New features — any `feat:` commits                             |
| **Patch** | Everything else — `fix:`, `docs:`, `refactor:`, `chore:`, etc. |

Trust the removal check over the commit subjects — v5.0.0 removed 17 skills under `refactor:`
subjects and would have shipped as MINOR without it.

When the script prints a **Skills Removed or Renamed** section, map old to new in the
release notes before publishing. A rename is invisible to a user whose slash command
stopped working, and reconstructing the mapping after the tag is published is the slow
way to do it.

### Step 3: Confirm Version with User

Present the analysis summary, then ask. Read the numbers off the script output — do not
re-summarize the commits from memory:

```
Since v5.5.1 — 14 commits
  feat 3 · fix 6 · docs 2 · chore 2 · ci 1
  Breaking markers: 0
  Skills removed or renamed: none
  Files changed: 41 (+912 / -430)
Recommended: MINOR -> v5.6.0
```

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

If user selects **Cancel**, stop the workflow and leave the tree untouched.

### Step 4: Bump, Commit, and Tag

```bash
bash .claude/skills/skills-release/scripts/release-bump.sh {{VERSION}}
```

The script rewrites every version file, regenerates the wrapper manifests, verifies each one
landed on `{{VERSION}}`, stages them, commits as `Release v{{VERSION}}`, and creates the signed
`v{{VERSION}}` tag. It does **not** push, and neither do you here — Step 5 gates that. It
refuses a tag that already exists: delete the old tag or choose another version.

End the step with one line: `Bumped 24 manifests to 5.6.0, committed, tagged v5.6.0 (not pushed)`.

### Step 5: User Approval Before Push

Pushing the tag publishes the release and cannot be recalled: the tag drives the release
workflow, and installers fetch the published GitHub Release. Show the version and the tag, and
wait for approval.

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

Do not run that cleanup yourself unless the user asks for it.

If user selects **Other**, follow their instructions.

### Step 6: Push Release

Only after user approves:

```bash
git push --follow-tags
```

`--follow-tags` pushes the commit and the reachable annotated release tag together in one round-trip — avoids torn state and won't publish stale local tags the way `--tags` does.

After pushing, get the remote URL and print:

```
Release v{{VERSION}} pushed successfully.
GitHub Releases: https://github.com/edloidas/skills/releases
```

Then stop. The release workflow runs on the tag from here — do not re-run it, do not create a
follow-up version, and do not edit the published release unless asked.

## Error Handling

A failing step ends the workflow where it stands: report the error and the corrective action,
and do not run the steps after it.
