# Skills

A public collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex agent skills following the [Agent Skills specification](https://agentskills.io/specification).

## Installation

### Claude Code

Add the marketplace and install the plugin groups you need:

```
/plugin marketplace add edloidas/skills
/plugin install edloidas@review
/plugin install edloidas@audit
/plugin install edloidas@workflow
/plugin install edloidas@obsidian
/plugin install edloidas@tools
```

Install all groups for the full set, or pick only the groups relevant to your workflow.

### Scopes

| Scope          | Command                                          | Use case                |
| -------------- | ------------------------------------------------ | ----------------------- |
| User (default) | `/plugin install edloidas@review`                | Personal — all projects |
| Project        | `/plugin install edloidas@review --scope project`| Team — shared via Git   |
| Local          | `/plugin install edloidas@review --scope local`  | Project — gitignored    |

### Codex

When you open this repository in Codex, it exposes two Codex-native integration paths:

- Repo skills via `.agents/skills/` — curated symlinks to Codex-vetted skills for live repo-local use
- Repo marketplace via `.agents/plugins/marketplace.json` — grouped wrapper plugins with Codex install metadata

Available Codex plugin groups in this repo marketplace:

- `Edloidas Review`
- `Edloidas Audit`
- `Edloidas Workflow`
- `Edloidas Obsidian`
- `Edloidas Tools`

These wrapper plugins expose the Codex-vetted subset of each source group, not every skill in the
repository.

Codex follows symlinked skill folders, so updates from `git pull` flow through automatically. If new skills or plugin changes do not appear, restart Codex.

The Codex wrapper layer is defined in `scripts/codex/catalog.json` and can be regenerated from the repo root:

```bash
./scripts/validate-codex.sh
./scripts/codex-packaging.sh sync-repo
```

Treat `.agents/plugins/marketplace.json`, `plugins/<plugin-name>/.codex-plugin/plugin.json`,
`.agents/skills/`, and `plugins/<plugin-name>/skills/` as generated Codex wrapper outputs. Edit
`scripts/codex/catalog.json` and source skills first, then rerun the sync script.

To install one or more Codex skill groups into your home-level `~/.agents/skills` without copying:

```bash
./scripts/codex-packaging.sh install-links review workflow
```

For user-scoped installation outside the repo, you can still install individual skills directly into `~/.codex/skills`:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo edloidas/skills \
  --path audit/ci-audit review/code-cleanup review/react-review audit/scripts-audit audit/workspace-audit
```

No `.curated` folder is required for this repo; installs use explicit `--path` values.

## Skill Structure

Skills are organized into plugin groups, each containing related skills:

```
<group>/
├── .claude-plugin/
│   └── plugin.json       # Plugin metadata (auto-discovers skills via "skills": "./")
├── .codex-plugin/        # Only in wrapper plugins under plugins/<plugin-name>/
│   └── plugin.json       # Codex plugin manifest (wrapper plugin only)
├── <skill-name>/
│   ├── SKILL.md          # Required — frontmatter + instructions
│   ├── agents/           # Optional — agent-specific configs (e.g. openai.yaml)
│   ├── scripts/          # Optional — executable code
│   ├── references/       # Optional — additional documentation
│   └── assets/           # Optional — templates, images, data files
└── ...
```

The `SKILL.md` file contains YAML frontmatter (`name`, `description`) followed by Markdown instructions:

```markdown
---
name: example-skill
description: Does X when the user asks for Y.
---

## Steps

1. First, do this.
2. Then, do that.
```

See the full [Agent Skills specification](https://agentskills.io/specification) for all available frontmatter fields and conventions.

## Available Skills

### Review

Code review, cleanup, and quality improvement skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [changes-review](./review/changes-review/)                  | Deep logic analysis of code changes                                       | Claude        |
| [code-cleanup](./review/code-cleanup/)                      | Post-implementation cleanup of comments and artifacts                     | Claude, Codex |
| [codex](./review/codex/)                                    | Quick external opinion from Codex CLI                                     | Claude        |
| [comment-audit](./review/comment-audit/)                    | Analyze code comments for quality and relevance                           | Claude, Codex |
| [consilium](./review/consilium/)                            | Critical review board — up to 6 reviewers (2 core + 4 on-demand)         | Claude        |
| [react-review](./review/react-review/)                      | Review React code for effects, conventions, and patterns                  | Claude, Codex |
| [review-comments](./review/review-comments/)                | Analyze PR review comments — triage into fix/skip with reasoning          | Claude, Codex |

### Audit

CI, lint, script, skill, and workspace auditing skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [ci-audit](./audit/ci-audit/)                               | Analyze GitHub Actions workflows for optimization                         | Claude, Codex |
| [lint-sync](./audit/lint-sync/)                              | Compare ESLint rules against Biome for overlap                            | Claude, Codex |
| [scripts-audit](./audit/scripts-audit/)                     | Analyze package.json scripts for consistency                              | Claude, Codex |
| [skill-audit](./audit/skill-audit/)                         | Audit skills for quality and specification compliance                     | Claude        |
| [workspace-audit](./audit/workspace-audit/)                 | Analyze pnpm workspace and monorepo setup                                 | Claude, Codex |

### Workflow

Git, GitHub, release, and development workflow skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [claude-md-sync](./workflow/claude-md-sync/)                | Detect and fix stale references in project CLAUDE.md or AGENTS.md         | Claude, Codex |
| [commit-summary](./workflow/commit-summary/)                | Generate formatted Git commit message summaries                           | Claude, Codex |
| [fix-findings](./workflow/fix-findings/)                    | Triage and fix problems from reviews, consilium, or debugging             | Claude        |
| [git-worktree](./workflow/git-worktree/)                    | Manage Git worktrees with configurable storage and agent settings copying | Claude, Codex |
| [issue-flow](./workflow/issue-flow/)                        | Full issue lifecycle: create, branch, commit, push, PR, merge            | Claude        |
| [issue-analyze](./workflow/issue-analyze/)                  | Analyze issue scope and produce an implementation task list               | Claude, Codex |
| [issue-writer](./workflow/issue-writer/)                    | Draft and update well-structured GitHub issues                            | Claude, Codex |
| [labels-sync](./workflow/labels-sync/)                      | Synchronize GitHub repository labels from JSON                            | Claude, Codex |
| [next-issue](./workflow/next-issue/)                        | Find the most relevant next GitHub issue to work on                       | Claude, Codex |
| [npm-release](./workflow/npm-release/)                      | Guide npm/pnpm package release workflow                                   | Claude, Codex |
| [permissions-cleanup](./workflow/permissions-cleanup/)       | Clean up stale permission entries from settings files                     | Claude        |
| [resolve-conflicts](./workflow/resolve-conflicts/)          | Semi-automatic merge and rebase conflict resolution                      | Claude        |

### Obsidian

Obsidian vault organization and working document management skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [working-docs](./obsidian/working-docs/)                    | Organize working documents in Obsidian with two-tier system               | Claude, Codex |

### Tools

Skills for working with specific external tools and CLIs.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [railway](./tools/railway/)                                 | Interact with Railway deployments — status, logs, variables, deploy       | Claude, Codex |

## Creating a Skill

1. Choose the appropriate group directory (`review/`, `audit/`, `workflow/`, `obsidian/`, or `tools/`)
2. Create a subdirectory matching the skill name
3. Add a `SKILL.md` with required `name` and `description` frontmatter
4. Write Markdown instructions in the body (keep under 500 lines)
5. Optionally add `scripts/`, `references/`, or `assets/` directories
6. Update the appropriate table above

## License

[MIT](LICENSE)
