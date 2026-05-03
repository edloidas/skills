# Skills

A public collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex agent skills following the [Agent Skills specification](https://agentskills.io/specification).

## Installation

### npx skills

Install skills to any supported agent using the [skills CLI](https://github.com/vercel-labs/skills):

```bash
# List available skills
npx skills add edloidas/skills --list

# Install all skills for all agents
npx skills add edloidas/skills --all

# Install a single skill to a specific agent
npx skills add edloidas/skills --skill changes-review -a claude-code
```

See the [skills CLI documentation](https://github.com/vercel-labs/skills) for the full list of
flags and supported source formats.

### Claude Code

Add the marketplace and install the plugin groups you need:

```
/plugin marketplace add edloidas/skills
/plugin install edloidas@plan
/plugin install edloidas@build
/plugin install edloidas@review
/plugin install edloidas@audit
/plugin install edloidas@maintain
/plugin install edloidas@ship
/plugin install edloidas@assist
/plugin install edloidas@obsidian
/plugin install edloidas@workflow
```

Install all groups for the full set, or pick only the groups relevant to your workflow.

#### Scopes

| Scope          | Command                                          | Use case                |
| -------------- | ------------------------------------------------ | ----------------------- |
| User (default) | `/plugin install edloidas@review`                | Personal — all projects |
| Project        | `/plugin install edloidas@review --scope project`| Team — shared via Git   |
| Local          | `/plugin install edloidas@review --scope local`  | Project — gitignored    |

### Manually

Clone the repo and load plugin groups with `--plugin-dir` (per-session, not persistent):

```bash
git clone https://github.com/edloidas/skills.git
claude --plugin-dir ./skills/review --plugin-dir ./skills/build
```

### Codex

When you open this repository in Codex, it exposes two repo-local integration paths:

- Repo skills via `.agents/skills/` — curated symlinks to Codex-vetted skills for use while this repo is open in Codex
- Repo marketplace via `.agents/plugins/marketplace.json` — repo-local wrapper plugin metadata for those same bundles

Available Codex plugin groups in this repo marketplace:

- `Edloidas Plan`
- `Edloidas Build`
- `Edloidas Review`
- `Edloidas Audit`
- `Edloidas Maintain`
- `Edloidas Ship`
- `Edloidas Assist`
- `Edloidas Obsidian`

These wrapper plugins expose the Codex-vetted subset of each source group, not every skill in the
repository. The generated wrapper layer is symlink-based and should be treated as repo-local.

Codex follows symlinked skill folders, so updates from `git pull` flow through automatically while
you are working inside this repository. For cross-repo or user-scoped use, install the skills into
a home-level directory instead of relying on the repo-local wrapper cache. If new repo-local skills
or plugin changes do not appear, restart Codex.

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
./scripts/codex-packaging.sh install-links --dest "$HOME/.agents/skills" review build
```

To install the full Codex-safe set for use across repositories:

```bash
./scripts/codex-packaging.sh install-links --dest "$HOME/.agents/skills" all
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

### Plan

Issue drafting, analysis, triage, and full issue lifecycle skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [issue-writer](./plan/issue-writer/)                        | Draft and update well-structured GitHub issues                            | Claude, Codex |
| [issue-analyze](./plan/issue-analyze/)                      | Analyze issue scope and produce an implementation task list               | Claude, Codex |
| [next-issue](./plan/next-issue/)                            | Find the most relevant next GitHub issue to work on                       | Claude, Codex |
| [issue-flow](./plan/issue-flow/)                            | Full issue lifecycle: create, branch, commit, push, PR, merge             | Claude        |

### Build

Git worktree management, conflict resolution, commit summaries, quick commits, and findings fixes.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [git-worktree](./build/git-worktree/)                      | Manage Git worktrees with configurable storage and agent settings copying  | Claude, Codex |
| [resolve-conflicts](./build/resolve-conflicts/)             | Semi-automatic merge and rebase conflict resolution                       | Claude, Codex |
| [commit](./build/commit/)                                   | Fast staged-or-scoped commit with conventional message (Haiku)             | Claude        |
| [commit-summary](./build/commit-summary/)                   | Generate formatted Git commit message summaries                           | Claude, Codex |
| [fix-findings](./build/fix-findings/)                       | Triage and fix problems from reviews, consilium, or debugging             | Claude        |

### Review

Code review, cleanup, critical review board, and quality improvement skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [changes-review](./review/changes-review/)                  | Deep logic analysis of code changes                                       | Claude, Codex |
| [code-cleanup](./review/code-cleanup/)                      | Post-implementation cleanup of comments and artifacts                     | Claude, Codex |
| [consilium](./review/consilium/)                            | Critical review board — up to 6 reviewers (2 core + 4 on-demand)         | Claude        |
| [react-review](./review/react-review/)                      | Review React code for effects, conventions, and patterns                  | Claude, Codex |
| [review-comments](./review/review-comments/)                | Analyze PR review comments — triage into fix/skip with reasoning          | Claude, Codex |
| [spec-extractor](./review/spec-extractor/)                  | Extract a behavioral spec from a codebase (1 file up to 500+ files)       | Claude        |

### Audit

CI, script, skill, and workspace auditing skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [ci-audit](./audit/ci-audit/)                               | Analyze GitHub Actions workflows for optimization                         | Claude, Codex |
| [scripts-audit](./audit/scripts-audit/)                     | Analyze package.json scripts for naming, composition, and consistency     | Claude, Codex |
| [skill-audit](./audit/skill-audit/)                         | Audit skills for quality, specification compliance, and Codex readiness   | Claude, Codex |
| [workspace-audit](./audit/workspace-audit/)                 | Analyze pnpm workspace and monorepo setup                                 | Claude, Codex |

### Maintain

Label sync, instruction file sync, permissions cleanup, lint migration, and comment auditing.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [labels-sync](./maintain/labels-sync/)                      | Check, apply, or export GitHub repository labels as reusable JSON         | Claude, Codex |
| [claude-md-sync](./maintain/claude-md-sync/)                | Detect and fix stale references in project CLAUDE.md or AGENTS.md         | Claude, Codex |
| [permissions-cleanup](./maintain/permissions-cleanup/)       | Clean up stale permission entries from settings files                     | Claude        |
| [lint-sync](./maintain/lint-sync/)                          | Compare ESLint rules against Biome for overlap                            | Claude, Codex |
| [comment-audit](./maintain/comment-audit/)                  | Analyze code comments for quality and relevance                           | Claude, Codex |

### Ship

Release workflows and deployment tools.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [npm-release](./ship/npm-release/)                          | Guide npm/pnpm package release workflow                                   | Claude, Codex |
| [railway](./ship/railway/)                                  | Interact with Railway deployments — status, logs, variables, deploy       | Claude, Codex |

### Assist

External opinion and assistance tools.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [ask](./assist/ask/)                                        | Explain concepts, verify claims, or challenge decisions                   | Claude, Codex |
| [codex](./assist/codex/)                                    | Quick external opinion from Codex CLI                                     | Claude        |
| [discuss](./assist/discuss/)                                | Iterative discussion mode — analyze, push back, and polish, no code edits | Claude        |
| [polish-prompt](./assist/polish-prompt/)                    | Iteratively polish a prompt via blind-judged tournament rounds            | Claude        |

### Obsidian

Obsidian vault organization and working document management skills.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [working-docs](./obsidian/working-docs/)                    | Organize working documents in Obsidian with two-tier system               | Claude, Codex |

### Workflow

End-to-end workflows that orchestrate multiple skills into a single command.

| Skill                                                       | Description                                                               | Agent         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| [solve-issue](./workflow/solve-issue/)                      | Full issue workflow: analyze, branch, plan, implement, verify, commit, push/PR/merge | Claude |

## Creating a Skill

1. Choose the appropriate group directory (`plan/`, `build/`, `review/`, `audit/`, `maintain/`, `ship/`, `assist/`, `obsidian/`, or `workflow/`)
2. Create a subdirectory matching the skill name
3. Add a `SKILL.md` with required `name` and `description` frontmatter
4. Write Markdown instructions in the body (keep under 500 lines)
5. Optionally add `scripts/`, `references/`, or `assets/` directories
6. Update the appropriate table above

## License

[MIT](LICENSE)
