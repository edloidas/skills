# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

## Repository Structure

Each skill lives as a top-level directory in the repo root. This repo IS the skills collection — there is no nested `skills/` subdirectory.

```
<skill-name>/
├── SKILL.md              # Required — frontmatter + instructions
├── scripts/              # Optional — executable code (bash, python, js)
├── references/           # Optional — additional docs loaded on demand
└── assets/               # Optional — templates, images, data files
```

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

| Field           | Constraint                                                                       |
| --------------- | -------------------------------------------------------------------------------- |
| `license`       | License name or reference to a bundled LICENSE file                              |
| `compatibility` | 1–500 chars; describes environment needs (products, packages, network access)    |
| `metadata`      | Key-value mapping; use reasonably unique key names to prevent conflicts           |
| `allowed-tools` | **Experimental.** Space-delimited list of pre-approved tools (e.g. `Bash(git:*) Read`) |

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
metadata:
  author: edloidas
  version: "1.0"
---
```

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

1. Create a directory at the repo root: `mkdir <skill-name>`
2. Create `<skill-name>/SKILL.md` with required frontmatter and instructions
3. Add `scripts/`, `references/`, or `assets/` directories as needed
4. Update the "Available Skills" table in `README.md`
5. Validate with: `skills-ref validate ./<skill-name>`

## Avoid

- Putting all content in SKILL.md body — move reference material to `references/`
- Writing vague descriptions that don't help the agent decide when to activate the skill
- Creating scripts with undocumented external dependencies
- Using absolute paths or paths outside the skill directory

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
