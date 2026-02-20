# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

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

**Plugin groups:**
- `review/` — Code review, cleanup, and quality improvement (5 skills)
- `audit/` — CI, lint, script, skill, and workspace auditing (5 skills)
- `workflow/` — Git, GitHub, release, and development workflows (6 skills)

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
| `arguments`     | Plain-text description of accepted arguments for `user-invocable` skills. **Avoid regex metacharacters** (`[`, `]`, `|`, `<`, `>`, etc.) — Claude Code parses this field as a regex and will throw `SyntaxError: Invalid regular expression` if the value contains unescaped special characters. Use descriptive text instead (e.g. `"all or space-separated skill names"`). |
| `allowed-tools` | **Experimental.** Space-delimited list of pre-approved tools (e.g. `Bash(git:*) Read`)                                |

Claude Code extension fields (ignored by other agents, safe to use in any skill):

| Field                      | Constraint                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `argument-hint`            | Autocomplete hint for expected arguments (e.g. `[issue-number]`, `[filename] [format]`)                             |
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

1. Choose the appropriate group directory (`review/`, `audit/`, or `workflow/`)
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

## Avoid

- Putting all content in SKILL.md body — move reference material to `references/`
- Writing vague descriptions that don't help the agent decide when to activate the skill
- Creating scripts with undocumented external dependencies
- Using absolute paths or paths outside the skill directory

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format: `<type>: <description>`

Common types: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `style:`, `ci:`

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
