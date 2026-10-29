# Creating Issues

Step 1 of `issue-flow`, plus the relationship paths that file or link issues: sub-issues,
project inheritance, blocked-by, and batch creation. `SKILL.md` owns the conventions this file
cites — **Asking the User**, **Assignment Defaults**, **Temp Files and Command Shape**, **Slice
Delivery** — and which report Step 1 prints before it stops.

## Step 1: Create Issue

Run these in parallel (they are independent):

```bash
# Parallel batch
bash "<skill-dir>/scripts/check-env.sh"
mktemp -d                                       # → save output as <TMPDIR>
bash "<skill-dir>/scripts/repo-context.sh"
bash "<skill-dir>/scripts/repo-ownership.sh"
```

Wait for all four before proceeding. `detect-base.sh` is not needed until Step 2.

### Title

Use conventional commit format: `<type>: <description>`. Defer to CLAUDE.md conventions if they differ.

### Epic Detection

Before writing the body or picking a label, determine if this is an **epic issue** — one that coordinates work without containing implementation itself. Signals:

- User mentions "epic", "umbrella", "tracking issue", or "aggregated issue"
- Issue groups multiple child issues or feature areas
- No concrete implementation details — only scope or coordination

If it is an epic, and the repo has an `epic` label (check `repo-context.sh` output), apply `epic` as the label without asking. Skip the normal type-based label inference. If `epic` label does not exist in the repo, fall through to normal label selection.

### Body

Write a 2-4 sentence description. No markdown headers.

Under **Slice Delivery**, when the scope is already understood, end the body with a short ordered list of parts that can each land as a working increment. When the scope still needs investigation, leave the list out — a guessed split misleads whoever plans the work.

