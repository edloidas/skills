---
name: issue-writer
description: >
  Draft or update a GitHub issue. Analyzes the description, asks clarifying questions, and
  produces a well-structured title and body following the project's template. Can update an
  existing issue or prepare a draft for filing later.
when_to_use: >
  On "draft an issue", "write an issue", "write this up as an issue", "update issue #N", "edit
  that issue", or "reword the issue body". Also when a bug report, feature request, task, or
  documentation gap has to become a well-formed GitHub issue before work starts, or when a
  draft is wanted for later filing rather than immediate creation.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Glob AskUserQuestion
argument-hint: "[description or issue number]"
---

# GitHub Issue Writer

Drafts and updates well-structured GitHub issues: analyzes the description, asks targeted
clarifying questions, generates a title under 72 characters, and produces a body from the
project template.

**Mutation class: writes to external services, and only on the update path.** The draft
path writes nothing anywhere — it prints a title and body for the user or for `issue-flow`
to file. The update path edits an existing issue on GitHub through
`scripts/update-issue.sh`, after the approval gate in Step 5.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Which Workflow

A request naming an existing issue — "update issue #123", "edit that issue", "reword the
body", or a bare "update the issue" pointing at one created earlier in this session — runs
the **Update Workflow**. Everything else runs the drafting **Workflow** below.

> For **creating** new issues on GitHub, use `issue-flow` when that skill is
> available. Otherwise use this skill to prepare the title and body, then
> create the issue with the available GitHub tooling.

## Bundled Scripts

This skill includes helper bash scripts in the `scripts/` directory:

1. **get-issue.sh** - Fetches existing issue data (title, body, labels, state)
2. **update-issue.sh** - Updates an existing issue

To use bundled scripts, execute them from the skill directory:

```bash
bash scripts/get-issue.sh 123
bash scripts/update-issue.sh --issue 123 --title "New Title" --add-label "bug"
```

## Workflow

Follow these steps in order. Adapt based on the scope and complexity of the issue.

### Step 1: Gather Initial Input

Ask the user to describe what they want the issue to cover. If they've already provided a description, proceed to analysis.

### Step 1.5: Determine Format

Check if the user's request indicates a preferred format:

**Auto-detect Short format** if keywords present:
- "short issue", "minimal issue", "quick issue"

**Auto-detect Default format** if keywords present:
- "simple issue", "draft issue", "basic issue"

**If not auto-detected**, ask the user which format they want, per **Asking the User**:

```
question: "What level of detail should this issue have?"
header: "Format"
options:
  - label: "Default (Recommended)"
    description: "Simple format with description, rationale, references, and implementation notes"
  - label: "Short"
    description: "Minimal format with just description and rationale (no section headers)"
  - label: "Full"
    description: "Comprehensive format with acceptance criteria, testing steps, and detailed implementation plan"
```

### Step 2: Analyze and Categorize

Determine the issue type based on the description:

- **Feature**: New functionality or enhancement
- **Bug**: Something is broken or not working as expected
- **Task**: General work item, refactoring, documentation
- **Question**: Needs discussion or clarification

**Type-to-Label Mapping:**

Based on the issue type, determine the recommended label:

| Type | Recommended Label | Notes |
|------|------------------|-------|
| Bug | `bug` | Add `critical` if severe/blocking |
| Feature | `feature` | New functionality |
| Task | Context-based | See keywords below |
| Question | None | Usually doesn't need a label |

**Task Label Keywords:**
- Keywords: refactor, cleanup, reorganize, restructure → `refactoring`
- Keywords: improve, enhance, update, optimize, better → `improvement`
- Keywords: research, investigate, explore, spike, prototype → `r&d`
- Default (no keywords matched): `improvement`

Identify which template sections are relevant based on scope:

| Scope | Required Sections |
|-------|-------------------|
| Short (minimal, quick) | Brief Description, Rationale (no section headers, bold markers only) |
| Default (simple task, draft) | Description, Rationale; optionally References, Implementation Notes |
| Small (bug fix, typo) | Brief Description, Acceptance Criteria |
| Medium (feature, enhancement) | Brief Description, Rationale, Implementation, Acceptance Criteria |
| Large / Full (architecture, major feature) | All sections as needed |

