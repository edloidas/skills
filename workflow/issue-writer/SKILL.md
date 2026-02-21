---
name: issue-writer
description: Use this skill when the user asks to draft, write, or update a GitHub issue. It analyzes the user's description, asks clarifying questions, and produces a well-structured issue title and description following the project's template. Can also update existing issues. For issue creation on GitHub, use issue-flow.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Task AskUserQuestion
arguments: "description issue-number"
argument-hint: "[description or issue number]"
---

# GitHub Issue Writer

## Purpose

Help users draft and update well-structured GitHub issues by:

- Analyzing the user's initial description
- Asking targeted clarifying questions
- Generating a concise title (under 72 characters)
- Producing a comprehensive description using the project template
- Updating existing issues on GitHub

## When to Use This Skill

Use this skill when the user:

**Drafting issues:**
- Asks to "write an issue" or "draft an issue"
- Wants help structuring a bug report or feature request
- Mentions wanting to document a task for GitHub
- Needs to formalize a task description

> For **creating** new issues on GitHub, use /issue-flow.

**Updating issues:**
- Asks to "update issue", "edit issue", or "modify issue"
- Wants to "change the title" or "update description"
- References a specific issue: "update issue #123", "edit https://github.com/..."
- Says "update the issue" (use recently created issue from same session)

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

**If not auto-detected**, use `AskUserQuestion` to ask:

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

**Format Auto-Detection:**
- If keywords like "short issue", "minimal issue", or "quick issue" are present, use Short format
- If keywords like "simple issue", "draft issue", or "basic issue" are present, use Default format

### Step 3: Interactive Questionnaire

Ask clarifying questions using `AskUserQuestion` tool to fill in gaps. Questions should be tailored to the issue type and scope.

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

Keep questions focused and avoid asking about things already clear from the description.

### Step 3.5: Confirm Label

Based on the type-to-label mapping from Step 2, use `AskUserQuestion` to confirm the label:

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

**Example for Feature type:**
```
options:
  - label: "feature (Recommended)"
    description: "New functionality being added"
  - label: "improvement"
    description: "Enhancement to existing functionality"
  - label: "epic"
    description: "Large feature spanning multiple issues"
  - label: "No label"
    description: "Skip label assignment"
```

**Example for Task type (with refactoring keywords):**
```
options:
  - label: "refactoring (Recommended)"
    description: "Code restructuring based on keywords: refactor, cleanup"
  - label: "improvement"
    description: "General enhancement"
  - label: "r&d"
    description: "Research and exploration work"
  - label: "No label"
    description: "Skip label assignment"
```

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

#### Full Issue Template

Use this comprehensive template for Full format issues (includes all sections as needed):

```markdown
{{BRIEF_DESCRIPTION}}

---

## Rationale

{{Include only if the "why" isn't obvious}}

- {{RATIONALE_POINT}}

---

## References

{{Include if there are relevant links}}

- {{REFERENCE: description}}

---

## Things to Consider

{{Include if there are important edge cases or decisions}}

- {{CONSIDERATION}}

---

## Implementation

> [!IMPORTANT]
> This is not a step-by-step guide — it's a functional checklist ordered logically.

{{Include for medium/large scope issues}}

1. {{IMPLEMENTATION_STEP}}

**UI Behavior:**

{{Include if there are specific interaction requirements}}

- {{UI_BEHAVIOR}}

---

## Acceptance Criteria

{{Always include — defines "done"}}

- [ ] {{CRITERION}}

---

## Testing Steps

{{Include if testing isn't obvious}}

1. {{TESTING_STEP}}

---

## Examples

{{Include if visual examples help clarify}}

**{{EXAMPLE_CASE}}**

![{{ALT_TEXT}}]({{IMAGE_URL}})

---

## Out of Scope _(Optional)_

{{Include only if scope boundaries need explicit definition}}

- {{OUT_OF_SCOPE_ITEM}}

---

## Technical Constraints _(Optional)_

{{Include only if there are specific technical requirements}}

- {{CONSTRAINT}}

---

<sub>*Drafted with AI assistance*</sub>
```

#### Short Issue Template

Use this minimal template for Short format issues. No section headers, no horizontal rules:

```markdown
{{DESCRIPTION — 4-6 sentences. Explain the issue naturally: what happens, what's affected, why it matters. Keep the user's original phrasing.}}

**Rationale:** {{WHY_NEEDED — 1-2 sentences}}

<sub>*Drafted with AI assistance*</sub>
```

#### Default Issue Template

Use this template for Default format issues. Use h5 headers, no horizontal rules:

```markdown
{{DESCRIPTION — 4-8 sentences: what the issue is, what it affects, how to reproduce (when applicable), what's impacted. Keep the user's original phrasing.}}

##### Rationale

{{WHY_NEEDED — explain why this needs to be fixed or implemented}}

##### References

{{Include only if there are relevant links or related issues}}

##### Implementation Notes

{{Include only if the approach is already known — brief notes on what needs to be done}}

<sub>*Drafted with AI assistance*</sub>
```

### Step 6: Present to User

Show the user:

1. **Title:** The generated title
2. **Description:** The formatted description
3. **Type suggestion:** bug, feature, enhancement, documentation, etc.
4. **Label suggestions:** Based on the content

Ask if they want any modifications.

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

> **Important:** Always show the changes to the user before updating the issue on GitHub. Skip this step only if the user explicitly requests to update without preview (e.g., "update without showing", "skip preview").

Show the user:
- **Before**: Current title/description
- **After**: New title/description
- **Label changes**: Labels being added/removed

Ask for confirmation before updating.

### Step 6: Update on GitHub

```bash
bash scripts/update-issue.sh \
  --issue {{ISSUE_NUMBER}} \
  --title "{{NEW_TITLE}}" \
  --body "{{NEW_DESCRIPTION}}" \
  --add-label "{{LABEL}}" \
  --remove-label "{{LABEL}}"
```

Return the updated issue URL to the user.

## Template Section Guidelines

### Description (Required)
The opening paragraph before any sections. Length varies by format: Short 4-6 sentences, Default 4-8 sentences, Full 1-2 sentences (detailed sections follow). Describe the issue in present tense. Preserve the user's original phrasing — restructure for clarity, don't rewrite.

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

## Keywords

issue, github, draft issue, write issue, update issue, edit issue, modify issue, bug report, feature request, task, documentation
