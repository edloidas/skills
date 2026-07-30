# Bucket Routing

Rules for picking exactly one target bucket per finding. A finding cannot live
in two buckets — pick the most durable single home.

## Buckets

### Personal preference (`~/.claude/CLAUDE.md`)

Cross-project habits, tone preferences, naming conventions the user holds
personally regardless of project. Things that should affect every Claude
conversation the user runs.

**Examples**
- "Don't add summary recaps at the end of every response."
- "Always quote separators like `===` instead of `---` to avoid hook issues."
- Preferred path conventions that span all repos.

**Apply rule:** never auto-apply. Show exact line + exact section header. Get
explicit y/n.

### Project convention (`<project>/CLAUDE.md`)

Project-specific rules: directory layout, test/build commands, repo conventions
for branches/commits, framework choices. Things that belong to this repo.

**Examples**
- "All commits in this repo follow `<type>: <description> #<number>`."
- "Use `bun` not `npm`."
- "The `epic-*` base branch convention."

**Apply rule:** never auto-apply. Show line + section. Get explicit y/n.

### Style/convention rule (`.claude/rules/<topic>.mdc`)

Narrow, checkable rules tied to code style or convention enforcement. The kind
of rule `review:review-rules` would surface in a code review.

**Examples**
- "Don't import from `dist/`."
- "Translation keys must use snake_case."
- "Test files mirror the source path."

**Apply rule:** show full rule file content. Create new file or append to
existing topic file. Get explicit y/n. Topic files are short — one focused rule
each.

### Cross-session pattern (auto-memory)

User preferences, role facts, project goals, references — patterns that
persist across sessions and aren't already documented elsewhere. Use the
auto-memory format from the system prompt's "auto memory" section.

**Examples**
- "User prefers terse responses with no trailing summaries."
- "Project frontend uses Vite + React."
- "Linear project 'INGEST' tracks pipeline bugs."

**Target:** `~/.claude/projects/<encoded-cwd>/memory/<type>_<topic>.md` with
correct frontmatter (`name`, `description`, `type`).

**Apply rule:** always update `MEMORY.md` index in the same operation. Memory
files are the only bucket eligible for `Apply safe` auto-application.

### Skill gap or bug

A skill in this repo (or installed globally) misbehaved, was missing
functionality, or had wrong instructions. The fix is an edit to that skill's
own files.

**Examples**
- "`issue-flow` doesn't recognize `epic-*` as a valid base branch."
- "`commit-summary` script chokes on multi-byte filenames."
- "`review:review-build` skill doesn't say what to do if no lint command exists."

**Target:** the affected skill's `SKILL.md` or `scripts/` files.

**Apply rule:** never auto-apply. Show the diff. If the skill belongs to a
different repo than the current cwd, switch the proposal to "open an issue
against `<repo>`" rather than direct edit. Consider invoking
`dev:skill-report` to record the failure separately for the skill author.

### Tooling gap

A repeatable check, lint rule, test, or CI config could have prevented the
friction. The fix is configuration, not docs.

**Examples**
- "Add `eslint-plugin-react-hooks` rule X — would have caught this."
- "Add a `pre-commit` hook that blocks committing files matching pattern Y."
- "Add a `tsc` step to CI — local-only typecheck missed this."

**Target:** lint config, test files, CI workflow YAML, hooks file.

**Apply rule:** propose only. Never auto-apply tooling changes — they can
break CI for everyone. Surface the proposed config diff, and let the user
choose to apply manually after review.

### Discuss-only / one-off

A genuinely interesting moment from the session that doesn't have a durable
target. Worth recording so cross-retro analysis can spot recurring versions,
but not worth saving anywhere actionable.

**Examples**
- "Spent 15 min chasing a stale lockfile that turned out to be the cache."
- "Realized mid-task that the spec was actually for a different module."

**Target:** the retro report only. No file edits anywhere else.

**Apply rule:** "applying" a Discuss-only finding means closing the chat
discussion — no edits land outside the report.

## Routing decision tree

For each finding, ask in order:

1. **Is the signal about a specific skill's behavior?** → Skill gap.
2. **Could a config/lint/test change have prevented it?** → Tooling gap.
3. **Is it a narrow, checkable code-style rule?** → `.claude/rules/`.
4. **Is it a project-specific convention (this repo only)?** → project CLAUDE.md.
5. **Is it a personal habit that applies to every project?** → global CLAUDE.md.
6. **Is it a stable cross-session fact about user/project?** → auto-memory.
7. **None of the above but worth recording?** → Discuss-only.

If a finding seems to fit two buckets, pick the **more durable / more
discoverable** one (memory > rules > CLAUDE.md > skill > tooling > discuss-only
in that priority).

## What never lands as a finding

- Production source code edits.
- New tests for product behavior (suggest in tooling-gap if the gap is
  test-coverage policy, but don't propose specific test code).
- Refactors of unrelated code.
- README rewrites unrelated to the friction.
