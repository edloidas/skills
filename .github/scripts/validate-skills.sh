#!/usr/bin/env bash
set -euo pipefail

# Validate the Claude marketplace/source-plugin contract for this repo.
#
# Scope:
# - .claude-plugin/marketplace.json exists and is valid JSON
# - each marketplace entry points at a source group directory
# - each source group ships .claude-plugin/plugin.json with the expected
#   auto-discovery configuration ("skills": ".")
# - each source group contains discoverable skills
# - source groups do not embed Codex wrapper manifests directly
#
# The Codex wrapper contract is validated separately by scripts/validate-codex.sh.

MARKETPLACE=".claude-plugin/marketplace.json"

errors=0
plugin_count=0
total_skills=0
total_codex_compatible_skills=0

error() {
  echo "::error::$*" >&2
  errors=1
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to validate marketplace and plugin manifests" >&2
    exit 1
  fi
}

validate_json_file() {
  local path="$1"
  if ! jq empty "$path" >/dev/null 2>&1; then
    error "Invalid JSON: $path"
    return 1
  fi
}

read_frontmatter() {
  local skill_dir="$1"
  awk '
    BEGIN { delimiter_count = 0 }
    $0 == "---" {
      delimiter_count++
      next
    }
    delimiter_count == 1 { print }
    delimiter_count >= 2 { exit }
  ' "$skill_dir/SKILL.md"
}

skill_has_codex_compatibility() {
  local skill_dir="$1"
  read_frontmatter "$skill_dir" | awk '
    /^compatibility:/ {
      if ($0 ~ /Codex/) {
        found = 1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

require_jq

if [ ! -f "$MARKETPLACE" ]; then
  echo "::error::$MARKETPLACE not found" >&2
  exit 1
fi

validate_json_file "$MARKETPLACE"
plugin_count=$(jq '.plugins | length' "$MARKETPLACE")

if [ "$plugin_count" -eq 0 ]; then
  error "Marketplace does not declare any plugins: $MARKETPLACE"
fi

if [ "$errors" -eq 1 ]; then
  exit 1
fi

# Iterate over each plugin entry in marketplace.json
for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name // empty" "$MARKETPLACE")
  source_decl=$(jq -r ".plugins[$i].source // empty" "$MARKETPLACE")
  source=${source_decl#./}
  plugin_manifest="$source/.claude-plugin/plugin.json"

  if [ -z "$name" ]; then
    error "Marketplace plugin at index $i is missing a name"
    continue
  fi

  if [ -z "$source_decl" ]; then
    error "Marketplace plugin '$name' is missing a source path"
    continue
  fi

  if [[ "$source_decl" != ./* ]]; then
    error "Plugin '$name': source path should be repo-relative and start with './' (got '$source_decl')"
  fi

  if [ ! -d "$source" ]; then
    error "Plugin '$name': source directory '$source' does not exist"
    continue
  fi

  if [ -f "$source/.codex-plugin/plugin.json" ]; then
    error "Plugin '$name': source group '$source/' must not contain .codex-plugin/plugin.json; Codex wrapper manifests belong under plugins/<plugin-name>/"
  fi

  if [ ! -f "$plugin_manifest" ]; then
    error "Plugin '$name': missing .claude-plugin/plugin.json in '$source/'"
    continue
  fi

  validate_json_file "$plugin_manifest" || continue

  manifest_name=$(jq -r '.name // empty' "$plugin_manifest")
  manifest_skills=$(jq -r '.skills // empty' "$plugin_manifest")

  if [ "$manifest_name" != "$name" ]; then
    error "Plugin '$name': marketplace name does not match $plugin_manifest name '$manifest_name'"
  fi

  if [ "$manifest_skills" != "." ]; then
    error "Plugin '$name': expected $plugin_manifest to declare \"skills\": \".\" for source-group auto-discovery (got '$manifest_skills')"
  fi

  # Find all SKILL.md files inside the plugin source directory
  skill_count=0
  codex_compatible_count=0

  while IFS= read -r skill_md; do
    [ -n "$skill_md" ] || continue
    skill_count=$((skill_count + 1))
    skill_dir=$(dirname "$skill_md")
    if skill_has_codex_compatibility "$skill_dir"; then
      codex_compatible_count=$((codex_compatible_count + 1))
    fi
  done <<EOF
$(find "$source" -mindepth 2 -maxdepth 2 -name SKILL.md -print | sort)
EOF

  if [ "$skill_count" -eq 0 ]; then
    error "Plugin '$name': no skills found in '$source/'"
  else
    echo "Plugin '$name': $skill_count skills found in '$source/' ($codex_compatible_count Codex-compatible)"
    total_skills=$((total_skills + skill_count))
    total_codex_compatible_skills=$((total_codex_compatible_skills + codex_compatible_count))
  fi
done

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "Claude marketplace valid. $total_skills skills across $plugin_count plugins ($total_codex_compatible_skills marked Codex-compatible)."
