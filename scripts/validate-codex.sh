#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
CATALOG_PATH="$SCRIPT_DIR/codex/catalog.json"

SOURCE_GROUPS=(
  plan
  build
  review
  audit
  maintain
  ship
  assist
  obsidian
)

errors=0

error() {
  echo "::error::$*" >&2
  errors=1
}

append_line() {
  local current="$1"
  local value="$2"
  if [ -n "$current" ]; then
    printf '%s\n%s\n' "$current" "$value"
  else
    printf '%s\n' "$value"
  fi
}

list_contains() {
  local list="$1"
  local item="$2"
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$line" = "$item" ] && return 0
  done <<EOF
$list
EOF
  return 1
}

read_frontmatter() {
  awk '
    BEGIN { delimiter_count = 0 }
    $0 == "---" {
      delimiter_count++
      next
    }
    delimiter_count == 1 { print }
    delimiter_count >= 2 { exit }
  ' "$1/SKILL.md"
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

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    error "jq is required"
    return 1
  }
}

validate_catalog_shape() {
  if [ ! -f "$CATALOG_PATH" ]; then
    error "Codex catalog not found: $CATALOG_PATH"
    return
  fi

  if ! jq empty "$CATALOG_PATH" >/dev/null 2>&1; then
    error "Codex catalog is not valid JSON: $CATALOG_PATH"
    return
  fi

  jq -e '.version | strings | select(length > 0)' "$CATALOG_PATH" >/dev/null || error "Catalog version is required"
  jq -e '.marketplace.name | strings | select(length > 0)' "$CATALOG_PATH" >/dev/null || error "Catalog marketplace.name is required"
  jq -e '.marketplace.displayName | strings | select(length > 0)' "$CATALOG_PATH" >/dev/null || error "Catalog marketplace.displayName is required"
  jq -e '.plugins | length > 0' "$CATALOG_PATH" >/dev/null || error "Catalog must define at least one plugin"
  jq -e '([.plugins[].group] | length) == ([.plugins[].group] | unique | length)' "$CATALOG_PATH" >/dev/null || error "Catalog has duplicate plugin groups"
  jq -e '([.plugins[].name] | length) == ([.plugins[].name] | unique | length)' "$CATALOG_PATH" >/dev/null || error "Catalog has duplicate plugin names"
  jq -e '([.plugins[].skills[]] | length) == ([.plugins[].skills[]] | unique | length)' "$CATALOG_PATH" >/dev/null || error "Catalog has duplicate skill paths"
  jq -e '([.plugins[].skills[] | split("/")[-1]] | length) == ([.plugins[].skills[] | split("/")[-1]] | unique | length)' "$CATALOG_PATH" >/dev/null || error "Catalog has duplicate exposed skill names"
  jq -e 'all(.plugins[]; (.group | strings | length > 0) and (.name | strings | length > 0) and (.displayName | strings | length > 0) and (.description | strings | length > 0) and (.shortDescription | strings | length > 0) and (.longDescription | strings | length > 0) and (.category | strings | length > 0) and (.websiteURL | strings | length > 0) and (.brandColor | strings | test("^#[0-9A-Fa-f]{6}$")) and (.keywords | type == "array" and length > 0) and (.skills | type == "array" and length > 0))' "$CATALOG_PATH" >/dev/null || error "Each catalog plugin must define complete metadata, keywords, and skills"
}

collect_exposed_skills() {
  jq -r '.plugins[] | .group as $group | .name as $plugin | .skills[] | [$group, $plugin, .] | @tsv' "$CATALOG_PATH"
}

collect_source_skills() {
  local group
  for group in "${SOURCE_GROUPS[@]}"; do
    find "$REPO_ROOT/$group" -mindepth 2 -maxdepth 2 -name SKILL.md -print
  done | sort
}

main() {
  local exposed_skills=""
  local compatible_skills=""
  local group
  local plugin_name
  local skill_path
  local skill_dir
  local skill_md
  local relative_skill_dir

  require_jq
  validate_catalog_shape

  if [ "$errors" -ne 0 ]; then
    exit 1
  fi

  while IFS=$'\t' read -r group plugin_name skill_path; do
    [ -n "$skill_path" ] || continue

    if [[ "$skill_path" != "$group/"* ]]; then
      error "Catalog plugin '$plugin_name' lists '$skill_path' outside its source group '$group'"
      continue
    fi

    skill_dir="$REPO_ROOT/$skill_path"

    if [ ! -d "$skill_dir" ]; then
      error "Catalog exposes missing skill directory: $skill_path"
      continue
    fi

    if [ ! -f "$skill_dir/SKILL.md" ]; then
      error "Catalog exposes '$skill_path' but SKILL.md is missing"
    fi

    if ! skill_has_codex_compatibility "$skill_dir"; then
      error "Catalog exposes '$skill_path' but compatibility does not include Codex"
    fi

    if [ ! -f "$skill_dir/agents/openai.yaml" ]; then
      error "Catalog exposes '$skill_path' but agents/openai.yaml is missing"
    fi

    exposed_skills=$(append_line "$exposed_skills" "$skill_path")
  done <<EOF
$(collect_exposed_skills)
EOF

  while IFS= read -r skill_md; do
    [ -n "$skill_md" ] || continue
    skill_dir=$(dirname "$skill_md")
    relative_skill_dir=${skill_dir#"$REPO_ROOT"/}

    if skill_has_codex_compatibility "$skill_dir"; then
      compatible_skills=$(append_line "$compatible_skills" "$relative_skill_dir")

      if [ ! -f "$skill_dir/agents/openai.yaml" ]; then
        error "Codex-compatible skill '$relative_skill_dir' is missing agents/openai.yaml"
      fi

      if ! list_contains "$exposed_skills" "$relative_skill_dir"; then
        error "Codex-compatible skill '$relative_skill_dir' is not listed in $CATALOG_PATH"
      fi
    fi
  done <<EOF
$(collect_source_skills)
EOF

  while IFS= read -r skill_path; do
    [ -n "$skill_path" ] || continue
    if ! list_contains "$compatible_skills" "$skill_path"; then
      error "Catalog exposes '$skill_path' but the skill is not marked Codex-compatible"
    fi
  done <<EOF
$exposed_skills
EOF

  if [ "$errors" -ne 0 ]; then
    exit 1
  fi

  echo "Codex validation passed: $(printf '%s\n' "$compatible_skills" | awk 'NF {count++} END {print count + 0}') compatible skills match the Codex catalog."
}

main "$@"
