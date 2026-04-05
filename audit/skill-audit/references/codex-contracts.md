# Codex Contracts

Repo-specific Codex contract for `edloidas/skills`.

## When This Applies

Audit Codex Integration for a skill when any of these are true:
- `compatibility` in `SKILL.md` includes `Codex`
- `agents/openai.yaml` exists
- the skill path appears in `scripts/codex/catalog.json`

If none apply, score Codex Integration as `N/A`.

## Source of Truth

Treat these as the editable Codex contract:
- the source skill directory at `<group>/<skill-name>/`
- `compatibility` in `SKILL.md`
- `agents/openai.yaml`
- `scripts/codex/catalog.json`
- repo instructions in `CLAUDE.md`

Key repo rules from `CLAUDE.md`:
- Codex-exposed skills should include `agents/openai.yaml`
- Codex-compatible skills in this repo must be exposed through `scripts/codex/catalog.json`
- generated wrapper files must be regenerated, not edited by hand

## Generated Outputs

Treat these as generated wrapper outputs:
- `.agents/plugins/marketplace.json`
- `.agents/skills/<skill-name>`
- `plugins/<plugin-name>/.codex-plugin/plugin.json`
- `plugins/<plugin-name>/skills/<skill-name>`

Missing, stale, or contradictory generated outputs are valid audit findings, but the fix path should point back to `scripts/codex/catalog.json` plus `scripts/codex-packaging.sh sync-repo`, not direct manual edits.

## Per-Skill Checks

For Codex-applicable skills, check all of these:

1. `compatibility` includes `Codex` when the skill is exposed to Codex
2. `agents/openai.yaml` exists and includes:
   - `interface.display_name`
   - `interface.short_description`
   - `policy.allow_implicit_invocation`
   - optional `interface.default_prompt`
3. `scripts/codex/catalog.json` includes the skill path when the skill is Codex-compatible in this repo
4. the catalog entry places the skill under the correct source group
5. generated wrapper outputs reflect the catalog rather than a hand-maintained parallel registry
6. the skill instructions do not tell contributors to edit generated Codex wrapper files manually

## Validator

The primary repo validator is:

```bash
bash scripts/validate-codex.sh
```

Prefer validator output over manual inference when it directly covers the issue. Use manual inspection to explain why the validator failed or to score a skill when the validator cannot run.
