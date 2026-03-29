# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

## Canonical Repo Instructions

`CLAUDE.md` is the canonical repo instructions file. The repo root also contains an `AGENTS.md`
symlink pointing to this file so Codex and other agents read the same instructions.

Edit `CLAUDE.md` directly. Do not replace the `AGENTS.md` symlink with a copied file.

## Repository Structure

Skills are organized into plugin groups. Each group has a `.claude-plugin/plugin.json` for auto-discovery and contains related skills:

```
<group>/
├── .claude-plugin/
│   └── plugin.json       # Plugin metadata — "skills": "./" enables auto-discovery
├── <skill-name>/
│   ├── SKILL.md          # Required — frontmatter + instructions
│   ├── scripts/          # Optional — executable code (bash, python, js)
│   ├── references/       # Optional — additional docs loaded on demand
│   └── assets/           # Optional — templates, images, data files
└── ...
```

Codex packaging is layered on top of these source groups using wrapper plugins and repo-local
skill symlinks:

```
.agents/
├── plugins/
│   └── marketplace.json  # Repo-local Codex marketplace
└── skills/
    └── <skill-name> -> ../../<group>/<skill-name>

plugins/
└── <plugin-name>/
    ├── .codex-plugin/
    │   └── plugin.json   # Codex wrapper plugin manifest
    └── skills/
        └── <skill-name> -> ../../../<group>/<skill-name>
```

**Plugin groups:**
- `review/` — Code review, cleanup, and quality improvement (5 skills)
- `audit/` — CI, lint, script, skill, and workspace auditing (5 skills)
- `workflow/` — Git, GitHub, release, and development workflows (12 skills)
- `obsidian/` — Obsidian vault organization and working document management (1 skill)
- `tools/` — Skills for working with specific external tools and CLIs (1 skill)

Wrapper plugin names and display names for Codex:
- `plugins/edloidas-review/` → `edloidas-review` / `Edloidas Review`
- `plugins/edloidas-audit/` → `edloidas-audit` / `Edloidas Audit`
- `plugins/edloidas-workflow/` → `edloidas-workflow` / `Edloidas Workflow`
- `plugins/edloidas-obsidian/` → `edloidas-obsidian` / `Edloidas Obsidian`
- `plugins/edloidas-tools/` → `edloidas-tools` / `Edloidas Tools`

The Codex wrapper layer is driven from `scripts/codex/catalog.json`. After changing the Codex-exposed
skill set or plugin metadata, run:

```bash
./scripts/validate-codex.sh
./scripts/codex-packaging.sh sync-repo
```

Treat `.agents/plugins/marketplace.json`, `plugins/<plugin-name>/.codex-plugin/plugin.json`,
`.agents/skills/`, and `plugins/<plugin-name>/skills/` as generated outputs. Update the source
skills and `scripts/codex/catalog.json`, then regenerate the wrapper layer instead of editing those files
by hand.

## How Skills Load (Progressive Disclosure)

Skills use progressive disclosure to manage context efficiently:

1. **Discovery** — Only `name` and `description` are read (~100 tokens). Write descriptions that clearly signal when the skill applies.
2. **Activation** — Full SKILL.md body is loaded (<5000 tokens recommended). Keep instructions concise.
3. **Execution** — `references/` and `assets/` files are loaded on demand. Put detailed material there, not in the body.

## Skill Naming

- Directory name must match the `name` frontmatter field exactly
- Lowercase letters, numbers, and hyphens only (`a-z`, `0-9`, `-`)
- No leading/trailing hyphens, no consecutive hyphens (`--`)
- Max 64 characters

Valid: `pdf-processing`, `data-analysis`, `code-review`
Invalid: `PDF-Processing` (uppercase), `-pdf` (leading hyphen), `pdf--processing` (consecutive hyphens)

## SKILL.md Conventions

### Frontmatter (YAML)

Required fields:

| Field         | Constraint                                           |
| ------------- | ---------------------------------------------------- |
| `name`        | 1–64 chars, matches directory name                   |
| `description` | 1–1024 chars, describes what the skill does and when |

Optional fields:

| Field           | Constraint                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `license`       | License name or reference to a bundled LICENSE file                                                                   |
| `compatibility` | 1–500 chars; target agent and/or environment needs (see Multi-Agent Convention)                                       |
| `metadata`      | Key-value mapping; use reasonably unique key names to prevent conflicts                                               |
| `arguments`     | Short space-separated parameter names for autocomplete tokens. Each word becomes a `[word]` token in Claude Code's autocomplete. Match the `argument-hint` pattern without brackets (e.g. `"command branch"`, `"mode"`, `"files --dry-run"`). **Avoid regex metacharacters** (`[`, `]`, `|`, `<`, `>`, etc.) — Claude Code parses this field as a regex and will throw `SyntaxError: Invalid regular expression`. |
| `allowed-tools` | **Experimental.** Space-delimited list of pre-approved tools (e.g. `Bash(git:*) Read`)                                |

Claude Code extension fields (ignored by other agents, safe to use in any skill):

| Field                      | Constraint                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `argument-hint`            | Hint shown during autocomplete to indicate expected arguments (e.g. `[issue-number]`, `[filename] [format]`)        |
| `disable-model-invocation` | `true` prevents Claude from auto-loading the skill; invoke manually with `/skill-name`. Default: `false`            |
| `user-invocable`           | `false` hides from the `/` menu; Claude can still load it when relevant. Default: `true`                            |
| `model`                    | Model to use when skill is active (e.g. `claude-sonnet-4-5`)                                                        |
| `context`                  | `fork` runs the skill in a forked subagent context                                                                  |
| `agent`                    | Subagent type when `context: fork` (e.g. `Explore`, `Plan`, `general-purpose`, or a custom `.claude/agents/` agent) |
| `hooks`                    | Hooks scoped to skill lifecycle. See [Claude Code hooks docs](https://code.claude.com/docs/en/hooks)                |

String substitutions available in skill body: `$ARGUMENTS`, `$ARGUMENTS[N]` / `$N`, `${CLAUDE_SESSION_ID}`.
Dynamic context injection: `` !`command` `` runs a shell command and inserts its output before Claude sees the skill content.

Example frontmatter:

```yaml
---
name: pdf-processing
description: >
  Converts PDF files to text and extracts metadata.
  Use when the user asks to parse, read, or analyze PDF documents.
license: MIT
compatibility: Requires poppler-utils (pdftotext) installed on the system
allowed-tools: Bash(pdftotext:*) Read
user-invocable: true
model: claude-sonnet-4-5
metadata:
  author: edloidas
---
```

### AskUserQuestion Conventions

Skills using `AskUserQuestion` must follow these rules:

1. First option is recommended — add `(Recommended)` suffix to its label
2. Every option has a description explaining the choice
3. Order by relevance — recommended first, alternatives next, skip/none last
4. Maximum 4 options — "Other" is added automatically by Claude Code
5. Headers ≤12 characters, labels 1-5 words

### Multi-Agent Convention

Skills for different agents (Claude Code, Codex, etc.) live in the same group directories — no nesting by agent. Agent compatibility is declared via the `compatibility` frontmatter field.

**Agent-specific skill:**

```yaml
compatibility: Claude Code
```

**Multi-agent skill:**

```yaml
compatibility: Claude Code, Codex
```

**Universal skill:** Omit `compatibility` entirely — the skill works with any agent.

The README "Available Skills" tables include an **Agent** column for quick scanning.

### Codex Metadata

Skills exposed to Codex should include `agents/openai.yaml` with:

- `interface.display_name`
- `interface.short_description`
- optional `interface.default_prompt`
- `policy.allow_implicit_invocation`

Use `allow_implicit_invocation: false` for destructive or environment-specific skills that should
only run when explicitly invoked.

### Writing Good Descriptions

The `description` determines when an agent activates the skill. Be specific and actionable — include what the skill does, what inputs it handles, and keywords that would appear in a matching user request.

- Poor: `"Helps with PDFs."`
- Good: `"Converts PDF files to text and extracts metadata. Use when the user asks to parse, read, or analyze PDF documents."`

### Body (Markdown)

- Keep under 500 lines / ~5000 tokens
- Include step-by-step instructions, examples, and edge cases
- Move detailed reference material to `references/` files
- Use relative paths from the skill root when referencing files (e.g. `references/api-guide.md`)
- Keep references one directory level deep; avoid nested reference chains
- Keep individual reference files focused — smaller files mean less context usage

### Scripts

- Must be self-contained or clearly document dependencies
- Include helpful error messages
- Handle edge cases gracefully

## Creating a New Skill

1. Choose the appropriate group directory (`review/`, `audit/`, `workflow/`, `obsidian/`, or `tools/`)
2. Create a subdirectory: `mkdir <group>/<skill-name>`
3. Create `<group>/<skill-name>/SKILL.md` with required frontmatter and instructions
4. Add `scripts/`, `references/`, or `assets/` directories as needed
5. Update the appropriate "Available Skills" table in `README.md`
6. Validate via `skill-audit` skill if available

## Plugin Manifests (`.claude-plugin/`)

`marketplace.json` and `plugin.json` have **different schemas** — do not mix their fields.

- **`marketplace.json`** — marketplace registry entry. Plugin objects support: `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`. **No `skills` field.** Adding `skills` here causes validation error: `plugins.0.skills: Invalid input`.
- **`plugin.json`** — plugin manifest. Declares `skills` as a path (e.g. `"skills": "./"`) for skill directory discovery.

Skills are discovered automatically from the path declared in `plugin.json`. No per-skill registration is needed in either file.

## Codex Wrapper Plugins

Do not add `.codex-plugin/plugin.json` directly to the source group directories (`review/`,
`audit/`, `workflow/`, `obsidian/`, `tools/`).

Use wrapper plugins under `plugins/<plugin-name>/` instead:

- Source groups remain the canonical skill source for all agents.
- Wrapper plugins expose only the Codex-vetted subset of skills.
- `plugins/<plugin-name>/skills/` should contain symlinks to the real skill directories.
- `.agents/skills/` should also contain only Codex-vetted skill symlinks.

Do not rely on `compatibility` metadata alone to hide unsupported skills from Codex discovery.
Only add `Codex` to a skill's `compatibility` frontmatter after reviewing that the instructions are
actually Codex-safe. In this repo, Codex-compatible skills must also be exposed through
`scripts/codex/catalog.json`.

When adding a new skill, or when upgrading an existing skill to support Codex, make sure the
Codex packaging layer is updated in the same change:

- Add or update the skill's `compatibility` frontmatter to reflect actual Codex support.
- Add `agents/openai.yaml` if the skill should be exposed in Codex.
- Add the skill symlink in `.agents/skills/` if it is part of the repo-local Codex skill set.
- Add the skill symlink in the appropriate `plugins/<plugin-name>/skills/` wrapper plugin if it should
  be installable through the repo marketplace.
- Ensure the wrapper plugin manifest and `.agents/plugins/marketplace.json` still reflect the
  intended Codex plugin set.
- Update `scripts/codex/catalog.json`, run `./scripts/validate-codex.sh`, and run `./scripts/codex-packaging.sh sync-repo` so the
  generated wrapper layer stays in sync.
- Update `README.md` if the exposed Codex skill set or plugin group contents changed.

A skill is not considered fully integrated until both the source skill and the Codex wrapper layer
are kept in sync.

## Bundling Agents with a Plugin

Claude Code agents (`.claude/agents/`) can be distributed alongside skills as part of a plugin. This is a **Claude Code-specific feature** — the Agent Skills spec (agentskills.io) has no concept of agent distribution.

### Directory layout

Place agent files in an `agents/` directory at the plugin group root:

```
<group>/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── my-agent.md       # Auto-discovered by Claude Code
│   └── other-agent.md
└── <skill-name>/
    └── SKILL.md
```

`agents/` at the plugin root is **auto-discovered** — no declaration needed in `plugin.json`. The `"agents"` field in `plugin.json` is additive (supplements auto-discovery for non-standard paths).

### Agent file format

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

### Priority order

When multiple locations define an agent with the same `name`, higher-priority locations win silently:

1. `.claude/agents/` — project-level (highest)
2. `~/.claude/agents/` — global user
3. Plugin's `agents/` — distributed (lowest)

### Naming and invocation

- Agents appear in the UI as `<plugin-name>:<agent-name>` (e.g. `review:review-build`)
- `subagent_type` in code uses the plain `name` without namespace (e.g. `subagent_type: "review-build"`)
- Agent `name` in frontmatter must match the filename (without `.md`)

## Avoid

- Putting all content in SKILL.md body — move reference material to `references/`
- Writing vague descriptions that don't help the agent decide when to activate the skill
- Creating scripts with undocumented external dependencies
- Using absolute paths or paths outside the skill directory

## Specs and Plans

Specs and plans are stored in `docs/superpowers/` (gitignored). Delete the spec and plan files for a feature once it is fully implemented.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format: `<type>: <description>`

Common types: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `style:`, `ci:`

**One commit per feature.** When adding a new skill or feature, do all work first (writing, reviewing, fixing) and produce a single clean commit at the end. Do not create intermediate commits during the process — squash everything into one before committing.

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
