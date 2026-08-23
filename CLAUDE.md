# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

**Never commit or push changes unless explicitly asked.** Never commit directly to the main branch unless explicitly asked.

**No AI footers:** Do not add "Drafted with AI assistance", Claude Code session links, `<sub>` attribution lines, or anything similar to commit messages, issue bodies, or PR bodies. No `Co-Authored-By` trailer crediting an assistant either, and an existing one in git history is not licence to repeat it. Add attribution only when this file, the user's own instructions, or the user's prompt asks for it.

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
and rejects a leftover pre-4.0 `<group>/<skill-name>` path. It also enforces the per-skill
rules that must never regress — required frontmatter, `name` matching the directory and the
naming format, `description` within 1,024 chars, the combined discovery entry within 1,536,
and no `references/`, `scripts/`, or `assets/` path in `SKILL.md` that the skill does not
ship.

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

Behavioral tests for bundled scripts live in a repo-root `tests/` tree that mirrors the skill
paths, deliberately outside every skill and every distribution tree — see
[Script Tests](#script-tests).

**Plugin groups:**
- `plan/` — Issue drafting, analysis, and the full issue lifecycle (3 skills)
- `build/` — Conflict resolution, commit summaries, quick commits, and findings fixes (4 skills)
- `review/` — Adversarial change review, cleanup, approach boards, PR feedback triage, and spec extraction (5 skills)
- `audit/` — CI, script, security, skill, workspace, tsconfig, Three.js, React, and test-suite auditing (9 skills)
- `maintain/` — Agent instruction layer setup and drift check, label sync, lint migration, editor config sync, repo security hardening, and stale process cleanup (6 skills)
- `ship/` — Release workflows for npm packages (1 skill)
- `assist/` — External opinion, design discussion, assistance, handoffs, and plain restatement tools (5 skills)
- `write/` — Markdown, README, and repository documentation writing (1 skill)
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
- `plugins/edloidas-write/` → `edloidas-write` / `Edloidas Write`
- `plugins/edloidas-obsidian/` → `edloidas-obsidian` / `Edloidas Obsidian`
- `plugins/edloidas-workflow/` → `edloidas-workflow` / `Edloidas Workflow`

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

**This is now enforced, not advised.** `validate-skills.sh` hard-fails a skill declaring
`Codex`, `OpenCode`, or `Pi` that contains `` !`command` `` injection, a `${CLAUDE_*}`
substitution, `ToolSearch`, `TodoWrite`, `SlashCommand`, or `subagent_type` — in `SKILL.md`
or any bundled `.md`. Claude-only skills are exempt, since for them these are the correct
mechanism. The rule exists because advice did not hold: `build/skills/commit` sat in the
Codex catalog with its entire context-gathering section written as seven injected commands,
plus three body lines instructing the agent not to gather the context itself. On Codex,
OpenCode, and pi the skill had no git state and was told not to look for any.

Detection lives in `CLAUDE_ONLY_PATTERNS` in that script. Note the comment there about
`(^|[[:space:]])`: BSD grep treats `^` inside a group as a literal, so the anchored
alternative matches nothing on macOS while passing on CI's GNU grep. Two `-e` patterns are
the portable form.

One skill is exempt, via `CLAUDE_ONLY_EXEMPT`:

| Skill | Why |
| ----- | --- |
| `audit/skills/skill-audit` | Its subject matter *is* these mechanisms — the rubric and the dispatched prompt have to name them to tell an auditor what to look for. The exemption is skill-wide, so a genuine violation inside it would go uncaught; acceptable because it dispatches as intent and has no workflow of its own a host could fail to run. |

Adding a row is a decision that needs a reason in this table. The exemption is not a way
past a finding — a skill that *uses* one of these mechanisms narrows its `compatibility`
or states the step as intent instead.

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

#### The canonical `Asking the User` section

Any skill declaring a non-Claude host and asking a question carries exactly one section,
worded **verbatim** as below. It sits immediately before the skill's first procedural
section — `## Workflow`, `## Phase 0`, `## Execution Steps`, whichever the skill uses —
at `##`, or `###` where the skill nests its conventions.

```markdown
## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.
```

Copy it; do not paraphrase it. Fourteen skills each carried their own wording of this rule
before it was unified, which made a reader unable to tell a deliberate variation from
drift. `skill-metrics.mjs` reports whether a skill has the canonical section, ad-hoc
wording, or none.

**Call sites do not re-explain the fallback.** They say `Ask, per **Asking the User**:`
followed by the options, and nothing more. A skill may add one extra paragraph under the
section for its own policy — which gate is never skipped, what happens when the host
cannot prompt at all — but not a second copy of the mechanics.

A skill whose only mention of `AskUserQuestion` is documentation about the field (as in
`skill-audit`'s rubric) does not need the section, and neither does a Claude-only skill.

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

**Subagent dispatch is written as intent, never as mechanism.** A skill declaring any
non-Claude host must not name a tool, an agent type, or a model when it dispatches work. Say
what to spawn and what it must return, and note the inline fallback for hosts without
subagents:

```
Dispatch a subagent to scan the target files against the active convention
rules and return structured violations. If the host has no subagent facility,
run the same prompt inline.
```

For dispatch specifically, per-host "Claude Code path / Codex path" splits and host-hint
parentheticals (`` `subagent_type: Explore` (Claude Code; use the host's nearest equivalent
elsewhere)``) are violations, not fallbacks — the aim is one set of instructions every agent
can follow. When the dispatched prompt is long enough to matter, put it in `references/` and
point every host at the same file; never keep a second copy in a plugin `agents/` file, which
only one host can read and which will drift.

Three things this rule does **not** cover:

- `allowed-tools` — a declaration, not an instruction. A portable skill that dispatches
  subagents should still declare `Task` / `Agent` for Claude Code's pre-approval, and that is
  not a mismatch with intent-only prose in the body.
- `AskUserQuestion` — the per-host fallback above is *required*, not forbidden.
- Per-host **data**, such as `assist/skills/handoff`'s table of where each host stores its
  transcripts. Facts that genuinely differ per host belong in a table with a documented
  default; only the dispatch procedure has to be uniform.

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

- Keep under 500 lines / ~5000 tokens. **Enforced** by `.github/scripts/validate-skills.sh`,
  which fails the build on a breach — see [Body Line Budgets](#body-line-budgets)
- Include step-by-step instructions, examples, and edge cases
- Move detailed reference material to `references/` files
- Use relative paths from the skill root when referencing files (e.g. `references/api-guide.md`)
- Keep references one directory level deep; avoid nested reference chains
- Keep individual reference files focused — smaller files mean less context usage

### Body Line Budgets

The 500-line body cap is mechanical, so it lives in `validate-skills.sh` rather than in
`skill-audit`'s rubric. Three skills carry a larger budgeted allowance in
`BODY_LINE_BUDGETS`:

| Skill | Allowance | Why |
| ----- | --------- | --- |
| `plan/skills/issue-flow` | 1000 | **Sanctioned.** It owns every git and `gh` write in the issue pipeline — base detection, the fork point, the squash rules, the force-push lease. That concentration is the seam that let `solve-issue` and `changes-review` become portable, and splitting it would put the same rules in two files, which this repo treats as the drift mechanism. Its size is the cost of being the single writer. |
| `workflow/skills/solve-issue` | 540 | Marginally over at 520. Trim on the next substantive edit rather than raising the budget. |

A budget is a per-skill ceiling, not an exemption — a budgeted skill that grows past its
allowance still fails, so a deliberate size cannot drift into an accidental one. Adding a
row is a decision that needs a reason in this table.

`body_line_count` counts every line after the frontmatter, **horizontal rules included**.
It used to skip each `---` in the file rather than only the two delimiters, which made a
body measure smaller than what the agent actually loads: `issue-writer` reported 498 lines
against a real 507, because nine `---` rules sit inside its issue templates. Six other
skills were undercounted too, none of them across a ceiling — `lint-sync` at 493 is now
the closest to the cap. A checker that reads low is worse than no checker, so if the two
counts ever disagree again, trust neither until you know which one is wrong.

`skill-audit` does not re-score a budgeted skill for its size. The validator owns the
mechanical limit; the rubric still judges whether heavy material is deferred, whether the
length is proportionate, and whether anything is duplicated into `references/`.

### Scripts

- Must be self-contained or clearly document dependencies
- Include helpful error messages
- Handle edge cases gracefully

## Creating a New Skill

1. Choose the appropriate group directory (`plan/`, `build/`, `review/`, `audit/`, `maintain/`, `ship/`, `assist/`, `write/`, `obsidian/`, or `workflow/`)
2. Create a real directory: `mkdir -p <group>/skills/<skill-name>` (never a symlink)
3. Create `<group>/skills/<skill-name>/SKILL.md` with required frontmatter and instructions
4. Add `scripts/`, `references/`, or `assets/` directories as needed
5. Update the appropriate "Available Skills" table in `README.md`
6. Run `bash .github/scripts/validate-skills.sh` to verify marketplace, manifests, and skill layout
7. If the skill bundles a shell script, add its tests under `tests/<group>/<skill>/` and run `bash tests/run.sh`
8. Run `skill-audit` and clear it before committing — see below

## Skill Changes Are Gated

Any change that creates, edits, moves, renames, or deletes a skill directory clears
`audit/skills/skill-audit` before it is committed. Any change to a bundled shell script also
clears `bash tests/run.sh`. The four checkers own different halves and none substitutes for
another:

| Checker | Owns | Failure |
| ------- | ---- | ------- |
| `.github/scripts/validate-skills.sh` | Marketplace and plugin manifests, canonical layout, per-skill frontmatter rules, dangling bundled paths, Claude-only mechanisms in a portable skill | Hard, fails CI |
| `scripts/validate-codex.sh` | Codex catalog, `compatibility` agreement, `agents/openai.yaml`, host subset rule | Hard, fails CI |
| `tests/run.sh` | What a bundled script actually returns — exit codes, chosen branch, parsed output, refusals | Hard, fails CI |
| `skill-audit` | Discovery, instruction quality, context cost, portability, safety | Scored 1-5, PASS / FAIL |

`skill-audit` never edits anything and never regenerates the packaging layer — a stale
generated tree is one of its findings. Anything mechanically checkable belongs in one of the
two validators, not in the rubric; add new mechanical rules there and let the skill cite them.

Reading a script cannot replace running it. `detect-base.sh` shipped a wrong answer while
`skill-audit` scored `issue-flow` 4.7/5 with no category below 4 — the prose was correct and
the script did not do what the prose said. That is what `tests/run.sh` is for.

## Script Tests

`tests/` holds behavioral tests for the shell scripts this repo bundles. Plain bash, no
install step, no new dependency:

```bash
bash tests/run.sh                    # everything
bash tests/run.sh detect-base        # only files whose path matches
```

**Tests live at the repo root, never inside a skill.** A `tests/` directory under
`<group>/skills/<name>/` would be symlinked into every generated host tree and ship inside
the installed plugin. `tests/<group>/<skill>/<script>.test.sh` mirrors the skill path
instead, so the distribution layer never sees them.

A test file sources `tests/lib/assert.sh` and `tests/lib/fixture.sh`, defines `test_*`
functions, and ends with `run_tests`. Each case runs in its own subshell in its own sandbox
directory, with `HOME`, `TMPDIR`, and `XDG_CONFIG_HOME` pointed inside it and every
environment variable the scripts under test consult unset — `CLAUDECODE`, `OUTSIDER_*`,
`GIT_DIR`, and the rest. A script that starts reading a new variable needs that variable
added to the scrub in `run_tests`, or a case will pass or fail based on who ran it. `fixture.sh` builds throwaway git
repos with a local bare "remote" and replaces `PATH` with a sandbox pair — a stub directory
plus symlinks to a fixed list of core tools — which is what makes "the tool is not
installed" testable at all. Nothing reaches the network, real `$HOME`, or a real remote.

Two conventions matter:

- **Target bash 3.2**, the shell stock macOS ships. No associative arrays, no `mapfile`,
  no `${var,,}`, no `[[ -v ]]`. Under `set -u`, `"${arr[@]}"` and `${arr[0]}` on an empty
  array are unbound-variable errors on every bash before 4.4 — but `${#arr[@]}` is not,
  which is why it is the guard the bundled scripts use. Where an expansion cannot be
  guarded by a preceding `${#arr[@]}` check, use `${arr[@]+"${arr[@]}"}`.
- **The suite needs `timeout` or `gtimeout`** on PATH, since one of the scripts it tests
  requires it. Stock macOS has neither.
- **A known defect gets two cases**: one asserting the correct behavior, marked `skip` with
  the reason and the fix, and one pinning what the script does today. The skip keeps the
  finding visible in the report; the pin makes a fix trip the suite instead of passing
  silently.

Scripts whose whole body is a `gh` call are deliberately untested — the stub would assert
the stub. Cover logic, refusals, and parsing.

**Known gap: the suite only runs on Linux.** CI runs it on `ubuntu-latest`, so the bash 3.2
and BSD-userland targets above are a convention, not a verified one. Adding `macos-latest`
to the `test-scripts` matrix and invoking `/bin/bash tests/run.sh` explicitly (Homebrew's
bash 5 comes first on the runner's PATH) would test both axes for free on a public repo.
Expect the first run to surface harness portability fixes rather than script defects.

## Plugin Manifests (`.claude-plugin/`)

`marketplace.json` and `plugin.json` have **different schemas** — do not mix their fields.

- **`marketplace.json`** — marketplace registry entry. Plugin objects support: `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`. **No `skills` field.** Adding `skills` here causes validation error: `plugins.0.skills: Invalid input`.
- **`plugin.json`** — plugin manifest. Skills are auto-discovered from subdirectories containing `SKILL.md`. Do not declare a `skills` field — it is no longer supported.

Skills are discovered automatically from the plugin root directory. No per-skill registration is needed in either file.

## Codex Wrapper Plugins

Do not add `.codex-plugin/plugin.json` directly to the source group directories (`plan/`,
`build/`, `review/`, `audit/`, `maintain/`, `ship/`, `assist/`, `write/`, `obsidian/`, `workflow/`).

Use wrapper plugins under `plugins/<plugin-name>/` instead:

- Source groups remain the canonical skill source for all agents.
- Wrapper plugins expose only the Codex-vetted subset of skills.
- `plugins/<plugin-name>/skills/` should contain symlinks to the real skill directories.
- `.agents/skills/` should also contain only Codex-vetted skill symlinks.

Do not rely on `compatibility` metadata alone to hide unsupported skills from Codex discovery.
Only add `Codex` to a skill's `compatibility` frontmatter after reviewing that the instructions are
actually Codex-safe. In this repo, Codex-compatible skills must also be exposed through
`scripts/codex/catalog.json`.

One skill is `compatibility: Claude Code`, locked by what it actually does. It should stay
Claude-only unless its workflow changes:

- `review/skills/code-to-spec` — dispatches fleets of plugin-namespaced subagents via
  `subagent_type` and keys temp files on `${CLAUDE_SESSION_ID}`.

`review/skills/consilium` was Claude-only for the same reasons and is now portable. It stopped
being a review skill: it is an approach board that takes a problem or a decision, generates
candidate approaches from independent seats, and ranks them. Making it portable was mostly
subtraction — dispatch is stated as intent, model choice as intent and depth as a budget rather
than a turn count, its outside seat runs through `outsider` instead of a private `codex exec`
wrapper, and the temp files that forced `${CLAUDE_SESSION_ID}` are gone entirely because the
candidate set travels in the dispatched prompt and `outsider` owns the one file that still hits
disk.

`plan/skills/issue-flow` and `workflow/skills/solve-issue` were Claude-only for the same
reason `changes-review` was: they named the mechanism. Both now state delegation as intent
("invoke `issue-flow`", "dispatch one subagent"), each call site documents what to do when
the host cannot chain skills or has no subagents, and both carry the standard
`AskUserQuestion` fallback in a single `Asking the User` convention rather than repeating
it at sixteen call sites. `issue-flow` owns every git and `gh` write in the pipeline, so
`solve-issue` holds no duplicate of its commit format or squash rules — the seam is what
made them portable.

`review/skills/changes-review` was Claude-only for its per-agent `model` overrides. It now
states model choice as intent — most capable model the host offers, next tier down when that is
the orchestrator's own, a different one per reviewer where the host allows it — and degrades to
role diversity alone where it does not. Model diversity is still half of why the reviewers
disagree usefully, so the report says which kind of diversity a run actually got.

`assist/skills/outsider` used to be two skills, `codex` and `claude`, each excluded from the
host it would have called recursively. It now resolves an installed agent CLI that is not the
current host, so it declares all four hosts and still never invokes itself. Recursion is a
selection rule in `scripts/run-outsider.sh`, not a `compatibility` omission — which is the
pattern to follow for anything else that shells out to an agent CLI.

When adding a new skill, or when upgrading an existing skill to support Codex, make sure the
Codex packaging layer is updated in the same change:

- Add or update the skill's `compatibility` frontmatter to reflect actual Codex support.
- Add `agents/openai.yaml` if the skill should be exposed in Codex.
- Add the skill symlink in `.agents/skills/` if it is part of the repo-local Codex skill set.
- Add the skill symlink in the appropriate `plugins/<plugin-name>/skills/` wrapper plugin if it should
  be installable through the repo marketplace.
- A dispatched prompt lives in exactly one place — the skill's `references/*-prompt.md`, read
  by every host. Do not mirror it into a plugin `agents/` file: only Claude Code can read that
  copy, and the two drift the moment one is edited.
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

- Agents appear in the UI as `<plugin-name>:<agent-name>` (e.g. `review:spec-analyzer`)
- `subagent_type` for plugin-distributed agents requires the namespaced form (e.g. `subagent_type: "review:spec-analyzer"`)
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

It exists only as the **pi package manifest** (`pi.skills` points at the generated `.pi/skills`
tree) and as a version anchor. It is `"private": true` and is **never published to npm** —
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
- One `Closes #<number>` per line. GitHub links only the first reference after a keyword, so `Closes #1 #23 #456` closes #1 and silently leaves the rest open.
- Never append a generated footer, `---` rule, session link, `<sub>` attribution, or promotional line, including on PRs created from the web.

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
