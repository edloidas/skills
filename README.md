<p align="center">
  <img src="assets/logo.png" width="180" alt="edloidas/skills">
</p>

<h1 align="center">Skills</h1>

<p align="center">
  <em>One collection of agent skills. Four coding agents. One install command each.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/tag/edloidas/skills?style=flat-square&color=FD3DB5&label=release" alt="Release">
  <img src="https://img.shields.io/badge/skills-44-FD3DB5?style=flat-square" alt="44 skills">
  <img src="https://img.shields.io/badge/agents-4-FD3DB5?style=flat-square" alt="4 agents">
  <img src="https://img.shields.io/badge/license-MIT-FD3DB5?style=flat-square" alt="MIT license">
</p>

---

44 skills for planning, building, reviewing, auditing, maintaining, and shipping software —
written once and distributed to [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://developers.openai.com/codex), [OpenCode](https://opencode.ai), and
[pi](https://pi.dev), following the [Agent Skills specification](https://agentskills.io/specification).

Each skill is a self-contained folder of instructions the agent loads only when a task calls for
it. Nothing runs in the background, nothing is injected into every prompt.

| Group | What it covers | Skills |
| ----- | -------------- | -----: |
| [plan](#plan) | Issue drafting, scope analysis, backlog triage, full issue lifecycle | 4 |
| [build](#build) | Worktrees, conflict resolution, commits, findings fixes | 5 |
| [review](#review) | Adversarial + contextual review, cleanup, review board, spec extraction | 8 |
| [audit](#audit) | CI, scripts, security, skills, workspace, Three.js | 6 |
| [maintain](#maintain) | Label/rule/config sync, lint migration, repo hardening, comment audits, retros | 10 |
| [ship](#ship) | npm releases, Railway deployments | 2 |
| [assist](#assist) | Explanations, external opinions, discussion, handoffs | 6 |
| [write](#write) | Markdown, READMEs, and repository documentation | 1 |
| [obsidian](#obsidian) | Working documents in an Obsidian vault | 1 |
| [workflow](#workflow) | End-to-end issue workflow | 1 |

## Installation

| Agent | Install | What you get |
| ----- | ------- | ------------ |
| Claude Code | `/plugin marketplace add edloidas/skills` | 10 plugin groups, all 44 skills |
| Codex | `codex plugin marketplace add edloidas/skills` | 9 wrapper plugins, 35 skills |
| pi | `pi install git:github.com/edloidas/skills` | 36 skills |
| OpenCode | `./scripts/skills-packaging.sh install-host opencode` | 36 skills |
| Other | `npx skills add edloidas/skills --all` | All 44 skills |

Counts differ because each skill declares which hosts it supports. Eight skills depend on
Claude-only features — subagent fleets, the Skill tool, Claude's own config files — and ship only
there. See [How skills reach each agent](#how-skills-reach-each-agent).

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
/plugin install edloidas@write
/plugin install edloidas@obsidian
/plugin install edloidas@workflow
```

Install all groups for the full set, or pick only the groups relevant to your workflow.

| Scope | Command | Use case |
| ----- | ------- | -------- |
| User (default) | `/plugin install edloidas@review` | Personal — all projects |
| Project | `/plugin install edloidas@review --scope project` | Team — shared via Git |
| Local | `/plugin install edloidas@review --scope local` | Project — gitignored |

To load a group for a single session without installing it:

```bash
git clone https://github.com/edloidas/skills.git
claude --plugin-dir ./skills/review --plugin-dir ./skills/build
```

### Codex

Add the marketplace from GitHub — no `--ref` flag needed:

```bash
codex plugin marketplace add edloidas/skills
```

This installs and enables all nine wrapper plugins: `Edloidas Plan`, `Build`, `Review`, `Audit`,
`Maintain`, `Ship`, `Assist`, `Write`, and `Obsidian`. Codex clones the whole repository, so `git pull`
updates flow through. Restart Codex if new skills do not appear.

Opening this repository in Codex additionally exposes `.agents/skills/` and the repo marketplace at
`.agents/plugins/marketplace.json` for local use.

To install the Codex set into `~/.agents/skills` for use across repositories:

```bash
./scripts/skills-packaging.sh install-host codex
```

### pi

Install the whole collection as a pi package:

```bash
pi install git:github.com/edloidas/skills
```

This resolves the 36 pi-compatible skills through the `pi.skills` manifest in `package.json`.

Add `-l` to install project-locally into `.pi/settings.json` instead of globally. Note that
`pi list` only reports global packages, so a `-l` install shows up in `.pi/settings.json` rather
than in `pi list`.

To link a checkout instead of installing the package:

```bash
./scripts/skills-packaging.sh install-host pi
```

Project-local skill directories load only after the project is trusted.

### OpenCode

No plugin and no `opencode.json` change is needed — OpenCode reads skill directories directly and
follows symlinks:

```bash
git clone https://github.com/edloidas/skills.git
cd skills
./scripts/skills-packaging.sh install-host opencode
```

That links the 36 OpenCode-compatible skills into `~/.config/opencode/skills`. Pass `--dest <path>`
to install elsewhere. Re-run after `git pull`; it prunes only links pointing into this repo, so
unrelated skills in the destination are left alone.

Opening this repository in OpenCode surfaces its generated repo-local set automatically.

### npx skills

The [skills CLI](https://github.com/vercel-labs/skills) installs into any agent it supports and sees
all 44 skills with no extra flags:

```bash
npx skills add edloidas/skills --list                                  # list
npx skills add edloidas/skills --all                                   # install everything
npx skills add edloidas/skills --skill changes-review -a claude-code   # install one
```

It has no notion of per-host compatibility, so it installs everything regardless of target. This
repo's internal release tool is deliberately excluded from the listing.

## Verify your install

| Agent | Command | Expect |
| ----- | ------- | ------ |
| Claude Code | `/plugin` | The `edloidas` marketplace and its installed groups |
| Codex | `codex plugin list` | 9 `@edloidas-skills` plugins, `installed, enabled` |
| pi | `pi list` | The `edloidas/skills` package |
| OpenCode | `opencode debug skill` | Your skills in the JSON listing |
| Any | `npx skills ls` | Installed skills per agent |

OpenCode loads its skill list once at startup and does not hot-reload it. Restart OpenCode before
trusting `opencode debug skill` after an install.

## Uninstall

| Agent | Command |
| ----- | ------- |
| Claude Code | `/plugin uninstall edloidas@<group>`, then `/plugin marketplace remove edloidas` |
| Codex | `codex plugin marketplace remove edloidas-skills` |
| pi | `pi remove git:github.com/edloidas/skills` |
| OpenCode | `rm ~/.config/opencode/skills/<skill>`, or remove the whole directory |
| npx skills | `npx skills remove --all` |

`install-host` writes only symlinks, so removing them leaves nothing behind.

## How skills reach each agent

Every skill lives in exactly one real directory, `<group>/skills/<name>/`. Everything else is a
generated symlink tree pointing at it. Claude Code, Codex, OpenCode, and pi all resolve symlinks;
the `skills` CLI does not, which is why the canonical location must be a real directory.

| Agent | Discovery path | Installed by |
| ----- | -------------- | ------------ |
| Claude Code | `<group>/skills/` via each group's `plugin.json` | Plugin marketplace |
| Codex | `.agents/skills/`, `plugins/<name>/skills/` | Plugin marketplace, or `install-host codex` |
| pi | `.pi/skills/` via `pi.skills`; also `~/.pi/agent/skills/` and `~/.agents/skills/` | `pi install`, or `install-host pi` |
| OpenCode | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, and their `~/.config/opencode` and `~/.agents` equivalents | `install-host opencode` |

A skill's `compatibility:` frontmatter is the source of truth for which hosts it reaches, and
`scripts/skills-packaging.sh sync-repo` generates the trees from it. The Codex set is a subset of
every other host's set, because Codex, OpenCode, and pi all read `.agents/skills/`.

Regenerate and validate the whole layer from the repo root:

```bash
./scripts/skills-packaging.sh sync-repo
bash .github/scripts/validate-skills.sh
./scripts/validate-codex.sh
bash .github/scripts/validate-discovery.sh
```

`validate-discovery.sh` asserts what each host actually resolves, rather than trusting the manifests
to agree with each other.

## Available Skills

In the **Agent** column, `All` means Claude Code, Codex, OpenCode, and pi.

### Plan

Issue drafting, analysis, triage, and full issue lifecycle skills.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [issue-writer](./plan/skills/issue-writer/) | Draft and update well-structured GitHub issues | All |
| [issue-analyze](./plan/skills/issue-analyze/) | Analyze issue scope and produce an implementation task list | All |
| [next-issue](./plan/skills/next-issue/) | Find the most relevant next GitHub issue to work on | All |
| [issue-flow](./plan/skills/issue-flow/) | Full issue lifecycle: create, branch, commit, push, PR, merge | Claude |

### Build

Git worktree management, conflict resolution, commit summaries, quick commits, and findings fixes.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [git-worktree](./build/skills/git-worktree/) | Manage Git worktrees with configurable storage and agent settings copying | All |
| [resolve-conflicts](./build/skills/resolve-conflicts/) | Semi-automatic merge and rebase conflict resolution | All |
| [commit](./build/skills/commit/) | Fast staged-or-scoped commit with conventional message | All |
| [commit-summary](./build/skills/commit-summary/) | Generate formatted Git commit message summaries | All |
| [fix-findings](./build/skills/fix-findings/) | Triage and fix problems from reviews, consilium, or debugging | All |

### Review

Code review, cleanup, critical review board, and quality improvement skills.

`adversarial-review` and `changes-review` both take a diff and are deliberate opposites.
`adversarial-review` attacks it — parallel reviewers, context withheld, nothing mutated.
`changes-review` assesses it — full issue and PR context, tooling that may autofix, and an
interactive fix menu at the end.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [adversarial-review](./review/skills/adversarial-review/) | Parallel cold reviewers that hunt bugs and requirement gaps — finds, never fixes | Claude |
| [changes-review](./review/skills/changes-review/) | Deep logic analysis of code changes | All |
| [code-cleanup](./review/skills/code-cleanup/) | Trim AI comment noise — restated/rationale comments — keep real gotchas | All |
| [consilium](./review/skills/consilium/) | Critical review board — up to 6 reviewers (2 core + 4 on-demand) | Claude |
| [react-review](./review/skills/react-review/) | Review React code for effects, conventions, and patterns | All |
| [review-comments](./review/skills/review-comments/) | Analyze PR review comments — triage into fix/skip with reasoning | All |
| [spec-extractor](./review/skills/spec-extractor/) | Extract a behavioral spec from a codebase (1 file up to 500+ files) | Claude |
| [test-quality](./review/skills/test-quality/) | Write behavior-pinning tests; audit, fix, or delete bad ones | All |

### Audit

CI, script, security, skill, workspace, and Three.js auditing skills.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [ci-audit](./audit/skills/ci-audit/) | Analyze GitHub Actions workflows for optimization | All |
| [scripts-audit](./audit/skills/scripts-audit/) | Analyze package.json scripts for naming, composition, and consistency | All |
| [security-audit](./audit/skills/security-audit/) | Audit GitHub Actions, release config, and repo settings for supply chain | All |
| [skill-audit](./audit/skills/skill-audit/) | Audit skills for quality, specification compliance, and Codex readiness | All |
| [three-audit](./audit/skills/three-audit/) | Audit Three.js / React Three Fiber code for perf and best-practice issues | All |
| [workspace-audit](./audit/skills/workspace-audit/) | Analyze pnpm workspace and monorepo setup | All |

### Maintain

Label sync, instruction file sync, permissions cleanup, lint migration, comment auditing, agent rule sync, editor config sync, repo security hardening, stale process cleanup, and session retros.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [labels-sync](./maintain/skills/labels-sync/) | Check, apply, or export GitHub repository labels as reusable JSON | All |
| [claude-md-sync](./maintain/skills/claude-md-sync/) | Detect and fix stale references in project CLAUDE.md or AGENTS.md | All |
| [editor-config](./maintain/skills/editor-config/) | Init or merge `.zed` / `.vscode` editor configs from a canonical set | All |
| [permissions-cleanup](./maintain/skills/permissions-cleanup/) | Clean up stale permission entries from settings files | Claude |
| [lint-sync](./maintain/skills/lint-sync/) | Compare ESLint rules against Biome for overlap | All |
| [comment-audit](./maintain/skills/comment-audit/) | Analyze code comments for quality and relevance | All |
| [rules-sync](./maintain/skills/rules-sync/) | Init or update `.claude/rules` / `.agents/rules` from a canonical set | All |
| [repo-hardening](./maintain/skills/repo-hardening/) | Apply a GitHub security baseline: rulesets, Actions defaults, environments | All |
| [stale-process-cleanup](./maintain/skills/stale-process-cleanup/) | Find and reap orphaned dev servers, LSP, and MCP processes | All |
| [retro](./maintain/skills/retro/) | Reflect on the current session and produce a structured retro report | Claude |

### Ship

Release workflows and deployment tools.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [npm-release](./ship/skills/npm-release/) | Guide npm/pnpm package release workflow | All |
| [railway](./ship/skills/railway/) | Interact with Railway deployments — status, logs, variables, deploy | All |

### Assist

External opinion and assistance tools.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [ask](./assist/skills/ask/) | Explain concepts, verify claims, or challenge decisions | All |
| [claude](./assist/skills/claude/) | Quick external opinion from Claude Code CLI | Codex, OpenCode, pi |
| [codex](./assist/skills/codex/) | Quick external opinion from Codex CLI | Claude, OpenCode, pi |
| [discuss](./assist/skills/discuss/) | Iterative discussion mode — analyze, push back, and polish, no code edits | All |
| [handoff](./assist/skills/handoff/) | Compact the session into a handoff — inline text or per-project doc file | All |
| [polish-prompt](./assist/skills/polish-prompt/) | Iteratively polish a prompt via blind-judged tournament rounds | Claude |

`codex` and `claude` are mirrors of each other: each shells out to the other model family's CLI,
so each ships everywhere except its own host, where it would be recursive.

### Write

Markdown, README, and repository documentation writing.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [markdown-writing](./write/skills/markdown-writing/) | Write READMEs, docs, PRs, and issues that lead with the point — GitHub alerts, structure, README skeleton | All |

### Obsidian

Obsidian vault organization and working document management skills.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [working-docs](./obsidian/skills/working-docs/) | Organize working documents in Obsidian with two-tier system | All |

### Workflow

End-to-end workflows that orchestrate multiple skills into a single command.

| Skill | Description | Agent |
| ----- | ----------- | ----- |
| [solve-issue](./workflow/skills/solve-issue/) | Full issue workflow: analyze, branch, plan, implement, verify, commit, push/PR/merge | Claude |

## Skill Structure

```
<group>/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata (auto-discovers skills)
└── skills/
    └── <skill-name>/         # Canonical location — a real directory, never a symlink
        ├── SKILL.md          # Required — frontmatter + instructions
        ├── agents/           # Optional — agent-specific configs (e.g. openai.yaml)
        ├── scripts/          # Optional — executable code
        ├── references/       # Optional — docs loaded on demand
        └── assets/           # Optional — templates, images, data files
```

`SKILL.md` is YAML frontmatter followed by Markdown instructions:

```markdown
---
name: example-skill
description: Does X when the user asks for Y.
compatibility: Claude Code, Codex, OpenCode, Pi
---

## Steps

1. First, do this.
2. Then, do that.
```

Skills use progressive disclosure: only `name` and `description` stay in context, and the body loads
on demand. Detailed material belongs in `references/`, not in the body.

## Contributing

[CLAUDE.md](CLAUDE.md) is the authoring guide — frontmatter fields, naming rules, per-host
packaging, and the validation contract. In short: create `<group>/skills/<name>/SKILL.md` as a real
directory, declare `compatibility`, add `agents/openai.yaml` and a `scripts/codex/catalog.json`
entry if it targets Codex, add a row to the table above, then run `sync-repo` and the validators.

## License

[MIT](LICENSE)
