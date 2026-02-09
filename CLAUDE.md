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

## Skill Naming

- Directory name must match the `name` frontmatter field exactly
- Lowercase letters, numbers, and hyphens only (`a-z`, `0-9`, `-`)
- No leading/trailing hyphens, no consecutive hyphens (`--`)
- Max 64 characters

## SKILL.md Conventions

### Frontmatter (YAML)

Required fields:

| Field         | Constraint                                           |
| ------------- | ---------------------------------------------------- |
| `name`        | 1–64 chars, matches directory name                   |
| `description` | 1–1024 chars, describes what the skill does and when |

Optional fields: `license`, `compatibility`, `metadata`, `allowed-tools`.

### Body (Markdown)

- Keep under 500 lines / ~5000 tokens
- Include step-by-step instructions, examples, and edge cases
- Move detailed reference material to `references/` files
- Use relative paths from the skill root when referencing files

### Scripts

- Must be self-contained or clearly document dependencies
- Include helpful error messages
- Handle edge cases gracefully

## Creating a New Skill

1. Create a directory at the repo root: `mkdir <skill-name>`
2. Create `<skill-name>/SKILL.md` with required frontmatter and instructions
3. Add `scripts/`, `references/`, or `assets/` directories as needed
4. Update the "Available Skills" table in `README.md`

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
