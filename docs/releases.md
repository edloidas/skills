# Releases

Read this when cutting a release or adding a version-bearing file. Releases run through the
`skills-release` skill (`tools/skills-release/`); its `release-prepare.sh` / `release-bump.sh`
scripts handle every version-bearing file.

The version is declared in **five files**, and every one must match the release tag:

| File | Read by |
| ---- | ------- |
| `.claude-plugin/marketplace.json` (the one plugin entry) | Claude Code marketplace |
| `.claude-plugin/plugin.json` | Claude Code plugin loader |
| `scripts/codex/catalog.json` | Codex wrapper generator |
| `plugins/edloidas/.codex-plugin/plugin.json` | Codex plugin loader (generated) |
| `package.json` | pi package manifest |

`.github/scripts/validate-version.sh` fails the release workflow if any of them drifts from the
tag. Add new version-bearing files to that script, to `release-prepare.sh`, and to
`release-bump.sh` in the same change — mutual agreement between manifests is not enough, since
they can all go stale together.

## `package.json`

It exists only as the **pi package manifest** (`pi.skills` points at the generated `.pi/skills`
tree) and as a version anchor. It is `"private": true` and is **never published to npm** —
pi installs straight from git. Do not run `npm publish`, `npm version`, or add dependencies.
