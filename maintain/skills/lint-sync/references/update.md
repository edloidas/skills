# Update Workflow

Read from `lint-sync` when the mode is `update`. Refreshes all reference files from upstream. Paths are relative to the skill root.

## U1: Update the ESLint mapping files

| File | Source | `_meta` fields to bump |
|------|--------|------------------------|
| `references/biome-eslint-mapping.json` | `https://biomejs.dev/linter/rules-sources/` | `biomeVersion`, `updatedAt` |
| `references/oxc-eslint-mapping.json` | `https://oxc.rs/docs/guide/usage/linter/rules` | `oxlintVersion`, `updatedAt` |

For each: fetch, parse the rule mappings (Oxc's are grouped by plugin), diff against the
existing file, show what was added and removed, then bump the `_meta` fields.

## U2: Update type-aware-rules.json

```bash
gh api repos/typescript-eslint/typescript-eslint/contents/packages/eslint-plugin/src/configs/flat/disable-type-checked.ts --jq '.content' | base64 -d
```

Parse, diff, update `_meta.updatedAt`.

## U3: Update version files

Check Biome and Oxc changelogs for new versions not yet tracked:
- Biome: `https://biomejs.dev/blog/` — look for new `biome-vX-Y` posts
- Oxc: `https://oxc.rs/blog/` — look for new release posts

For each new version found, add entry to `biome-versions.json` or `oxc-versions.json` with:
- Promoted rules
- New rules
- New formatter options
- New features

End with one line per refreshed file: `biome-eslint-mapping.json: +14 / -3 (v2.4.2)`. Then stop
— `update` maintains this skill's reference files and touches no project config.