### Step 3: Interactive Questionnaire

Ask clarifying questions to fill in gaps, per **Asking the User**. Tailor them to the
issue type and scope.

**For Features:**
- What problem does this solve?
- Are there any design references or examples?
- What are the key acceptance criteria?
- Any technical constraints to consider?

**For Bugs:**
- What is the expected behavior?
- What is the actual behavior?
- Steps to reproduce?
- Any error messages or screenshots?

**For Tasks:**
- Why is this work needed now?
- Are there dependencies on other work?
- What does "done" look like?

Ask at most three of these in one round, and only the ones the description leaves open —
a question whose answer is already in the user's own text costs a turn and returns nothing.

### Step 3.5: Confirm Label

Based on the type-to-label mapping from Step 2, confirm the label, per **Asking the User**:

```
question: "Which label best describes this issue?"
header: "Label"
options:
  - label: "{{RECOMMENDED_LABEL}} (Recommended)"
    description: "Based on issue type: {{TYPE}}"
  - label: "{{ALTERNATIVE_LABEL_1}}"
    description: "{{DESCRIPTION_1}}"
  - label: "{{ALTERNATIVE_LABEL_2}}"
    description: "{{DESCRIPTION_2}}"
  - label: "No label"
    description: "Skip label assignment"
```

**Example for Bug type:**
```
options:
  - label: "bug (Recommended)"
    description: "This appears to be a bug based on the error behavior described"
  - label: "critical"
    description: "High priority bug, needs immediate attention"
  - label: "improvement"
    description: "If this is more of an enhancement than a bug"
  - label: "No label"
    description: "Skip label assignment"
```

The other types take the same shape with these labels, `No label` always last:

| Type | Recommended | Alternative 1 | Alternative 2 |
| ---- | ----------- | ------------- | ------------- |
| Feature | `feature` — new functionality | `improvement` — enhances what exists | `epic` — spans multiple issues |
| Task (refactor keywords) | `refactoring` — code restructuring | `improvement` — general enhancement | `r&d` — research and exploration |
| Question | `No label` (recommended) | — | — |

### Step 4: Generate Title

Create a title that:

- Is under 72 characters (hard limit)
- Starts with the component/area if applicable (e.g., "Button: Add loading state")
- Uses imperative mood ("Add", "Fix", "Update", not "Adding", "Fixed")
- Is specific but concise
- Avoids redundant words like "Issue:" or "Task:"

**Good examples:**
- `Button: Add disabled state visual feedback`
- `Fix tooltip positioning on viewport edge`
- `TreeView: Implement keyboard navigation`

**Bad examples:**
- `Issue: There's a problem with buttons` (vague, has "Issue:")
- `Adding a new feature for users to be able to see loading spinners` (too long, wrong mood)

### Step 5: Generate Description

Use the appropriate template based on the selected format.

**Writing rules (all formats):**

1. Never start the description with a markdown header — always lead with plain text
2. Use present tense for existing problems ("the button does not respond", not "the button did not respond" or "added responsive button handling") — describe the issue as it currently exists
3. Preserve the user's original wording where possible — restructure, don't rewrite

The templates live in `references/templates.md`, one per format — Full, Default, and
Short. Read the one matching the chosen format. `## Template Section Guidelines` below
says what belongs in each section.

### Step 6: Present to User

Show the user:

1. **Title:** The generated title
2. **Description:** The formatted description
3. **Type suggestion:** bug, feature, enhancement, documentation, etc.
4. **Label suggestions:** Based on the content

A finished Default-format draft:

````markdown
**Title:** `Tooltip: Fix clipping at the viewport edge`

**Description:**

The tooltip is cut off when its anchor sits near the bottom of the window. It renders
below the anchor regardless of the space available, so the last two lines fall outside
the viewport and cannot be scrolled into view. It reproduces on any page where an anchor
is within roughly 80px of the bottom edge, in every browser tested. Users lose the end of
the text, which on the form fields is where the validation rule is stated.

#### Rationale

The tooltip carries validation copy nobody else states, so a clipped tooltip means a rule
the user cannot read at all.

