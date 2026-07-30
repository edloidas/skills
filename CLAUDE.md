# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

**Never commit or push changes unless explicitly asked.** Never commit directly to the main branch unless explicitly asked.

**No AI footers:** Do not add "Drafted with AI assistance" or similar lines to issue or PR bodies.

## Canonical Repo Instructions

`CLAUDE.md` is the canonical repo instructions file. The repo root also contains an `AGENTS.md`
symlink pointing to this file so Codex and other agents read the same instructions.

Edit `CLAUDE.md` directly. Do not replace the `AGENTS.md` symlink with a copied file.

## Repository Structure

Skills are organized into plugin groups. Each group has a `.claude-plugin/plugin.json` for auto-discovery and contains related skills:

```
<group>/
├── .claude-plugin/
│   └── plugin.json               # Plugin metadata
└── skills/
    └── <skill-name>/             # Canonical skill location — a REAL directory
        ├── SKILL.md              # Required — frontmatter + instructions
        ├── scripts/              # Optional — executable code
        ├── references/           # Optional — docs loaded on demand
        └── assets/               # Optional — templates, images, data
```

**`<group>/skills/<skill-name>/` is the one canonical location for a skill, and it must be
a real directory — never a symlink.** Two independent constraints force this:

1. Claude Code's plugin loader looks inside the plugin's `skills/` directory, not the
   plugin root. A skill outside `<group>/skills/` is invisible to the plugin even though
   `SKILL.md`, `plugin.json`, and the marketplace entry all exist.
2. Agent skill CLIs (notably `npx skills`) discover skills with
   `readdir(withFileTypes)` + `entry.isDirectory()`, which is **false** for a symlink. A
   symlinked skill directory is invisible to them. They also hard-skip directories named
   `node_modules`, `.git`, `dist`, `build`, and `__pycache__` — which is why the `build/`
   group is only reachable through the `<group>/skills/` path that the marketplace
   manifest points at.

`.github/scripts/validate-skills.sh` enforces both: it rejects a symlinked skill directory
and rejects a leftover pre-4.0 `<group>/<skill-name>` path.

Distribution trees are generated symlinks into that canonical location. Claude Code, Codex,
OpenCode, and pi all resolve symlinks, so only the canonical directory has to be real:

```
.agents/
├── plugins/
│   └── marketplace.json  # Repo-local Codex marketplace
└── skills/
    └── <skill-name> -> ../../<group>/skills/<skill-name>

plugins/
└── <plugin-name>/
    ├── .codex-plugin/
    │   └── plugin.json   # Codex wrapper plugin manifest
    └── skills/
        └── <skill-name> -> ../../../<group>/skills/<skill-name>
```

Internal, repo-only skills stay out of the published set by living under `tools/` with a
symlink into `.claude/skills/` — Claude Code follows the symlink, while `npx skills`
skips it. `tools/skills-release` is the one current example.

**Plugin groups:**
- `plan/` — Issue drafting, analysis, triage, and full issue lifecycle (4 skills)
- `build/` — Git worktree management, conflict resolution, commit summaries, quick commits, and findings fixes (5 skills)
- `review/` — Code review, cleanup, test quality, critical review board, and quality improvement (7 skills)
- `audit/` — CI, script, security, skill, workspace, and Three.js auditing (6 skills)
- `maintain/` — Label sync, instruction file sync, permissions cleanup, lint migration, comment auditing, agent rule sync, editor config sync, stale process cleanup, and session retros (9 skills)
- `ship/` — Release workflows and deployment tools (2 skills)
- `assist/` — External opinion and assistance tools (5 skills)
- `obsidian/` — Obsidian vault organization and working document management (1 skill)
- `workflow/` — End-to-end workflows that orchestrate multiple skills (1 skill)

