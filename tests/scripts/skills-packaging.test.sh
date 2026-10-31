#!/usr/bin/env bash
# skills-packaging.sh sync-repo — the Codex plugin it generates. Codex drops symlinks when it
# copies a plugin into its cache, so the plugin has to be rooted at the repo root and name its
# real skill directories; a plugin of symlinked skills installs empty.

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture.sh"

# A repo with one Codex skill in the catalog and one Claude Code-only skill outside it.
make_repo() {
  mkdir -p scripts/codex assets skills/sample/agents skills/claude-only
  cp "$(script scripts/skills-packaging.sh)" scripts/skills-packaging.sh
  printf 'png' > assets/logo.png
  cat > scripts/codex/catalog.json <<'JSON'
{
  "version": "1.2.3",
  "marketplace": { "name": "fixture-skills", "displayName": "Fixture" },
  "author": { "name": "A", "url": "https://example.com" },
  "pluginBranding": { "brandColor": "#000000", "logo": "./assets/logo.png", "composerIcon": "./assets/logo.png" },
  "repository": "https://example.com/repo",
  "license": "MIT",
  "plugins": [
    {
      "name": "fixture", "displayName": "Fixture", "description": "d", "shortDescription": "s",
      "longDescription": "l", "category": "c", "websiteURL": "https://example.com",
      "keywords": ["k"], "skills": ["skills/sample"]
    }
  ]
}
JSON
  printf -- '---\nname: sample\ndescription: d\ncompatibility: Claude Code, Codex, OpenCode, Pi\n---\n' \
    > skills/sample/SKILL.md
  printf 'policy:\n  allow_implicit_invocation: true\n' > skills/sample/agents/openai.yaml
  printf -- '---\nname: claude-only\ndescription: d\ncompatibility: Claude Code\n---\n' \
    > skills/claude-only/SKILL.md
}

sync() {
  run bash scripts/skills-packaging.sh sync-repo
}

test_plugin_lists_catalog_skills_by_path() {
  make_repo
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq '["./skills/sample/"]' "$(jq -c '.skills' .codex-plugin/plugin.json)" "plugin skills"
  assert_eq 1.2.3 "$(jq -r '.version' .codex-plugin/plugin.json)" "plugin version"
}

test_marketplace_points_at_repo_root() {
  make_repo
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq ./ "$(jq -r '.plugins[0].source.path' .agents/plugins/marketplace.json)" "source path"
  assert_eq fixture "$(jq -r '.plugins[0].name' .agents/plugins/marketplace.json)" "plugin name"
}

test_agents_tree_holds_only_catalog_skills() {
  make_repo
  sync
  assert_symlink_to .agents/skills/sample ../../skills/sample
  assert_no_file .agents/skills/claude-only
}

test_second_plugin_refused() {
  make_repo
  jq '.plugins += [.plugins[0] | .name = "other" | .skills = ["skills/claude-only"]]' \
    scripts/codex/catalog.json > catalog.tmp && mv catalog.tmp scripts/codex/catalog.json
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "exactly one plugin" "error output"
  assert_no_file .codex-plugin/plugin.json
}

test_missing_logo_refused() {
  make_repo
  rm assets/logo.png
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Plugin logo not found" "error output"
}

run_tests