#### Implementation Notes

Placement is resolved once on mount from an already-clamped anchor rect, so the overflow
check always passes. Resolve placement after measuring instead, and flip above the anchor
when the rect overflows.
````

**Type:** Bug · **Label:** `bug`

Then ask whether they want changes, per **Asking the User**. Once they are satisfied,
stop. Do not create the issue on GitHub, and do not offer to — `issue-flow` files it, and
the user decides when. This step's deliverable is the text above and nothing else.

## Update Workflow

Use this workflow when the user wants to update an existing issue.

### Step 1: Identify the Issue

Determine which issue to update:

1. **Issue specified**: User provides issue number or URL
   - `#123`, `123`, `https://github.com/owner/repo/issues/123`
2. **Recent issue in session**: If an issue was just created in this conversation, offer to use that
3. **Ask**: If neither, ask the user for the issue number or URL

### Step 2: Fetch Current Issue Data

```bash
bash scripts/get-issue.sh <issue-number-or-url>
```

Show the user:
- Current title
- Current description (summarized if long)
- Current labels

### Step 3: Determine Changes

Ask the user what they want to change:
- Title only
- Description only
- Both title and description
- Labels (add or remove)

### Step 4: Apply Changes

For description updates:
- If minor edit: Apply the specific change
- If rewrite: Use the same template logic as creating (Steps 2-5 of create workflow)

For title updates:
- Follow the same title guidelines (under 72 chars, imperative mood)

### Step 5: Present Changes for Approval

An issue body is public and replaces what was there — an overwritten description cannot be
recovered from the issue itself. Show the changes and wait for approval before updating.
Skip the preview only when the user asked for that in so many words ("update without
showing", "skip preview").

Show the user:
- **Before**: Current title/description
- **After**: New title/description
- **Label changes**: Labels being added/removed

Then ask for confirmation, per **Asking the User**.

### Step 6: Update on GitHub

```bash
bash scripts/update-issue.sh \
  --issue {{ISSUE_NUMBER}} \
  --title "{{NEW_TITLE}}" \
  --body "{{NEW_DESCRIPTION}}" \
  --add-label "{{LABEL}}" \
  --remove-label "{{LABEL}}"
```

Report one line — `Updated #<N>: <what changed> — <url>` — and stop. Do not re-fetch the
issue to confirm the write; the script fails loudly if it did not land.

## Template Section Guidelines

### Description (Required)
The opening paragraph before any sections, written to the Step 5 writing rules. Length by format: Short 4-6 sentences, Default 4-8 sentences, Full 1-2 sentences (the detailed sections follow).

### Rationale (Optional)
Explain the "why" when it's not obvious:
- Business/technical value
- Why this approach vs alternatives
- Architectural decisions

### References (Optional)
Links that provide context:
- Design files (Figma, screenshots)
- Similar implementations
- Documentation or RFCs
- Related issues/PRs

### Things to Consider (Optional)
Important aspects affecting implementation:
- Edge cases
- Performance considerations
- Integration points
- Future extensibility

### Implementation (Medium/Large scope)
Functional checklist, not micromanagement:
- Clear about WHAT needs to be done
- Context for WHY
- Code snippets for complex patterns
- Logical order

### UI Behavior (If applicable)
Expected user interactions:
- Focus management
- Keyboard navigation
- Animations/transitions
- Responsive behavior

### Acceptance Criteria (Required)
Testable yes/no checkboxes defining completion.

### Testing Steps (Optional)
How to find and test in the application:
- Navigation steps
- Actions to trigger
- Expected outcomes

### Examples (Optional)
Screenshots, mockups, or code examples showing expected result.

### Out of Scope (Optional)
What is explicitly NOT part of this task. Prevents scope creep.

### Technical Constraints (Optional)
Specific requirements:
- Performance targets
- Browser support
- Accessibility standards

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth login`) — required for updating issues
- Must be run from within a GitHub repository for update operations

See `references/helper-scripts.md` for detailed script documentation, usage examples, and exit codes.

## Error Handling

- If `gh` CLI is not available, skip update operations and just provide the formatted output
- If not in a git repository, skip GitHub integration and just provide the formatted output
