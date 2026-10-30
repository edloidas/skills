# edloidas/skills

A collection of Claude Code and other agents skills following the [Agent Skills specification](https://agentskills.io/specification).

**Never commit or push changes unless explicitly asked.** Never commit directly to the main branch unless explicitly asked.

**No AI footers:** Do not add "Drafted with AI assistance", Claude Code session links, `<sub>` attribution lines, a trailing `---` rule, or anything similar to commit messages, issue bodies, or PR bodies — including PRs created from the web. No `Co-Authored-By` trailer crediting an assistant either, and an existing one in git history is not licence to repeat it. Add attribution only when this file, the user's own instructions, or the user's prompt asks for it.

## Repo Instructions

`AGENTS.md` is the one repo instruction file, read by Codex, OpenCode, pi, and Claude Code —
Claude Code reads `AGENTS.md` when no `CLAUDE.md` exists. Do not add a `CLAUDE.md`,
`CLAUDE.local.md`, or `.claude/CLAUDE.md`: Claude Code can load one of them instead of this file.

This file holds what every session needs. Reference material read only while doing a specific
job lives in `docs/`, and each rule lives in exactly one of these files:

| Doc | Read it when |
| --- | ------------ |
| [docs/writing-skills.md](docs/writing-skills.md) | Creating or editing a skill: naming, frontmatter, discovery text, how to write a body, `Asking the User`, portability across hosts |
| [docs/validation.md](docs/validation.md) | A validator fails, or you change one: body budgets and their reasons, Claude-only pattern detection and its exemption |
| [docs/testing.md](docs/testing.md) | Adding or changing a bundled shell script or a `validate-skills.sh` rule |
| [docs/packaging.md](docs/packaging.md) | Changing the host set of a skill, the Codex wrapper, the generated trees, plugin manifests, or bundled agents |
| [docs/releases.md](docs/releases.md) | Cutting a release or adding a version-bearing file |

## Layout

The whole collection is one Claude Code plugin, `edloidas`, whose root is the repo root. The
marketplace (also named `edloidas`) has a single entry with `"source": "./"`:

```
.claude-plugin/
├── plugin.json                   # The edloidas plugin manifest
└── marketplace.json              # The edloidas marketplace, one plugin entry
agents/                           # Plugin subagents (code-to-spec's spec-* agents)
docs/                             # Reference docs for working on this repo
skills/
└── <skill-name>/                 # Canonical skill location — a REAL directory
    ├── SKILL.md                  # Required — frontmatter + instructions
    ├── scripts/                  # Optional — executable code
    ├── references/               # Optional — docs loaded on demand
    └── assets/                   # Optional — templates, images, data
tests/skills/<skill-name>/        # Behavioral tests for bundled scripts
tools/skills-release/             # Repo-only skill, not published
```

**`skills/<skill-name>/` is the one canonical location for a skill, and it must be a real
directory — never a symlink.** Why, and what enforces it: [docs/packaging.md](docs/packaging.md).

`.agents/`, `.opencode/skills/`, `.pi/skills/`, and `plugins/edloidas/` are generated symlink
trees and manifests. Never edit them by hand: change the source skill, its `compatibility`, or
`scripts/codex/catalog.json`, then run `./scripts/skills-packaging.sh sync-repo` and commit the
result.

## Skill Changes Are Gated

Any change that creates, edits, moves, renames, or deletes a skill directory clears
`skills/skill-audit` before it is committed. Any change to a bundled shell script also
clears `bash tests/run.sh`. The four checkers own different halves and none substitutes for
another:

| Checker | Owns | Failure |
| ------- | ---- | ------- |
| `.github/scripts/validate-skills.sh` | Marketplace and plugin manifests, canonical layout, per-skill frontmatter rules, skill tiers and their discovery byte limits, body line and token ceilings, dangling bundled paths, Claude-only mechanisms in a portable skill, the verbatim `Asking the User` section, shouty emphasis in the body and in `references/*prompt*.md` fences, calibration adverbs, and README skill-count and tier-column drift (rules: [docs/writing-skills.md](docs/writing-skills.md); ceilings and exemptions: [docs/validation.md](docs/validation.md)) | Hard, fails CI; behavioural-style words warn only |
| `scripts/validate-codex.sh` | Codex catalog, `compatibility` agreement, `agents/openai.yaml` and its tier-to-`allow_implicit_invocation` mapping, host subset rule | Hard, fails CI |
| `tests/run.sh` | What a bundled script actually returns — exit codes, chosen branch, parsed output, refusals ([docs/testing.md](docs/testing.md)) | Hard, fails CI |
| `skill-audit` | Discovery, instruction quality, context cost, portability, safety, layer discipline | Scored 1-5, PASS / FAIL |

`skill-audit` never edits anything and never regenerates the packaging layer — a stale
generated tree is one of its findings. Anything mechanically checkable belongs in one of the
two validators, not in the rubric; add new mechanical rules there and let the skill cite them.

Reading a script cannot replace running it. `detect-base.sh` shipped a wrong answer while
`skill-audit` scored `issue-flow` 4.7/5 with no category below 4 — the prose was correct and
the script did not do what the prose said. That is what `tests/run.sh` is for.

`bash tests/run.sh` takes several minutes; run it in the background.

## Specs and Plans

Specs and plans are stored in `docs/superpowers/` (gitignored). Delete the spec and plan files for a feature once it is fully implemented.

## Releases

Use the `skills-release` skill (`tools/skills-release/`, surfaced to Claude Code through the
`.claude/skills/skills-release` symlink). The version-bearing files and the `package.json`
rules are in [docs/releases.md](docs/releases.md).

## Git & GitHub

Conventional commit style: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`.

- **Branch**: `issue-<number>` when working on an issue.
- **Commit / issue / PR title**: `<Issue Title> #<number>`, e.g. `feat: add ask skill #12`. Without
  an issue, `<type>: <description>`.
- **One commit per feature.** Do all work first, then produce a single clean commit. No
  intermediate commits.
- **PR body**: concise what and why, one blank line between sections. One `Closes #<number>` per
  line, last — after the body text. GitHub links only the first reference after a keyword, so
  `Closes #1 #23 #456` closes #1 and silently leaves the rest open.

## License

All skills in this repository are released under the MIT License unless a skill's own `SKILL.md` specifies otherwise via the `license` frontmatter field.
