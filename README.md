# Skills

A public collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex agent skills following the [Agent Skills specification](https://agentskills.io/specification).

## Installation

### Claude Code

Add the marketplace and install the skills plugin:

```
/plugin marketplace add edloidas/skills
/plugin install edloidas-skills@edloidas-skills
```

This makes all 20 skills available in your Claude Code sessions.

### Scopes

| Scope          | Command                                                           | Use case                |
| -------------- | ----------------------------------------------------------------- | ----------------------- |
| User (default) | `/plugin install edloidas-skills@edloidas-skills`                 | Personal — all projects |
| Project        | `/plugin install edloidas-skills@edloidas-skills --scope project` | Team — shared via Git   |
| Local          | `/plugin install edloidas-skills@edloidas-skills --scope local`   | Project — gitignored    |

### Codex

Install directly from this GitHub repo into `~/.codex/skills`:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo edloidas/skills \
  --path ci-audit code-cleanup code-polish gradle-format lint-audit scripts-audit suggest-react-improvements text-fix tsconfig-audit workspace-audit
```

No `.curated` folder is required for this repo; installs use explicit `--path` values.

## Skill Structure

Each skill is a top-level directory containing at minimum a `SKILL.md` file:

```
<skill-name>/
├── SKILL.md              # Required — frontmatter + instructions
├── agents/               # Optional — agent-specific configs (e.g. openai.yaml)
├── scripts/              # Optional — executable code
├── references/           # Optional — additional documentation
└── assets/               # Optional — templates, images, data files
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

| Skill                                                       | Description                                                               | Agent         | Category     |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- | ------------ |
| [changes-review](./changes-review/)                         | Deep logic analysis of code changes                                       | Claude        | Review       |
| [ci-audit](./ci-audit/)                                     | Analyze GitHub Actions workflows for optimization                         | Claude, Codex | Audit        |
| [code-cleanup](./code-cleanup/)                             | Post-implementation cleanup of comments and artifacts                     | Claude, Codex | Code Quality |
| [code-polish](./code-polish/)                               | Analyze code changes for best practices and quality                       | Claude, Codex | Code Quality |
| [comment-audit](./comment-audit/)                           | Analyze code comments for quality and relevance                           | Claude        | Audit        |
| [git-worktree](./git-worktree/)                             | Manage Git worktrees with configurable storage and agent settings copying | Any           | Git          |
| [gradle-format](./gradle-format/)                           | Format and modernize Gradle build files                                   | Claude, Codex | Formatting   |
| [issue-writer](./issue-writer/)                             | Create and update well-structured GitHub issues                           | Claude        | GitHub       |
| [lint-audit](./lint-audit/)                                 | Analyze ESLint, Biome, and Oxlint configurations                          | Claude, Codex | Audit        |
| [lint-sync](./lint-sync/)                                   | Compare ESLint rules against Biome for overlap                            | Claude        | Audit        |
| [npm-release](./npm-release/)                               | Guide npm/pnpm package release workflow                                   | Claude        | Release      |
| [review-scope](./review-scope/)                             | Determine review scope from git diff                                      | Claude        | Review       |
| [scripts-audit](./scripts-audit/)                           | Analyze package.json scripts for consistency                              | Claude, Codex | Audit        |
| [suggest-react-improvements](./suggest-react-improvements/) | Suggest React code improvements and patterns                              | Claude, Codex | Code Quality |
| [summary-commit](./summary-commit/)                         | Generate formatted Git commit message summaries                           | Claude        | Git          |
| [sync-labels](./sync-labels/)                               | Synchronize GitHub repository labels from JSON                            | Claude        | GitHub       |
| [text-fix](./text-fix/)                                     | Fix grammar and polish text with minimal edits                            | Claude, Codex | Text         |
| [text-summary](./text-summary/)                             | Summarize text or URL content                                             | Claude        | Text         |
| [tsconfig-audit](./tsconfig-audit/)                         | Analyze TypeScript configurations for best practices                      | Claude, Codex | Audit        |
| [workspace-audit](./workspace-audit/)                       | Analyze pnpm workspace and monorepo setup                                 | Claude, Codex | Audit        |

## Creating a Skill

1. Create a directory at the repo root matching the skill name
2. Add a `SKILL.md` with required `name` and `description` frontmatter
3. Write Markdown instructions in the body (keep under 500 lines)
4. Optionally add `scripts/`, `references/`, or `assets/` directories
5. Update the table above

## License

[MIT](LICENSE)