Wrapper plugin names and display names for Codex:
- `plugins/edloidas-plan/` → `edloidas-plan` / `Edloidas Plan`
- `plugins/edloidas-build/` → `edloidas-build` / `Edloidas Build`
- `plugins/edloidas-review/` → `edloidas-review` / `Edloidas Review`
- `plugins/edloidas-audit/` → `edloidas-audit` / `Edloidas Audit`
- `plugins/edloidas-maintain/` → `edloidas-maintain` / `Edloidas Maintain`
- `plugins/edloidas-ship/` → `edloidas-ship` / `Edloidas Ship`
- `plugins/edloidas-assist/` → `edloidas-assist` / `Edloidas Assist`
- `plugins/edloidas-obsidian/` → `edloidas-obsidian` / `Edloidas Obsidian`

The Codex wrapper layer is driven from `scripts/codex/catalog.json`. After changing the Codex-exposed
skill set or plugin metadata, run:

```bash
./scripts/validate-codex.sh
./scripts/skills-packaging.sh sync-repo
```

Treat `.agents/plugins/marketplace.json`, `plugins/<plugin-name>/.codex-plugin/plugin.json`,
`.agents/skills/`, `.opencode/skills/`, `.pi/skills/`, and `plugins/<plugin-name>/skills/` as
generated outputs. Update the source skills, their `compatibility` frontmatter, and
`scripts/codex/catalog.json`, then regenerate instead of editing those files by hand.

The generated Codex wrapper layer is symlink-based and should be treated as repo-local when this
repository is open in Codex. For user-scoped or cross-repo Codex usage, install skills via
`./scripts/skills-packaging.sh install-links --dest "$HOME/.agents/skills" ...` or direct installs
into `~/.codex/skills` rather than assuming the wrapper plugin cache will be portable.

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

| Field         | Constraint                                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------------------------------- |
| `name`        | 1–64 chars, matches directory name                                                                               |
| `description` | ≤1,024 chars; when paired with `when_to_use`, the combined discovery entry is capped at 1,536 chars and truncated |

Optional fields:

