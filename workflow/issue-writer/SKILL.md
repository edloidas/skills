---
name: issue-writer
description: Use this skill when the user asks to create, write, draft, or update a GitHub issue. It analyzes the user's description, asks clarifying questions, and produces a well-structured issue title and description following the project's template. Can also update existing issues.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Task AskUserQuestion
arguments: "issue description, issue number to update, or none for interactive mode"
argument-hint: "[description or issue number]"
---

# GitHub Issue Writer

## Purpose

Help users create and update well-structured GitHub issues by:

- Analyzing the user's initial description
- Asking targeted clarifying questions
- Generating a concise title (under 72 characters)
- Producing a comprehensive description using the project template
- Creating or updating issues on GitHub if in a git repository

## When to Use This Skill

Use this skill when the user:

**Creating issues:**
- Asks to "create an issue", "write an issue", or "draft an issue"
- Wants help structuring a bug report or feature request
- Mentions wanting to document a task for GitHub
- Needs to formalize a task description

**Updating issues:**
- Asks to "update issue", "edit issue", or "modify issue"
- Wants to "change the title" or "update description"
- References a specific issue: "update issue #123", "edit https://github.com/..."
- Says "update the issue" (use recently created issue from same session)

## Bundled Scripts

This skill includes helper bash scripts in the `scripts/` directory:

1. **check-environment.sh** - Validates git repo, gh CLI, and shows auth source (incl. cache status)
2. **get-repo-info.sh** - Retrieves repository details, labels, and recent issues
3. **get-issue.sh** - Fetches existing issue data (title, body, labels, state)
4. **create-issue.sh** - Creates a new issue
5. **update-issue.sh** - Updates an existing issue

To use bundled scripts, execute them from the skill directory:

```bash
bash scripts/check-environment.sh
bash scripts/get-repo-info.sh
bash scripts/get-issue.sh 123
bash scripts/create-issue.sh --title "Title" --body "Body" --label "enhancement"
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
| Default (simple task, draft) | Brief Description, Rationale, References, Implementation Notes |
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

Use the appropriate template based on the selected format. **BRIEF_DESCRIPTION is always required.**

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

_Drafted with AI assistance_
```

#### Short Issue Template

Use this minimal template for Short format issues. Note: No section headers (`##`), use bold text for markers instead:

```markdown
{{BRIEF_DESCRIPTION}}

**Rationale:** {{WHY_NEEDED - explain the motivation in 1-2 sentences}}

_Drafted with AI assistance_
```

#### Default Issue Template

Use this template for Default format issues:

```markdown
{{BRIEF_DESCRIPTION}}

---

## Rationale

{{WHY_NEEDED - explain the motivation}}

---

## References

{{REFERENCE_LINKS_OR_RELATED_ISSUES - include any relevant links, or "None" if not applicable}}

---

## Implementation Notes

{{BASIC_APPROACH_OR_HINTS - brief guidance on how to approach this}}

_Drafted with AI assistance_
```

### Step 6: Present to User

> **Important:** Always show the complete issue (title and description) to the user before creating it on GitHub. Skip this step only if the user explicitly requests to create without preview (e.g., "create without showing", "skip preview").

Show the user:

1. **Title:** The generated title
2. **Description:** The formatted description
3. **Type suggestion:** bug, feature, enhancement, documentation, etc.
4. **Label suggestions:** Based on the content

Ask if they want any modifications before creating.

### Step 6.5: Assign Issue

Before creating, determine who should be assigned to the issue.

**Fetch suggested assignees:**
```bash
bash scripts/get-repo-info.sh
```

The script outputs:
- Top contributors and collaborators for the repository

**Use `AskUserQuestion` to confirm assignee:**

**Requirements:**
- Always include `@me` (self-assign) as first (recommended) option
- Always include at least 2 other contributors from the repo
- Always include "No assignee" as last option
- Total: 4 options (self + 2 others + no assignee)

```
question: "Who should this issue be assigned to?"
header: "Assignee"
options:
  - label: "@me (Recommended)"
    description: "Self-assign since you're creating this issue"
  - label: "@{{PERSON_1}}"
    description: "{{Collaborator or top contributor to this repository}}"
  - label: "@{{PERSON_2}}"
    description: "{{Collaborator or top contributor to this repository}}"
  - label: "No assignee"
    description: "Leave unassigned for team triage"
```

**Priority for selecting the 2 other people:**
1. Repository collaborators
2. If less than 2 collaborators found, fill remaining slots with top contributors

**Example:**
```
options:
  - label: "@me (Recommended)"
    description: "Self-assign since you're creating this issue"
  - label: "@contributor-1"
    description: "Collaborator on this repository"
  - label: "@contributor-2"
    description: "Top contributor to this repository"
  - label: "No assignee"
    description: "Leave unassigned for team triage"
```

### Step 7: Create on GitHub (Optional)

If the user confirms and we're in a git repository:

**Use the bundled scripts:**

```bash
# First, check the environment
bash scripts/check-environment.sh

# Optionally, get repo info for context (labels, recent issues)
bash scripts/get-repo-info.sh

# Create the issue
bash scripts/create-issue.sh \
  --title "{{TITLE}}" \
  --body "{{DESCRIPTION}}" \
  --label "{{LABELS}}" \
  --assignee "@me"
```

**Or manual creation:**

```bash
gh issue create \
  --title "{{TITLE}}" \
  --body "$(cat <<'EOF'
{{DESCRIPTION}}
EOF
)" \
  --label "{{LABELS}}" \
  {{--assignee "@me" if requested}}
```

Return the issue URL to the user.

**Label Selection:**

1. First, fetch existing labels from the repository:
   ```bash
   gh label list --json name,description
   ```

2. Filter to only use labels matching these (case-insensitive):
   - `feature` - New functionality
   - `improvement` - Enhancement to existing functionality
   - `bug` - Something isn't working
   - `epic` - Large multi-issue effort
   - `critical` - High priority, needs immediate attention
   - `refactoring` - Code restructuring without behavior change
   - `r&d` - Research and development, exploration
   - `won't fix` - Acknowledged but not planned to address

3. Suggest from the filtered list based on issue type, or set none if no match

---

See `references/askuser-format.md` for AskUserQuestion standards and template.

---

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

### Brief Description (Required)
1-2 sentences describing what this is and its primary purpose. Be specific and actionable.

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

- `gh` CLI installed and authenticated (`gh auth login`)
- Must be run from within a GitHub repository

See `references/helper-scripts.md` for detailed script documentation, usage examples, and exit codes.

## Error Handling

- If `gh` CLI is not available, provide the formatted issue for manual creation
- If not in a git repository, skip GitHub integration and just provide the formatted output
- If user declines creation, provide the markdown for them to copy

## Keywords

issue, github, create issue, write issue, update issue, edit issue, modify issue, bug report, feature request, task, documentation
