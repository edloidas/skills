# Skills

A public collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agent skills following the [Agent Skills specification](https://agentskills.io/specification).

## Usage

Clone this repository and register it as a skill source in your Claude Code configuration:

```bash
git clone https://github.com/edloidas/skills.git
```

Point Claude Code to the cloned directory to make skills available in your sessions. See the [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) for details on configuring custom skills.

## Skill Structure

Each skill is a top-level directory containing at minimum a `SKILL.md` file:

```
<skill-name>/
├── SKILL.md              # Required — frontmatter + instructions
├── scripts/              # Optional — executable code
├── references/           # Optional — additional documentation
└── assets/               # Optional — templates, images, data files
```

The `SKILL.md` file contains YAML frontmatter (`name`, `description`) followed by Markdown instructions:

```markdown
---
name: example-skill
description: Does X when the user asks for Y.
---

## Steps

1. First, do this.
2. Then, do that.
```

See the full [Agent Skills specification](https://agentskills.io/specification) for all available frontmatter fields and conventions.

## Available Skills

*No skills yet — check back soon.*

## Creating a Skill

1. Create a directory at the repo root matching the skill name
2. Add a `SKILL.md` with required `name` and `description` frontmatter
3. Write Markdown instructions in the body (keep under 500 lines)
4. Optionally add `scripts/`, `references/`, or `assets/` directories
5. Update the table above

## License

[MIT](LICENSE)