For epic issues: **do not list child issue numbers in the body.** Sub-issue relationships are managed via the GitHub sub-issues API (see **## Sub-Issues**), not via body text.

### Labels

Auto-detect label from the issue type (e.g., `feat` → `feature` or `enhancement`). Match against labels fetched by `repo-context.sh`. Ask, per **Asking the User**: the top 3 matching labels + "No label".

### Assignee

Follow **Assignment Defaults** in `SKILL.md`; `KIND=personal` skips `issue-assignees.sh` entirely.

**`KIND=org` or `KIND=external`** — run `issue-assignees.sh` to find users with actual recent assignment activity:

```bash
bash "<skill-dir>/scripts/issue-assignees.sh"
```

Output: `<user>\t<count>` per row, up to 3 rows (excludes self and bots). Ask, per **Asking the User**:

1. `@me` (Recommended)
2. First result, description: `"Assigned to <count> of last 100 issues"`
3. Second result, description: `"Assigned to <count> of last 100 issues"`
4. "No assignee"

If `issue-assignees.sh` returns nothing, show only `@me` and "No assignee" — no collaborator-list fallback, per **Assignment Defaults**.

### Type

Issue types are an organization-level feature. Probe through the same GraphQL field `gh issue create` depends on:

```bash
bash "<skill-dir>/scripts/issue-types.sh"
```

- Names returned → map the conventional commit type onto the closest one and pass
  `--type "<name>"` to the create wrapper.
- Empty output → the repo has no assignable issue types. This is the normal answer for a
  personal repo. Skip silently.

The wrapper runs the same probe when `--type` is absent and refuses to create, listing the
types, if any exist. Probe only through the script; its header says why the REST catalog and
`--dry-run` are wrong.

### Project

Decide this before creating: the wrapper refuses without `--project "<title>"` (repeatable) or `--no-project`, and adds the issue to each project itself.

If the new issue is a child of, or a follow-up to, an existing issue, follow **## Project Inheritance From Parent** instead.

Otherwise, rank candidates via `suggest-projects.sh` (output: `<bucket>\t<id>\t<title>\t<note>` per row; `USED` = projects from your recent issues, `RELATED` = other active projects):

```bash
bash "<skill-dir>/scripts/suggest-projects.sh"
```

Ask, per **Asking the User**: slot 1 (Recommended) = first row, slots 2–4 = next rows, with `<note>` as each option's description. Backfill the last slot with "No project" when fewer than 4 rows exist. Pass the selection as `--project "<project-title>"`; "No project", zero rows, or Projects V2 unavailable is `--no-project`.

### Milestone

**Trigger:** Check milestones when either:
- The user explicitly asks to assign a milestone
- The target repo's CLAUDE.md mentions milestones (any mention — section headers, instructions, config)

If neither trigger matches, skip silently.

**When triggered**, fetch open milestones:

```bash
gh api "repos/<owner>/<repo>/milestones?state=open" --jq '.[] | {number, title, state, open_issues, closed_issues, due_on}'
```

Then apply:
- **0 milestones**: skip silently
- **1 milestone**: assign automatically — inform the user which milestone was used
- **2+ milestones**: ask, per **Asking the User**:

```
Which milestone for this issue?
1. "<title1>" (Recommended) — X open / Y closed, due YYYY-MM-DD
2. "<title2>" — X open / Y closed, due YYYY-MM-DD
3. No milestone
```

Order by due date (soonest first). The first non-closed milestone is recommended.

Assign via `--milestone "<title>"` in the create-wrapper command.

### Create

Use the `<TMPDIR>` from the parallel setup batch, spelled out per **Temp Files and Command Shape**. Write the issue body to `<TMPDIR>/body.md` with the host's file-write tool, then create the issue through the wrapper:

```bash
bash "<skill-dir>/scripts/create-issue.sh" (--project "<title>"... | --no-project) -- --title "<title>" --body-file <TMPDIR>/body.md --label "<label>" --assignee "<assignee>" [--type "<name>"] [--milestone "<name>"]
```

Exit `2` means nothing was created — supply the missing decision and run it again. Exit `3` means the issue exists (its URL is on stdout) but a project add failed: add it with the `add-to-project.sh` command the error names, never by creating again.

The wrapper runs `gh issue create` once. If `gh` returns nonzero after creating the issue, it checks recent issues by exact title, current author, and the creation window; when exactly one match exists, reuse that URL and continue. If it exits nonzero, stop and reconcile manually. Do not retry issue creation until that reconciliation finds no created issue.

When creating multiple issues, use unique filenames per issue: `<TMPDIR>/<slug>-body.md` (e.g. `auth-body.md`, `settings-body.md`). Resolve `<TMPDIR>` once and reuse it for all issues.

**Media the body references.** Where the body carries a local image or video path — a screenshot of the bug, a mockup — pass it through the wrapper once per file. Alt text follows the path after a `#`, on images only: a video renders as a player and cannot carry any, so a `#` on one is a mistake.

```bash
bash "<skill-dir>/scripts/create-issue.sh" --project "<project>" -- --title "<title>" --body-file <TMPDIR>/body.md --attach "<path>#<alt text>"
```

`gh` uploads the file and rewrites that path in place, so the image lands where the body put it. A path passed without being referenced is appended to the end of the issue instead. Needs `gh` 2.99.0 or newer and does not work on GitHub Enterprise Server: check `gh --version` first, and where either is missing, create the issue with the image reference stripped from the body and report that it could not be uploaded.

**A failed upload does not fail the issue, and this wrapper hides that.** When some attachments upload and others do not, `gh` still creates the issue with the ones that worked, prints its URL to stdout, and exits nonzero. The wrapper reads that nonzero as "create failed", ignores the URL it was handed, finds the issue again by title, and reports `reusing <url>` — so the step succeeds while the published body still carries a local path that resolves to nothing. Confirm every referenced path exists before running the wrapper, and on a `reusing` warning open the issue and check each image rendered before printing the Step 1 report.

If the user mentioned other issue numbers to include in this aggregated issue, link them per **## Sub-Issues** before printing the Step 1 report.

## Sub-Issues

Use when an aggregated (parent) issue should group related child issues. Link each child with `references/github-relationships.md` → **Sub-Issues (REST API)** — the integer `.id`, `-F`, and the verify call are there. Take `<owner>/<repo>` from `repo-context.sh` — it is the line *after* the `=== Repository ===` header, not the first line of output.

Print one line: `Linked <N> sub-issues to #<parent>`.

When a new issue will be linked as a child of an existing parent, resolve its projects via **## Project Inheritance From Parent** before creating it, so the child lands on the same project board(s) as the parent.

A follow-up filed while working on #N (per **## Project Inheritance From Parent**) is linked the same way to #N's parent, if any — see `references/github-relationships.md` → **Parent of an Issue**.

## Project Inheritance From Parent

When a new issue is being created as a child of an existing parent (sub-issue link, "attach to #N", "linked to #N"), or as a follow-up filed while working on #N (the `issue-<N>` branch is checked out, or a caller names the issue it is working on), inherit #N's project membership instead of using the generic Project picker. Below, "parent" means #N in both cases.

Fetch the parent's projects (output: `<id>\t<title>`):

```bash
bash "<skill-dir>/scripts/get-issue-projects.sh" <parent_number>
```

Apply based on count:

- **0** — fall through to the generic Project subsection.
- **1** — add automatically and tell the user which project was inherited.
- **2+** — ask, per **Asking the User**:
  1. "Add to all <N> parent projects" (Recommended)
  2. "Pick individually" — follow-up yes/no per project
  3. "Skip projects"

Pass each selected project as its own `--project "<title>"` to the create wrapper; "Skip projects" is `--no-project`.

When linking many children to the same parent (see **## Batch Issue Creation**), fetch the parent's projects once and reuse the decision for every child — do not prompt per child.

## Blocked-By

Use when child issues have dependencies between them — e.g., issue B cannot start until issue A is done. Run `references/github-relationships.md` → **Blocked-By Relationships**: node IDs in one query, then `addBlockedBy` (`removeBlockedBy` to undo). Take `<owner>/<repo>` as **## Sub-Issues** does. Print one line per pair: `#<blocked> is now blocked by #<blocking>`.

## Batch Issue Creation

When the user asks to create multiple issues at once (e.g., an epic with child issues, or a set of related issues):

1. Resolve `<TMPDIR>` once via `mktemp -d`
2. Create the parent/epic issue first (if applicable)
3. Write all child issue body files with unique slugs: `<TMPDIR>/<slug>-body.md`
4. Create the child issues sequentially — the exception to running independent calls in parallel, because the wrapper adds to projects as it creates and parallel Projects V2 calls hit rate limits. On exit `3`, add that issue with the command the error names and continue with the next child. Resolve the project set once: via **## Project Inheritance From Parent** when children are linked to an **existing** parent, otherwise via **### Project**. Apply **Assignment Defaults** once and reuse the same assignee for every issue in the batch, including the parent. Do not prompt per issue.
   ```bash
   for slug in <slug1> <slug2> <slug3>; do
     bash "<skill-dir>/scripts/create-issue.sh" --project "<project>" -- --title "<title for $slug>" --body-file <TMPDIR>/$slug-body.md --label "<label>" --assignee "<assignee>" [--type "<name>"]
   done
   ```
5. Batch-link sub-issues to parent (if applicable), per **## Sub-Issues**
6. Ask about initial project status (e.g., "Backlog", "Current Sprint"), per **Asking the User** — then batch-update via `project-status.sh`
7. Print the batch summary table (`references/report-format.md`) instead of per-issue Step 1 reports
