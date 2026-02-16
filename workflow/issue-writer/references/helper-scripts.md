## Bundled Helper Scripts Details

### scripts/check-environment.sh

- Validates current directory is a git repository
- Checks if GitHub CLI (gh) is installed
- Verifies `gh` authentication status
- Shows remote origin information

**Exit codes:**
- `0` - Environment ready
- `1` - Not in a git repository
- `2` - gh CLI not installed
- `3` - No authentication method available

### scripts/get-repo-info.sh

- Uses `gh` for GitHub CLI calls
- Fetches repository details (name, owner, description)
- Lists available labels (filtered to allowed set)
- Shows recent issues for context and style guidance
- Lists assignable users (collaborators and top contributors)

### scripts/create-issue.sh

- Uses `gh` for GitHub CLI calls
- Creates issue with title, body, labels, and assignee
- Supports `--body` for inline content or `--body-file` for file input
- Handles special characters in body content
- Returns the created issue URL

**Usage:**
```bash
create-issue.sh --title "Title" --body "Body" [--label "label1,label2"] [--assignee "@me"]
create-issue.sh --title "Title" --body-file /path/to/body.md [--label "bug"]
```

### scripts/get-issue.sh

- Uses `gh` for GitHub CLI calls
- Fetches existing issue data by number or URL
- Returns JSON with title, body, labels, state, number, url
- Supports multiple input formats: `123`, `#123`, `owner/repo#123`, full URL

**Usage:**
```bash
get-issue.sh 123
get-issue.sh https://github.com/owner/repo/issues/123
```

### scripts/update-issue.sh

- Uses `gh` for GitHub CLI calls
- Updates existing issue title, body, and/or labels
- Supports adding and removing labels
- At least one modification required

**Usage:**
```bash
update-issue.sh --issue 123 --title "New Title"
update-issue.sh --issue 123 --body "New description"
update-issue.sh --issue 123 --add-label "bug" --remove-label "feature"
update-issue.sh --issue 123 --title "Title" --body-file /path/to/body.md
```
