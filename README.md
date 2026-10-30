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

They cover issue planning and the full issue lifecycle, building and committing, adversarial
review, auditing, repository maintenance, npm releases, explanations and outside opinions,
Markdown writing, Obsidian working docs, and end-to-end workflows. The full list is in
[Available Skills](#available-skills).

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

Each host also has a native install, which buys namespaced skill names and updates through the
host itself:

| Agent | Install | What you get |
| ----- | ------- | ------------ |
| Claude Code | `/plugin marketplace add edloidas/skills` | The `edloidas` plugin, every skill |
| Codex | `codex plugin marketplace add edloidas/skills` | The `edloidas` wrapper plugin |
| pi | `pi install git:github.com/edloidas/skills` | Every portable skill |
| OpenCode | `./scripts/skills-packaging.sh install-host opencode` | Every portable skill |

Every skill ships to all four agents except one. `code-to-spec` drives fleets of
plugin-namespaced subagents and keys its temp files on Claude's session id, so it is Claude Code
only. See [How skills reach each agent](#how-skills-reach-each-agent).

### Claude Code

The whole collection is one plugin, `edloidas`, in the marketplace of the same name. Its skills
are namespaced `edloidas:<skill>`. Add the marketplace, then install the plugin:

```
/plugin marketplace add edloidas/skills
/plugin install edloidas@edloidas
```

On Claude Code 2.1.275 or later the two steps are one:
`/plugin install edloidas --marketplace edloidas/skills`.

| Scope | Command | Use case |
| ----- | ------- | -------- |
| User (default) | `/plugin install edloidas@edloidas` | Personal — all projects |
| Project | `/plugin install edloidas@edloidas --scope project` | Team — shared via Git |
| Local | `/plugin install edloidas@edloidas --scope local` | Project — gitignored |

To hand a team the plugin through Git instead, commit the marketplace and the plugin to
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "edloidas": { "source": { "source": "github", "repo": "edloidas/skills" } }
  },
  "enabledPlugins": {
    "edloidas@edloidas": true
  }
}
```

Up to 5.x the collection shipped as ten group plugins (`plan@edloidas`, `review@edloidas`, and so
on). Those ids no longer exist: uninstall them and install `edloidas@edloidas` once.

To load the plugin for a single session without installing it:

```bash
git clone https://github.com/edloidas/skills.git
claude --plugin-dir ./skills
```

### Codex

Add the marketplace from GitHub — no `--ref` flag needed:

```bash
codex plugin marketplace add edloidas/skills
```

This installs and enables the one wrapper plugin, `Edloidas`, which carries every Codex-ready
skill. Codex clones the whole repository, so `git pull` updates flow through. Restart Codex if new
skills do not appear.

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
| Claude Code | `/plugin` | The `edloidas` marketplace and the `edloidas` plugin |
| Codex | `codex plugin list` | `edloidas@edloidas-skills`, `installed, enabled` |
| pi | `pi list` | The `edloidas/skills` package |
| OpenCode | `opencode debug skill` | Your skills in the JSON listing |
| Any | `npx skills ls` | Installed skills per agent |

OpenCode loads its skill list once at startup and does not hot-reload it. Restart OpenCode before
trusting `opencode debug skill` after an install.

## Uninstall

| Agent | Command |
| ----- | ------- |
| Claude Code | `/plugin uninstall edloidas@edloidas`, then `/plugin marketplace remove edloidas` |
| Codex | `codex plugin marketplace remove edloidas-skills` |
| pi | `pi remove git:github.com/edloidas/skills` |
| OpenCode | `rm ~/.config/opencode/skills/<skill>`, or remove the whole directory |
| npx skills | `npx skills remove --all` |

`install-host` writes only symlinks, so removing them leaves nothing behind.

## How skills reach each agent

Every skill lives in exactly one real directory, `skills/<name>/`. Everything else is a
generated symlink tree pointing at it. Claude Code, Codex, OpenCode, and pi all resolve symlinks;
the `skills` CLI does not, which is why the canonical location must be a real directory.

| Agent | Discovery path | Installed by |
| ----- | -------------- | ------------ |
| Claude Code | `skills/` via the root `.claude-plugin/plugin.json` | Plugin marketplace |
| Codex | `.agents/skills/`, `plugins/edloidas/skills/` | Plugin marketplace, or `install-host codex` |
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

Every skill runs on Claude Code, Codex, OpenCode, and pi, except `code-to-spec`, which is Claude Code
only. Topic rows group the table for reading; they are not separate plugins.

**Tier** says how a skill is reached: `auto` skills start on their own when your request matches,
`routed` ones run by `/name` or when another skill calls them, and `manual` ones only by `/name`.

| Skill | Agents | Tier | Description |
| ----- | ------ | ---- | ----------- |
| **Plan** | | | |
| [issue-writer](./skills/issue-writer/) | All four | routed | Draft and update well-structured GitHub issues |
| [issue-analyze](./skills/issue-analyze/) | All four | routed | Analyze issue scope against its parent, siblings, and dependencies, and produce an implementation task list |
| [issue-flow](./skills/issue-flow/) | All four | routed | Full issue lifecycle: pick, create, branch, commit, push, PR, merge |
| [next-issue](./skills/next-issue/) | All four | routed | Recommend the next issues to work on, with type, size, fit, and what blocks the rest |
| **Build** | | | |
| [resolve-conflicts](./skills/resolve-conflicts/) | All four | auto | Semi-automatic merge and rebase conflict resolution |
| [commit-summary](./skills/commit-summary/) | All four | routed | Derive a commit message body from the code behind the change |
| [live-probe](./skills/live-probe/) | All four | routed | Settle a claim about observable behavior by running it, or write the project's runbook for doing so |
| **Review** | | | |
| [changes-review](./skills/changes-review/) | All four | routed | Parallel cold reviewers that hunt bugs and requirement gaps, verify them, and optionally publish as a comment or a full review — finds, never fixes |
| [code-cleanup](./skills/code-cleanup/) | All four | routed | Prune comments aggressively, apply project conventions, simplify correct code |
| [consilium](./skills/consilium/) | All four | routed | Approach board — generate candidate approaches, attack them comparatively, recommend one |
| [doubt](./skills/doubt/) | All four | routed | Verify a set of claims with two seats blind to the reasoning behind them — one verdict each |
| [pr-review](./skills/pr-review/) | All four | routed | Review someone else's PR, or land it with `--land` — approve and merge, folding small fixes first; or verify and answer the feedback on yours — replies and resolves |
| [code-to-spec](./skills/code-to-spec/) | Claude Code | routed | Extract a behavioral spec from a codebase (1 file up to 500+ files) |
| **Audit** | | | |
| [ci-audit](./skills/ci-audit/) | All four | routed | Audit GitHub Actions for wall clock, spend, and whether the gating actually gates |
| [package-audit](./skills/package-audit/) | All four | routed | Audit package.json scripts against each package's role and, in a pnpm workspace, catalogs, protocol, overrides, and hoisting |
| [security-audit](./skills/security-audit/) | All four | routed | Find supply-chain gaps in Actions, release config, repo settings, and package manager — read-only |
| [skill-audit](./skills/skill-audit/) | All four | auto | Gate a skill change on discovery, instructions, context cost, portability, and safety |
| [three-audit](./skills/three-audit/) | All four | routed | Audit Three.js / React Three Fiber code for perf and best-practice issues |
| [react-audit](./skills/react-audit/) | All four | routed | Audit React code for effect misuse, memoization, state architecture, and conventions |
| [tests-audit](./skills/tests-audit/) | All four | routed | Audit a test suite and report keep/tighten/rewrite/delete per test |
| [tsconfig-audit](./skills/tsconfig-audit/) | All four | routed | Audit tsconfig.json against TypeScript 7 and report what to drop, add, and keep |
| **Maintain** | | | |
| [labels-sync](./skills/labels-sync/) | All four | manual | Check, apply, or export GitHub repository labels as reusable JSON |
| [editor-config](./skills/editor-config/) | All four | manual | Init or merge `.zed` / `.vscode` editor configs from a canonical set |
| [repo-hardening](./skills/repo-hardening/) | All four | manual | Apply a GitHub security baseline: rulesets, Actions defaults, immutable releases, environments |
| [session-cleanup](./skills/session-cleanup/) | All four | manual | Memory report, then clean up leftover processes, worktrees, merged branches, and session files |
| **Ship** | | | |
| [npm-release](./skills/npm-release/) | All four | auto | Guide npm/pnpm package release workflow |
| **Assist** | | | |
| [explain](./skills/explain/) | All four | auto | Explain how something works by tracing the mechanism, not describing it |
| [handoff](./skills/handoff/) | All four | auto | Compact the session into a handoff — inline text or per-project doc file |
| [outsider](./skills/outsider/) | All four | auto | Quick opinion or review from an agent CLI outside this session |
| [sharpen](./skills/sharpen/) | All four | routed | Rewrite a prompt or task statement to ask for what a top practitioner would do — the four answers, the rewrite, and the choices left to you |
| [bro](./skills/bro/) | All four | manual | Say the last message again, straight — shorter, plainer, decision last |
| **Write** | | | |
| [markdown-writing](./skills/markdown-writing/) | All four | auto | Write READMEs, docs, PRs, and issues that lead with the point — GitHub alerts, structure, README skeleton |
| **Obsidian** | | | |
| [working-docs](./skills/working-docs/) | All four | routed | Organize working documents in Obsidian with two-tier system |
| **Workflow** | | | |
| [do](./skills/do/) | All four | auto | Take any engineering task end to end: route it to the skill that owns it, to a playbook for a bug, a slowdown, an investigation, a review-and-fix, or a small change, or to `orchestrate` for a large goal; report with the evidence pasted |
| [solve-issue](./skills/solve-issue/) | All four | routed | Full issue workflow: analyze, plan, implement, verify, audit tests, review, ship via `issue-flow`, then answer the PR's automated reviewers |
| [orchestrate](./skills/orchestrate/) | All four | routed | Coordinate a body of work from one session that never touches the code: issues, new issues, own PR fixes, reviews and decisions as units, each in its own worker (`solve-issue`, `pr-review`, `consilium`); goal and plan up front, run state on disk, every hand-back checked against GitHub, a plain summary per unit |
| [pr-triage](./skills/pr-triage/) | All four | routed | Whole review queue in one run: triage every pull request waiting on you, verify findings with blind judges, then approve, merge, fold small fixes, request changes, or deep-review by tier; lists your own PRs by state; scope to `current` repo, `assigned` or `created`; `recheck` picks up author updates |
| [issue-triage](./skills/issue-triage/) | All four | routed | Whole open issue backlog behind one plan: scripts fetch, resolve references, group related and similar issues and lint type and labels; the strongest model judges each theme and blind judges verify every close; then close with the right reason, fix type, labels, title and project status, ask owners, or file follow-ups, written and audited by an idempotent script. `metadata` relabels and moves without judging; `report` stops at the plan |

## How the skills fit together

`do` is the front door. It takes a task, decides once what it needs, and runs that: the skill that
owns the task, one of its own playbooks for work with no issue, the change directly when it is a
one-liner, or `orchestrate` when the goal splits into several units. `orchestrate` never touches
code — each unit runs in its own worker, and a unit with no issue runs `do` there. `solve-issue`
takes one GitHub issue end to end.

### Plan

`issue-flow` owns every git and GitHub write in the pipeline — creating the issue, branching, snapshots, commits, squashing, pushes, PRs, merges. Skills that
orchestrate the pipeline (`solve-issue`) delegate those actions to it instead of
reimplementing them, so the commit subject format and the squash rules live in one place.
`next-issue` owns choosing what to work on; it is not in the `/` menu and runs on its own
when you ask what is next.

### Review

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

`consilium` is not a review skill. It takes a problem or a decision, not a diff: up to four seats
generate candidate approaches — one of them the simplest thing that could work, one an agent outside
this process with none of the conversation's context — and two attack the set comparatively, then two
verification lenses rule on every objection, refuting only on evidence, before anything is ranked.
The current state is always a candidate, a hedged rule becomes an open question rather than a
candidate to rank, and an approach already on the table is withheld from the generators and enters as
one candidate among several. It reports a full ranking by default and a concise one on `short`. It is
the most expensive skill in the collection; spend it on decisions that are expensive to reverse.

`doubt` is the cheap half of that idea. It takes a set of claims that already exists — findings, a
plan, an analysis, a reviewer's objection — and rules on each one with two seats that never see the
reasoning behind them: one cold, one an agent outside the process. Its verdicts separate a claim
that is wrong from one that is true only in a narrower case, and both from one that is true and
still not worth acting on, so a seat that wants a trivial finding dropped never has to argue it is
false. Upholding the claim set is a normal outcome. Two agents rather than eight is the point: it is
affordable enough to fire before you contradict a reviewer, before a comment is published, once
before fixes start, or when an agent is about to make a call the user would normally make and the
user is not there. The report groups claims by what to do with them and ends on a short
recommendation of what to do next.

`code-to-spec` is the collection's only Claude Code-only skill. It dispatches six
plugin-namespaced subagents and keys its intermediate files on Claude's session id, so there is
nothing to port until that changes.

### Audit

Every audit skill finds and reports; none of them edits. `react-audit` and `three-audit` double as
stack lenses for `changes-review`.

### Assist

`outsider` shells out to whichever agent CLI is installed and is *not* the one running it — Codex
from Claude Code, Claude from Codex, and so on. It ships everywhere because the host is excluded at
selection time rather than by leaving a host out of `compatibility`.

## Skill Structure

```
.claude-plugin/
├── plugin.json               # The edloidas plugin (auto-discovers skills/ and agents/)
└── marketplace.json          # The edloidas marketplace, one entry pointing at the repo root
agents/                       # Subagents the plugin ships (code-to-spec's spec-* agents)
skills/
└── <skill-name>/             # Canonical location — a real directory, never a symlink
    ├── SKILL.md              # Required — frontmatter + instructions
    ├── agents/               # Optional — agent-specific configs (e.g. openai.yaml)
    ├── scripts/              # Optional — executable code
    ├── references/           # Optional — docs loaded on demand
    └── assets/               # Optional — templates, images, data files
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

[AGENTS.md](AGENTS.md) holds the repo rules and the validation contract, and links the
reference docs: [writing skills](docs/writing-skills.md) (frontmatter fields, naming rules,
portability), [packaging](docs/packaging.md) (per-host trees, Codex wrapper), and the rest in
`docs/`. In short: create `skills/<name>/SKILL.md` as a real
directory, declare `compatibility`, add `agents/openai.yaml` and a `scripts/codex/catalog.json`
entry if it targets Codex, add a row to the table above, then run `sync-repo` and the validators.

## License

[MIT](LICENSE)
