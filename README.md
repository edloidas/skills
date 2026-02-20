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
```

Install all three for the full set, or pick only the groups relevant to your workflow.

### Scopes

| Scope          | Command                                          | Use case                |
| -------------- | ------------------------------------------------ | ----------------------- |
| User (default) | `/plugin install edloidas@review`                | Personal — all projects |
| Project        | `/plugin install edloidas@review --scope project`| Team — shared via Git   |
| Local          | `/plugin install edloidas@review --scope local`  | Project — gitignored    |

### Codex

Install directly from this GitHub repo into `~/.codex/skills`:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo edloidas/skills \
  --path audit/ci-audit review/code-cleanup review/react-improvements audit/scripts-audit audit/workspace-audit
```

No `.curated` folder is required for this repo; installs use explicit `--path` values.

## Skill Structure

Skills are organized into plugin groups, each containing related skills:

```
<group>/
├── .claude-plugin/
│   └── plugin.json       # Plugin metadata (auto-discovers skills via "skills": "./")
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
| [comment-audit](./review/comment-audit/)                    | Analyze code comments for quality and relevance                           | Claude        |
| [consilium](./review/consilium/)                            | Critical review board — up to 6 reviewers (2 core + 4 on-demand)         | Claude        |
| [react-improvements](./review/react-improvements/)          | Suggest React code improvements and patterns                              | Claude, Codex |

### Audit

CI, lint, script, skill, and workspace auditing skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [ci-audit](./audit/ci-audit/)                               | Analyze GitHub Actions workflows for optimization                         | Claude, Codex |
| [lint-sync](./audit/lint-sync/)                              | Compare ESLint rules against Biome for overlap                            | Claude        |
| [scripts-audit](./audit/scripts-audit/)                     | Analyze package.json scripts for consistency                              | Claude, Codex |
| [skill-audit](./audit/skill-audit/)                         | Audit skills for quality and specification compliance                     | Claude        |
| [workspace-audit](./audit/workspace-audit/)                 | Analyze pnpm workspace and monorepo setup                                 | Claude, Codex |

### Workflow

Git, GitHub, release, and development workflow skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [claude-md-sync](./workflow/claude-md-sync/)                | Detect and fix stale references in project CLAUDE.md                      | Claude        |
| [commit-summary](./workflow/commit-summary/)                | Generate formatted Git commit message summaries                           | Claude        |
| [git-worktree](./workflow/git-worktree/)                    | Manage Git worktrees with configurable storage and agent settings copying | Any           |
| [issue-flow](./workflow/issue-flow/)                        | Full issue lifecycle: create, branch, commit, push, PR, merge            | Claude        |
| [issue-writer](./workflow/issue-writer/)                    | Draft and update well-structured GitHub issues                            | Claude        |
| [labels-sync](./workflow/labels-sync/)                      | Synchronize GitHub repository labels from JSON                            | Claude        |
| [npm-release](./workflow/npm-release/)                      | Guide npm/pnpm package release workflow                                   | Claude        |
| [permissions-cleanup](./workflow/permissions-cleanup/)       | Clean up stale permission entries from settings files                     | Claude        |

## Creating a Skill

1. Choose the appropriate group directory (`review/`, `audit/`, or `workflow/`)
2. Create a subdirectory matching the skill name
3. Add a `SKILL.md` with required `name` and `description` frontmatter
4. Write Markdown instructions in the body (keep under 500 lines)
5. Optionally add `scripts/`, `references/`, or `assets/` directories
6. Update the appropriate table above

## License

[MIT](LICENSE)
