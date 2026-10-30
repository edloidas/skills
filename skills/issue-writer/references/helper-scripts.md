## Bundled Helper Scripts Details

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
