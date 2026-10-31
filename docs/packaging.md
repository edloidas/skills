# Packaging

Read this when changing which hosts a skill ships to, the Codex plugin, the generated trees,
the plugin manifests, or the bundled agents. Which hosts a skill declares, and what makes a skill
safe to declare them, is in [writing-skills.md](writing-skills.md#portability).

## Why Skills Are Real Directories

`skills/<skill-name>/` is the one canonical location for a skill, and it must be a real
directory — never a symlink. Two independent constraints force this:

1. Claude Code's plugin loader looks inside the plugin's `skills/` directory, not the
   plugin root. A skill outside `skills/` is invisible to the plugin even though
   `SKILL.md`, `plugin.json`, and the marketplace entry all exist.
2. Agent skill CLIs (notably `npx skills`) discover skills with
   `readdir(withFileTypes)` + `entry.isDirectory()`, which is **false** for a symlink. A
   symlinked skill directory is invisible to them. They also hard-skip directories named
   `node_modules`, `.git`, `dist`, `build`, and `__pycache__`, so no directory on a skill's
   path may carry one of those names.

`validate-skills.sh` enforces both ([validation.md](validation.md)).

Internal, repo-only skills stay out of the published set by living under `tools/` with a
symlink into `.claude/skills/` — Claude Code follows the symlink, while `npx skills`
skips it. `tools/skills-release` and `tools/skill-eval` are the current examples.

## Generated Trees

Distribution trees are generated symlinks into that canonical location. Claude Code, Codex,
OpenCode, and pi all resolve symlinks when they read a tree in place, so only the canonical
directory has to be real:

```
.codex-plugin/
└── plugin.json           # Codex plugin manifest; lists the Codex skills by path
.agents/
├── plugins/
│   └── marketplace.json  # Codex marketplace; its one plugin's path is ./
└── skills/
    └── <skill-name> -> ../../skills/<skill-name>
```

`sync-repo` generates one symlink tree per host, all pointing into the canonical
`skills/<name>` directories:

| Tree | Read by | Contents |
| ---- | ------- | -------- |
| `.agents/skills/` | Codex, OpenCode, pi | Codex-vetted set (from `scripts/codex/catalog.json`) |
| `.opencode/skills/` | OpenCode | Every skill declaring `OpenCode` |
| `.pi/skills/` | pi | Every skill declaring `Pi` |

Treat `.agents/plugins/marketplace.json`, `.codex-plugin/plugin.json`, `.agents/skills/`,
`.opencode/skills/`, and `.pi/skills/` as generated outputs. Update the source skills, their `compatibility` frontmatter, and
`scripts/codex/catalog.json`, then regenerate:

```bash
./scripts/validate-codex.sh
./scripts/skills-packaging.sh sync-repo
```

To install a host's set globally rather than repo-locally:

```bash
./scripts/skills-packaging.sh install-host opencode   # -> ~/.config/opencode/skills
./scripts/skills-packaging.sh install-host pi         # -> ~/.pi/agent/skills
./scripts/skills-packaging.sh install-host codex      # -> ~/.agents/skills
```

`install-host` prunes only links that point into this repo, so unrelated skills sharing the
destination directory are left alone.

## Codex Plugin

The Codex plugin, `edloidas` / `Edloidas` in the Codex marketplace `edloidas-skills`, is rooted at
the repo root, like the Claude Code plugin. Both are driven from `scripts/codex/catalog.json`,
which holds exactly one plugin.

Codex copies an installed plugin into its cache and drops every symlink on the way, so the plugin
cannot be a tree of symlinked skills — that installs empty. Instead:

- `.codex-plugin/plugin.json` sits at the repo root beside `.claude-plugin/`, and its `skills`
  array names each catalog skill as `./skills/<name>/`. Codex loads only the listed directories,
  which is what keeps a Claude Code-only skill such as `code-to-spec` out.
- The marketplace entry in `.agents/plugins/marketplace.json` has `path: "./"`.
- The install copies the whole repo into `$CODEX_HOME/plugins/cache/`; the skills arrive as the
  real directories.

`.agents/skills/` is separate: the Codex-vetted set as symlinks, read in place when this
repository is open in Codex, OpenCode, or pi. `./scripts/skills-packaging.sh install-host codex`
links the same set into `~/.agents/skills` for use outside a plugin.

When adding a new skill, or when upgrading an existing skill to support Codex, update the
Codex packaging layer in the same change:

- Add or update the skill's `compatibility` frontmatter to reflect actual Codex support.
- Add `agents/openai.yaml` (below) if the skill should be exposed in Codex.
- Add the skill to `scripts/codex/catalog.json`, run `./scripts/validate-codex.sh`, and run
  `./scripts/skills-packaging.sh sync-repo` so `.agents/skills/`, `.codex-plugin/plugin.json`,
  and `.agents/plugins/marketplace.json` stay in sync.
- Update `README.md` if the exposed Codex skill set changed.

A skill is not considered fully integrated until both the source skill and the Codex plugin layer
are kept in sync.

### Codex Metadata

Skills exposed to Codex include `agents/openai.yaml` with:

- `interface.display_name`
- `interface.short_description`
- optional `interface.default_prompt`
- `policy.allow_implicit_invocation`

`allow_implicit_invocation` follows the skill's tier ([writing-skills.md](writing-skills.md#tiers)),
and `scripts/validate-codex.sh` fails on a mismatch:

| `metadata.tier` | `allow_implicit_invocation` |
| --------------- | --------------------------- |
| `auto` | `true` |
| `routed` | `false` |
| `manual` | `false` |

The flag is Codex's only discovery switch, so a skill that should not start on its own changes
tier rather than overriding the flag.

## Claude Code Plugin Manifests

`.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` have **different schemas** —
do not mix their fields.

- **`marketplace.json`** — marketplace registry entry. Plugin objects support: `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`. **No `skills` field.** Adding `skills` here causes validation error: `plugins.0.skills: Invalid input`.
- **`plugin.json`** — plugin manifest. Do not declare a `skills` field — it is no longer supported.

Skills are discovered automatically from the plugin root's `skills/` directory. No per-skill
registration is needed in either file.

## Bundled Agents

Claude Code agents can be distributed alongside skills as part of a plugin. This is a
**Claude Code-specific feature** — the Agent Skills spec (agentskills.io) has no concept of agent
distribution, which is why a portable skill keeps its dispatched prompt in `references/` instead
([writing-skills.md](writing-skills.md#subagent-dispatch-is-intent)).

Agent files live in `agents/` at the plugin root, which here is the repo root:

```
.claude-plugin/
└── plugin.json
agents/
├── spec-scout.md         # Auto-discovered by Claude Code
└── spec-auditor.md
skills/
└── <skill-name>/
    └── SKILL.md
```

`agents/` at the plugin root is **auto-discovered** — no declaration needed in `plugin.json`. The `"agents"` field in `plugin.json` is additive (supplements auto-discovery for non-standard paths).

Agent files are Markdown with YAML frontmatter:

```markdown
---
name: my-agent
description: What this agent does and when to invoke it
model: sonnet
tools: Bash, Read, Glob, Grep
---

Agent system prompt here.
```

When multiple locations define an agent with the same `name`, higher-priority locations win silently:

1. `.claude/agents/` — project-level (highest)
2. `~/.claude/agents/` — global user
3. Plugin's `agents/` — distributed (lowest)

Naming and invocation:

- Agents appear in the UI as `<plugin-name>:<agent-name>` (e.g. `edloidas:spec-analyzer`)
- `subagent_type` for plugin-distributed agents requires the namespaced form (e.g. `subagent_type: "edloidas:spec-analyzer"`)
- `subagent_type` for built-in agents uses the plain name (e.g. `subagent_type: "general-purpose"`)
- Agent `name` in frontmatter must match the filename (without `.md`)