| Field           | Constraint                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `license`       | License name or reference to a bundled LICENSE file                                                                   |
| `compatibility` | 1–500 chars; target agent and/or environment needs (see Multi-Agent Convention)                                       |
| `metadata`      | Key-value mapping; use reasonably unique key names to prevent conflicts                                               |
| `when_to_use`   | Trigger phrases and scenarios for activation. Appended to `description` at discovery; combined cap 1,536 chars        |
| `arguments`     | Space-separated parameter names for autocomplete tokens. **Caution:** makes arguments mandatory for marketplace-installed plugin skills — users cannot submit with Enter unless they provide arguments. Only use for skills that genuinely cannot function without explicit input (e.g. an issue number that can't be derived from context). For optional arguments, use `argument-hint` only. See [Arguments Behavior](#arguments-behavior) below. |
| `allowed-tools` | **Experimental.** Pre-approved tools, as a space-separated string (`Bash(git:*) Read`) or a YAML list                  |

Claude Code extension fields (ignored by other agents, safe to use in any skill):

| Field                      | Constraint                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `argument-hint`            | Hint shown during autocomplete to indicate expected arguments (e.g. `[issue-number]`, `[filename] [format]`)        |
| `disable-model-invocation` | `true` prevents Claude from auto-loading the skill; invoke manually with `/skill-name`. Default: `false`            |
| `user-invocable`           | `false` hides from the `/` menu; Claude can still load it when relevant. Default: `true`                            |
| `model`                    | Model to use when skill is active (e.g. `claude-sonnet-4-5`)                                                        |
| `effort`                   | Override session effort while the skill is active: `low`, `medium`, `high`, `xhigh`, or `max`                       |
| `paths`                    | Glob string or YAML list that scopes auto-activation to matching file paths (e.g. `".github/workflows/**/*.yml"`)   |
| `shell`                    | `bash` (default) or `powershell`; gates the shell used for `` !`command` `` and ` ```! ` injection blocks            |
| `context`                  | `fork` runs the skill in a forked subagent context                                                                  |
| `agent`                    | Subagent type when `context: fork` (e.g. `Explore`, `Plan`, `general-purpose`, or a custom `.claude/agents/` agent) |
| `hooks`                    | Hooks scoped to skill lifecycle. See [Claude Code hooks docs](https://code.claude.com/docs/en/hooks)                |

String substitutions available in skill body: `$ARGUMENTS`, `$ARGUMENTS[N]` / `$N`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` (absolute path to the skill's `SKILL.md` directory — useful for invoking bundled scripts regardless of cwd).
Dynamic context injection: `` !`command` `` runs a shell command and inserts its output before Claude sees the skill content.

#### Claude-only vs Agent Skills spec

The Agent Skills [spec](https://agentskills.io/specification) defines a portable subset. The following fields and features are Claude Code extensions — they are silently ignored by the spec but **must not be relied on for skills exposed to Codex** via `scripts/codex/catalog.json`. Using them on a `compatibility: Claude Code, Codex` skill risks silent behavior differences across hosts:

- `` !`command` `` dynamic injection and ` ```! ` blocks
- Skill-scoped `hooks:`
- `effort`, `paths`, `shell`
- `${CLAUDE_SKILL_DIR}` substitution (host support varies — verify before using on Codex-exposed skills)

When a Codex-exposed skill needs bundled-script paths, keep the current `<skill-dir>` prose placeholder and let Claude resolve it contextually. Save `${CLAUDE_SKILL_DIR}` for Claude-only skills.

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

### Arguments Behavior

For marketplace-installed plugin skills, `arguments` makes arguments **mandatory** (Enter is
blocked until provided) and `argument-hint` is **not displayed**. Direct skills
(`~/.claude/skills/`) are unaffected — both fields work as expected.

Only use `arguments` when the skill genuinely cannot function without explicit input (e.g. an
issue number). Prefer `argument-hint` alone for optional hints. `$ARGUMENTS` works regardless
of whether `arguments` is declared.

### AskUserQuestion Conventions

Skills using `AskUserQuestion` must follow these rules:

1. First option is recommended — add `(Recommended)` suffix to its label
2. Every option has a description explaining the choice
3. Order by relevance — recommended first, alternatives next, skip/none last
4. Maximum 4 options — "Other" is added automatically by Claude Code
5. Headers ≤12 characters, labels 1-5 words

For any skill compatible with both Claude Code and Codex that uses `AskUserQuestion`,
include a local fallback in `SKILL.md`. If `AskUserQuestion` is unavailable, present
the same decision in normal chat as a short numbered list of 2-5 concise options,
keep the recommended option first, and wait for the user's reply so they can answer
with just the option number.

### Multi-Agent Convention

Skills for different agents (Claude Code, Codex, etc.) live in the same group directories — no nesting by agent. Agent compatibility is declared via the `compatibility` frontmatter field.

**`compatibility` is the single source of truth for host support.** It is not just
documentation: `scripts/skills-packaging.sh sync-repo` parses it to decide which skills land
in each host's generated tree, so editing it changes what ships.

Recognised host tokens are `Claude Code`, `Codex`, `OpenCode`, and `Pi`, comma-separated:

```yaml
compatibility: Claude Code                        # Claude-only — needs a documented reason
compatibility: Claude Code, Codex, OpenCode, Pi   # fully portable (the common case)
```

**Universal skill:** Omit `compatibility` entirely — the skill works with any agent.

**The Codex set must be a subset of every other host's set.** Codex, OpenCode, and pi all
read `.agents/skills/`, which carries the Codex-vetted set, and each non-Codex host also
reads its own tree. So the set a host really sees is its own tree unioned with the Codex
tree. If a skill declared `Codex` but not `Pi`, pi would still pick it up from
`.agents/skills/` despite never declaring support. `scripts/validate-codex.sh` fails on
that combination. In practice: a skill that is Codex-safe is portable, so declare all four.

Adding a host to a skill is not free. Check that the body has no Claude-only dependency —
`AskUserQuestion` without a chat fallback, `subagent_type`, Skill-tool orchestration,
`${CLAUDE_SESSION_ID}`, or `~/.claude/...` paths.

The README "Available Skills" tables include an **Agent** column for quick scanning.

### Per-Host Skill Trees

`sync-repo` generates one symlink tree per host, all pointing into the canonical
`<group>/skills/<name>` directories:

| Tree | Read by | Contents |
| ---- | ------- | -------- |
| `.agents/skills/` | Codex, OpenCode, pi | Codex-vetted set (from `scripts/codex/catalog.json`) |
| `.opencode/skills/` | OpenCode | Every skill declaring `OpenCode` |
| `.pi/skills/` | pi | Every skill declaring `Pi` |

All three are **generated** — never edit them by hand. To install a host's set globally
rather than repo-locally:

```bash
./scripts/skills-packaging.sh install-host opencode   # -> ~/.config/opencode/skills
./scripts/skills-packaging.sh install-host pi         # -> ~/.pi/agent/skills
./scripts/skills-packaging.sh install-host codex      # -> ~/.agents/skills
```

`install-host` prunes only links that point into this repo, so unrelated skills sharing the
destination directory are left alone.

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

1. Choose the appropriate group directory (`plan/`, `build/`, `review/`, `audit/`, `maintain/`, `ship/`, `assist/`, `obsidian/`, or `workflow/`)
2. Create a real directory: `mkdir -p <group>/skills/<skill-name>` (never a symlink)
3. Create `<group>/skills/<skill-name>/SKILL.md` with required frontmatter and instructions
4. Add `scripts/`, `references/`, or `assets/` directories as needed
5. Update the appropriate "Available Skills" table in `README.md`
6. Run `bash .github/scripts/validate-skills.sh` to verify marketplace, manifests, and skill layout
7. Validate via `skill-audit` skill if available

## Plugin Manifests (`.claude-plugin/`)

`marketplace.json` and `plugin.json` have **different schemas** — do not mix their fields.

- **`marketplace.json`** — marketplace registry entry. Plugin objects support: `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`. **No `skills` field.** Adding `skills` here causes validation error: `plugins.0.skills: Invalid input`.
- **`plugin.json`** — plugin manifest. Skills are auto-discovered from subdirectories containing `SKILL.md`. Do not declare a `skills` field — it is no longer supported.

Skills are discovered automatically from the plugin root directory. No per-skill registration is needed in either file.

## Codex Wrapper Plugins

Do not add `.codex-plugin/plugin.json` directly to the source group directories (`plan/`,
`build/`, `review/`, `audit/`, `maintain/`, `ship/`, `assist/`, `obsidian/`, `workflow/`).

Use wrapper plugins under `plugins/<plugin-name>/` instead:

- Source groups remain the canonical skill source for all agents.
- Wrapper plugins expose only the Codex-vetted subset of skills.
- `plugins/<plugin-name>/skills/` should contain symlinks to the real skill directories.
- `.agents/skills/` should also contain only Codex-vetted skill symlinks.

Do not rely on `compatibility` metadata alone to hide unsupported skills from Codex discovery.
Only add `Codex` to a skill's `compatibility` frontmatter after reviewing that the instructions are
actually Codex-safe. In this repo, Codex-compatible skills must also be exposed through
`scripts/codex/catalog.json`.

Seven skills are `compatibility: Claude Code`, each locked by what it actually does. They
should stay Claude-only unless their workflow changes:

- `maintain/skills/permissions-cleanup` — operates on Claude Code
  `settings.json` / `settings.local.json` permission files rather than Codex config.
- `maintain/skills/retro` — reads and writes Claude's own state: `~/.claude/CLAUDE.md`,
  `.claude/rules/*.mdc`, and `~/.claude/projects/<encoded-cwd>/retro/`.
- `review/skills/consilium` and `review/skills/spec-extractor` — dispatch fleets of
  plugin-namespaced subagents via `subagent_type` and key temp files on
  `${CLAUDE_SESSION_ID}`.
- `assist/skills/polish-prompt` — runs a four-way parallel candidate tournament plus a
  separate judge subagent, gates on `AskUserQuestion` at four points, and writes
  `.claude/tmp/polish-*-<session-id>.md`. Fleet orchestration, same class as `consilium`.
- `plan/skills/issue-flow` and `workflow/skills/solve-issue` — orchestrate other skills
  through Claude's Skill tool and gate on `AskUserQuestion`.

`assist/skills/codex` is the one skill that is portable but deliberately not Codex-exposed:
running it inside Codex would be recursive, while it is genuinely useful from OpenCode and
pi. Hence `compatibility: Claude Code, OpenCode, Pi`. This is exactly the case the per-host
split exists for — before it, a Codex-specific exclusion also denied the skill to two
unrelated hosts.

When adding a new skill, or when upgrading an existing skill to support Codex, make sure the
Codex packaging layer is updated in the same change:

- Add or update the skill's `compatibility` frontmatter to reflect actual Codex support.
- Add `agents/openai.yaml` if the skill should be exposed in Codex.
- Add the skill symlink in `.agents/skills/` if it is part of the repo-local Codex skill set.
- Add the skill symlink in the appropriate `plugins/<plugin-name>/skills/` wrapper plugin if it should
  be installable through the repo marketplace.
- If a Codex-exposed skill mirrors a Claude plugin agent via a prompt reference
  (for example `references/*-prompt.md`), update the Claude agent file and the
  Codex prompt reference together so the two hosts do not drift out of sync.
- Ensure the wrapper plugin manifest and `.agents/plugins/marketplace.json` still reflect the
  intended Codex plugin set.
- Update `scripts/codex/catalog.json`, run `./scripts/validate-codex.sh`, and run `./scripts/skills-packaging.sh sync-repo` so the
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
- `subagent_type` for plugin-distributed agents requires the namespaced form (e.g. `subagent_type: "review:review-build"`)
- `subagent_type` for built-in agents uses the plain name (e.g. `subagent_type: "general-purpose"`)
- Agent `name` in frontmatter must match the filename (without `.md`)

## Avoid

- Putting all content in SKILL.md body — move reference material to `references/`
- Writing vague descriptions that don't help the agent decide when to activate the skill
- Creating scripts with undocumented external dependencies
- Using absolute paths or paths outside the skill directory

## Specs and Plans

Specs and plans are stored in `docs/superpowers/` (gitignored). Delete the spec and plan files for a feature once it is fully implemented.

## Releases

Use the `skills-release` skill (`tools/skills-release/`, surfaced to Claude Code through the
`.claude/skills/skills-release` symlink). Its `release-prepare.sh` / `release-bump.sh` scripts
handle every version-bearing file.

The version is declared in **four kinds of file**, and every one must match the release tag:

| File | Read by |
| ---- | ------- |
| `.claude-plugin/marketplace.json` (per plugin entry) | Claude Code marketplace |
| `<group>/.claude-plugin/plugin.json` | Claude Code plugin loader |
| `scripts/codex/catalog.json` | Codex wrapper generator |
| `plugins/<plugin-name>/.codex-plugin/plugin.json` | Codex plugin loader (generated) |
| `package.json` | pi package manifest |

`.github/scripts/validate-version.sh` fails the release workflow if any of them drifts from the
tag. Add new version-bearing files to that script, to `release-prepare.sh`, and to
`release-bump.sh` in the same change — mutual agreement between manifests is not enough, since
they can all go stale together.

### `package.json`

It exists only as the **pi package manifest** (`pi.skills` points at the nine `<group>/skills`
directories) and as a version anchor. It is `"private": true` and is **never published to npm** —
pi installs straight from git. Do not run `npm publish`, `npm version`, or add dependencies.

## Git & GitHub

Conventional commits: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`.

When working on an issue, create a new branch named `issue-<number>`.

### Commits

- **With issue:** `<Issue Title> #<number>` — e.g. `feat: add ask skill #12`
- **Without issue:** `<type>: <description>`
- **One commit per feature.** Do all work first, then produce a single clean commit. No intermediate commits.

### Pull Requests

- **Title:** `<type>: <description> #<number>`
- **Body:** concise what/why, no emojis, one blank line between sections.
- Multiple issues go on one `Closes` line: `Closes #1 #23 #456`.
- End with the session link as the last line, wrapped small: `<sub>[Claude Code session](<link>)</sub>`. It is the only attribution — never append a second generated footer, `---` rule, or promotional line, including on PRs created from the web.

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
