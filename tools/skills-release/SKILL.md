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
allowed-tools: Bash Read AskUserQuestion
metadata:
  author: edloidas
---

# Skills Collection Release Workflow

This skill **writes locally and pushes**. It rewrites every version-bearing manifest,
regenerates the Codex wrapper layer, commits, creates the tag (signed when signing is
configured), pushes both to GitHub in one atomic push, and edits the published release notes —
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
| `release-bump.sh` | Rewrites the version files, regenerates the Codex wrappers, verifies, commits, tags, and verifies the tag — no push | Step 4 |
| `release-push.sh` | Refuses unless the tag is annotated, at HEAD, and signed when signing is configured; pushes branch and tag with `--atomic`; confirms both on the remote | Step 6 |
| `release-tag.sh` | Tag creation and verification, sourced by the two above | Never directly |
| `release-execute.sh` | `release-bump.sh` then `release-push.sh` with **no gate between them** | Never in this workflow — it clears the Step 5 gate; it exists for a non-interactive release the user asks for by name |

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

When the script prints a **Skills Removed or Renamed** section, keep that list — Step 7 maps it
into the release notes.

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

Run it bare — never piped through `tail`, `head`, or any filter: a pipe reports the filter's
exit status, which is how a GPG failure once went unseen and master was pushed without
`v5.18.0`. The script rewrites every version file, regenerates the
wrapper manifests, verifies each one landed on `{{VERSION}}`, stages them, commits as
`Release v{{VERSION}}`, creates the `v{{VERSION}}` tag (signed when `user.signingkey` or
`tag.gpgSign` is set), and verifies the tag. It does **not** push, and neither do you here —
Step 5 gates that. It refuses a tag that already exists: delete the old tag or choose another
version.

A non-zero exit means stop. If the commit landed but the tag did not, the script prints the
two recovery commands — show them to the user and run neither yourself.

End the step with one line: `Bumped 24 manifests to 5.6.0, committed, tagged v5.6.0 (not pushed)`.

### Step 5: User Approval Before Push

Pushing the tag publishes the release and cannot be recalled: the tag drives the release
workflow, and installers fetch the published GitHub Release. Show the version and the tag, and
wait for approval. If Step 2 listed removed or renamed skills, also show the
`## Removed or renamed skills` section Step 7 will put in the release notes — one line per
skill, `old (group) -> new` or `old (group) -> removed`. Approving the push approves that notes
edit, so draft it here, not after.

**Use the AskUserQuestion tool:**

```
AskUserQuestion:
  question: "Ready to push v{{VERSION}} to remote?"
  header: "Push"
  options:
    - label: "Yes"
      description: "Push commit and tag atomically, then apply the shown release-notes mapping"
    - label: "No"
      description: "Keep local commit and tag, do not push"
```

If user selects **No**, inform them:

- The commit and tag remain local
- To undo: `git reset --hard HEAD~1 && git tag -d v{{VERSION}}`

Do not run that cleanup yourself unless the user asks for it.

If user selects **Other**, follow their instructions.

### Step 6: Push Release

Only after user approves, and bare — never piped through `tail`, `head`, or a filter:

```bash
bash .claude/skills/skills-release/scripts/release-push.sh {{VERSION}}
```

It re-verifies the tag, then runs `git push --atomic origin <branch> v{{VERSION}}`, so the
remote takes both refs or neither. Do not substitute a plain `git push` or `--follow-tags`:
neither refuses when the tag is missing. A non-zero exit means nothing was pushed — report the
script's error line and stop.

Then confirm the tag independently:

```bash
git ls-remote --tags origin v{{VERSION}}
```

Empty output means the release did not publish, whatever the script printed — report that and
stop. Otherwise end the step with one line:
`Pushed master + v{{VERSION}} at a1b2c3d4e5f6; tag confirmed on origin`.

### Step 7: Release Notes

The release workflow creates the GitHub Release with `--generate-notes`. Generated notes list
commits, not removed skills, and a rename is invisible to a user whose slash command stopped
working. So:

- **Step 2 printed no Skills Removed or Renamed section:** nothing to edit. End with
  `Release notes: generated by the workflow, no mapping needed`.
- **It did:** wait for the release workflow (`gh run watch` on the run for `v{{VERSION}}`), read
  the generated body with `gh release view v{{VERSION}} --json body -q .body`, put the section
  approved at Step 5 above it, and apply the result with
  `gh release edit v{{VERSION}} --notes-file <file>`. End with
  `Release notes: mapped 3 removed or renamed skills`.

Then stop. Do not re-run the workflow, create a follow-up version, or edit the release further
unless asked.

## Error Handling

A failing step ends the workflow where it stands: report the error and the corrective action,
and do not run the steps after it.
