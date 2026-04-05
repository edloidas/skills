# Projects V2 Integration

## Token Configuration

GitHub Projects V2 API requires a token with `read:project` scope. The bundled `resolve-project-token.sh` resolves tokens in this order:

1. **`GH_PROJECTS_TOKEN`** environment variable — set a fine-grained PAT with `read:project` scope
2. **`gh auth token`** — falls back to the current gh CLI token (may lack project scope)

## Setting Up a Fine-Grained PAT

1. Go to [GitHub Settings > Developer settings > Fine-grained tokens](https://github.com/settings/tokens?type=beta)
2. Create a new token with these permissions:
   - **Repository access**: All repositories (or select specific ones)
   - **Permissions**: Issues (Read & Write), Projects (Read & Write)
3. Export as environment variable:
   ```bash
   export GH_PROJECTS_TOKEN="github_pat_..."
   ```
4. Optionally add to your shell profile (`~/.zshrc`, `~/.bashrc`)

## How Projects Integration Works

### Adding Issues to Projects

`add-to-project.sh <issue-number> <project-title> [status]`

- Searches repo-level projects first, then org-level
- Case-insensitive project title matching
- Optionally sets initial status (calls `project-status.sh`)

### Updating Project Status

`project-status.sh <issue-number> <status>`

- Finds the issue's associated project automatically
- Discovers the Status field via GraphQL introspection
- Case-insensitive status value matching

### Typical Status Values

| Status      | When set           |
| ----------- | ------------------ |
| In Progress | Branch created     |
| Review      | PR created         |
| Done        | PR merged & closed |

Actual status options depend on the project's configuration.

## Graceful Degradation

If project operations fail at any point, the skill warns once and skips all subsequent project operations. The core issue lifecycle (create, branch, commit, push, PR, merge) works without project integration.
