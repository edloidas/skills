<p align="center">
  <img src="assets/logo.png" width="180" alt="edloidas/skills">
</p>

<h1 align="center">Skills</h1>

<p align="center">
  <em>One collection of agent skills. Any coding agent. One command.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/tag/edloidas/skills?style=flat-square&color=FD3DB5&label=release" alt="Release">
  <img src="https://img.shields.io/badge/skills-38-FD3DB5?style=flat-square" alt="38 skills">
  <img src="https://img.shields.io/badge/agents-4-FD3DB5?style=flat-square" alt="4 agents">
  <img src="https://img.shields.io/badge/license-MIT-FD3DB5?style=flat-square" alt="MIT license">
</p>

---

38 skills for planning, building, reviewing, auditing, maintaining, and shipping software —
written once and distributed to [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://developers.openai.com/codex), [OpenCode](https://opencode.ai), and
[pi](https://pi.dev), following the [Agent Skills specification](https://agentskills.io/specification).

Each skill is a self-contained folder of instructions the agent loads only when a task calls for
it. Nothing runs in the background, nothing is injected into every prompt.

| Group | What it covers | Skills |
| ----- | -------------- | -----: |
| [plan](#plan) | Issue drafting, scope analysis, backlog triage, full issue lifecycle | 3 |
| [build](#build) | Conflict resolution, commits, findings fixes, live probes | 5 |
| [review](#review) | Adversarial change review, cleanup, claim verification, approach boards, PR feedback, spec extraction | 6 |
| [audit](#audit) | CI, scripts, security, skills, workspace, tsconfig, Three.js, React, tests | 9 |
| [maintain](#maintain) | Agent config, label and editor config sync, lint migration, repo hardening, process cleanup | 6 |
| [ship](#ship) | npm releases | 1 |
| [assist](#assist) | Explanations, external opinions, design discussion, handoffs, restatement | 5 |
| [write](#write) | Markdown, READMEs, repository documentation | 1 |
| [obsidian](#obsidian) | Working documents in an Obsidian vault | 1 |
| [workflow](#workflow) | End-to-end issue workflow | 1 |

## Installation

Any agent, one command — the [skills CLI](https://github.com/vercel-labs/skills) installs into every
agent it detects:

```bash
npx skills add edloidas/skills --all
```

`--all` is shorthand for every skill, every agent, no prompts. Narrow it however you like:

```bash
npx skills add edloidas/skills -l                               # list, install nothing
npx skills add edloidas/skills --all -g                         # every skill, user-level
npx skills add edloidas/skills -s changes-review,explain -y     # only these skills
npx skills add edloidas/skills -s changes-review -a claude-code  # one skill, one agent
```

Installs are project-level by default: skills land in `./.agents/skills/`, each supported agent gets
a symlink beside it, and `skills-lock.json` records the set. `-g` installs user-level instead, for
every project. The CLI has no notion of per-host compatibility, so it installs everything regardless
of target. This repo's internal release tool is deliberately excluded from the listing.

Each host also has a native install, which buys plugin grouping, namespaced skill names, and updates
through the host itself:

| Agent | Install | What you get |
| ----- | ------- | ------------ |
| Claude Code | `/plugin marketplace add edloidas/skills` | 10 plugin groups, every skill |
| Codex | `codex plugin marketplace add edloidas/skills` | 10 wrapper plugins |
| pi | `pi install git:github.com/edloidas/skills` | Every portable skill |
| OpenCode | `./scripts/skills-packaging.sh install-host opencode` | Every portable skill |

Every skill ships to all four agents except one. `code-to-spec` drives fleets of
plugin-namespaced subagents and keys its temp files on Claude's session id, so it is Claude Code
only. See [How skills reach each agent](#how-skills-reach-each-agent).

### Claude Code

Plugin ids are `<group>@edloidas` — the plugin first, the marketplace second. Add the marketplace,
then install the groups you need:

```
/plugin marketplace add edloidas/skills
/plugin install plan@edloidas
/plugin install build@edloidas
/plugin install review@edloidas
/plugin install audit@edloidas
/plugin install maintain@edloidas
/plugin install ship@edloidas
/plugin install assist@edloidas
/plugin install write@edloidas
/plugin install obsidian@edloidas
/plugin install workflow@edloidas
```

There is no marketplace-wide install, so the full set is either those ten lines or one shell loop:

```bash
claude plugin marketplace add edloidas/skills
for group in plan build review audit maintain ship assist write obsidian workflow; do
  claude plugin install "$group@edloidas"
done
```

| Scope | Command | Use case |
| ----- | ------- | -------- |
| User (default) | `/plugin install review@edloidas` | Personal — all projects |
| Project | `/plugin install review@edloidas --scope project` | Team — shared via Git |
| Local | `/plugin install review@edloidas --scope local` | Project — gitignored |

To hand a team the whole set through Git instead, commit the marketplace and the groups to
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "edloidas": { "source": { "source": "github", "repo": "edloidas/skills" } }
  },
  "enabledPlugins": {
    "plan@edloidas": true,
    "build@edloidas": true,
    "review@edloidas": true,
    "audit@edloidas": true,
    "maintain@edloidas": true,
    "ship@edloidas": true,
    "assist@edloidas": true,
    "write@edloidas": true,
    "obsidian@edloidas": true,
    "workflow@edloidas": true
  }
}
```

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

This installs and enables all 10 wrapper plugins: `Edloidas Plan`, `Build`, `Review`, `Audit`,
`Maintain`, `Ship`, `Assist`, `Write`, `Obsidian`, and `Workflow`. Codex clones the whole
repository, so `git pull` updates flow through. Restart Codex if new skills do not appear.

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

This resolves the pi-compatible skills through the `pi.skills` manifest in `package.json`.

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

That links the OpenCode-compatible skills into `~/.config/opencode/skills`. Pass `--dest <path>`
to install elsewhere. Re-run after `git pull`; it prunes only links pointing into this repo, so
unrelated skills in the destination are left alone.

Opening this repository in OpenCode surfaces its generated repo-local set automatically.

## Verify your install

| Agent | Command | Expect |
| ----- | ------- | ------ |
| Claude Code | `/plugin` | The `edloidas` marketplace and its installed groups |
| Codex | `codex plugin list` | 10 `@edloidas-skills` plugins, `installed, enabled` |
| pi | `pi list` | The `edloidas/skills` package |
| OpenCode | `opencode debug skill` | Your skills in the JSON listing |
| Any | `npx skills ls` | Installed skills per agent |

OpenCode loads its skill list once at startup and does not hot-reload it. Restart OpenCode before
trusting `opencode debug skill` after an install.

## Uninstall

| Agent | Command |
| ----- | ------- |
| Claude Code | `/plugin uninstall <group>@edloidas`, then `/plugin marketplace remove edloidas` |
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

Every skill below runs on Claude Code, Codex, OpenCode, and pi, with one exception noted in
[Review](#review).

### Plan

Issue drafting, analysis, and the full issue lifecycle.

`issue-flow` owns every git and GitHub write in the pipeline — picking the next issue,
creating it, branching, snapshots, commits, squashing, pushes, PRs, merges. Skills that
orchestrate the pipeline (`solve-issue`) delegate those actions to it instead of
reimplementing them, so the commit subject format and the squash rules live in one place.

| Skill | Description |
| ----- | ----------- |
| [issue-writer](./plan/skills/issue-writer/) | Draft and update well-structured GitHub issues |
| [issue-analyze](./plan/skills/issue-analyze/) | Analyze issue scope and produce an implementation task list |
| [issue-flow](./plan/skills/issue-flow/) | Full issue lifecycle: pick, create, branch, commit, push, PR, merge |

### Build

Conflict resolution, commit summaries, quick commits, findings fixes, and live behavioral probes.

| Skill | Description |
| ----- | ----------- |
| [resolve-conflicts](./build/skills/resolve-conflicts/) | Semi-automatic merge and rebase conflict resolution |
| [commit](./build/skills/commit/) | Fast staged-or-scoped commit with conventional message |
| [commit-summary](./build/skills/commit-summary/) | Derive a commit message body from the code behind the change |
| [fix-and-reverify](./build/skills/fix-and-reverify/) | Fix review findings in rounds, re-reviewing each fix |
| [live-probe](./build/skills/live-probe/) | Settle a claim about observable behavior by running it once |

### Review

Change review, cleanup, claim verification, PR feedback, approach boards, and spec extraction.

`changes-review` attacks a diff — parallel reviewers on different models, each blind to the
implementer's reasoning, then a verification round that re-attacks the findings before you see
them. It finds and never fixes; it posts only when asked, and then a finding reaches the author only
if it can be demonstrated and attributed to the branch rather than to the base. Publication takes the
shape the pull request allows — one issue comment on your own branch, a real review with per-line
comments and a verdict on someone else's. Every phase is configurable, so `pr-review` and
`solve-issue` drive the same primitive. Conventions and comment noise are `code-cleanup`'s job.
When the diff touches a stack one of the audit skills knows deeply, `changes-review` also loads it as
a lens — `react-audit` for React files, `three-audit` for Three.js and R3F — so a general reviewer
does not have to carry a stack-specific failure catalog. Both stay directly invocable on their own.

`pr-review` is the caller that primitive was built for. On someone else's branch it drives
`changes-review` and publishes the result as a real review; on your own it works the threads, and the
posture step decides whether answering is even its business before it decides what the answer is. It
verifies a claim's premise separately from its conclusion, because bot reviewers get the premise wrong
far more often than the conclusion, and it changes no code unless asked.

`consilium` is not a review skill. It takes a problem or a decision, not a diff: three seats generate
candidate approaches — one of them an agent outside this process, with none of the conversation's
context — and three attack the candidate set comparatively, then the surviving objections are verified
before anything is ranked. An approach already on the table enters as one candidate among several
rather than as the subject of an audit. It is the most expensive skill in the collection; spend it on
decisions that are expensive to reverse.

`doubt` is the cheap half of that idea. It takes a set of claims that already exists — findings, a
plan, an analysis, a reviewer's objection — and rules on each one with two seats that never see the
reasoning behind them: one cold, one an agent outside the process. Its verdicts separate a claim
that is wrong from one that is true only in a narrower case, and both from one that is true and
still not worth acting on, so a seat that wants a trivial finding dropped never has to argue it is
false. Upholding the claim set is a normal outcome. Two agents rather than nine is the point: it is
affordable enough to fire before you contradict a reviewer, before a comment is published, or once
before fixes start.

| Skill | Description |
| ----- | ----------- |
| [changes-review](./review/skills/changes-review/) | Parallel cold reviewers that hunt bugs and requirement gaps, verify them, and optionally publish as a comment or a full review — finds, never fixes |
| [code-cleanup](./review/skills/code-cleanup/) | Prune comments aggressively, apply project conventions, simplify correct code |
| [consilium](./review/skills/consilium/) | Approach board — generate candidate approaches, attack them comparatively, recommend one |
| [doubt](./review/skills/doubt/) | Verify a set of claims with two seats blind to the reasoning behind them — one verdict each |
| [pr-review](./review/skills/pr-review/) | Review someone else's PR, or verify and answer the feedback on yours — replies and resolves |
| [code-to-spec](./review/skills/code-to-spec/) | Extract a behavioral spec from a codebase (1 file up to 500+ files) |

`code-to-spec` is the collection's only Claude Code-only skill. It dispatches six
plugin-namespaced subagents and keys its intermediate files on Claude's session id, so there is
nothing to port until that changes.

### Audit

CI, script, security, skill, workspace, tsconfig, Three.js, React, and test-suite auditing skills.
Every one of them finds and reports; none of them edits. `react-audit` and `three-audit` double as
stack lenses for `changes-review`.

| Skill | Description |
| ----- | ----------- |
| [ci-audit](./audit/skills/ci-audit/) | Audit GitHub Actions for wall clock, spend, and whether the gating actually gates |
| [scripts-audit](./audit/skills/scripts-audit/) | Analyze package.json scripts for naming, composition, and consistency |
| [security-audit](./audit/skills/security-audit/) | Find supply-chain gaps in Actions, release config, repo settings, and package manager — read-only |
| [skill-audit](./audit/skills/skill-audit/) | Gate a skill change on discovery, instructions, context cost, portability, and safety |
| [three-audit](./audit/skills/three-audit/) | Audit Three.js / React Three Fiber code for perf and best-practice issues |
| [react-audit](./audit/skills/react-audit/) | Audit React code for effect misuse, memoization, state architecture, and conventions |
| [tests-audit](./audit/skills/tests-audit/) | Audit a test suite and report keep/tighten/rewrite/delete per test |
| [tsconfig-audit](./audit/skills/tsconfig-audit/) | Audit tsconfig.json against TypeScript 7 and report what to drop, add, and keep |
| [workspace-audit](./audit/skills/workspace-audit/) | Analyze pnpm workspace and monorepo setup |

### Maintain

Agent instruction setup and drift check, label sync, lint migration, editor config sync, repo security hardening, and stale process cleanup.

| Skill | Description |
| ----- | ----------- |
| [agent-config](./maintain/skills/agent-config/) | Init a repo's agent instruction layer and check it for drift |
| [labels-sync](./maintain/skills/labels-sync/) | Check, apply, or export GitHub repository labels as reusable JSON |
| [editor-config](./maintain/skills/editor-config/) | Init or merge `.zed` / `.vscode` editor configs from a canonical set |
| [lint-sync](./maintain/skills/lint-sync/) | Migrate ESLint and Prettier to Biome or Oxc, or modernize an existing config |
| [repo-hardening](./maintain/skills/repo-hardening/) | Apply a GitHub security baseline: rulesets, Actions defaults, immutable releases, environments |
| [stale-process-cleanup](./maintain/skills/stale-process-cleanup/) | Find and reap orphaned dev servers, LSP, and MCP processes |

### Ship

Release workflows for npm packages.

| Skill | Description |
| ----- | ----------- |
| [npm-release](./ship/skills/npm-release/) | Guide npm/pnpm package release workflow |

### Assist

Explanations, design discussion, external opinions, handoffs, and plain restatement.

| Skill | Description |
| ----- | ----------- |
| [explain](./assist/skills/explain/) | Explain how something works by tracing the mechanism, not describing it |
| [discuss](./assist/skills/discuss/) | Talk a design through — investigate, take a position, push back; never writes |
| [handoff](./assist/skills/handoff/) | Compact the session into a handoff — inline text or per-project doc file |
| [outsider](./assist/skills/outsider/) | Quick opinion or review from an agent CLI outside this session |
| [bro](./assist/skills/bro/) | Say the last message again, straight — shorter, plainer, decision last |

`outsider` shells out to whichever agent CLI is installed and is *not* the one running it — Codex
from Claude Code, Claude from Codex, and so on. It ships everywhere because the host is excluded at
selection time rather than by leaving a host out of `compatibility`.

### Write

Markdown, README, and repository documentation writing.

| Skill | Description |
| ----- | ----------- |
| [markdown-writing](./write/skills/markdown-writing/) | Write READMEs, docs, PRs, and issues that lead with the point — GitHub alerts, structure, README skeleton |

### Obsidian

Working document management in an Obsidian vault.

| Skill | Description |
| ----- | ----------- |
| [working-docs](./obsidian/skills/working-docs/) | Organize working documents in Obsidian with two-tier system |

### Workflow

End-to-end workflows that orchestrate multiple skills into a single command.

| Skill | Description |
| ----- | ----------- |
| [solve-issue](./workflow/skills/solve-issue/) | Full issue workflow: analyze, plan, implement, verify, audit tests, review, ship via `issue-flow`, then answer the PR's automated reviewers |

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
