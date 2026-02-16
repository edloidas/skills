#!/usr/bin/env bash
set -euo pipefail

# Validate that each plugin's source directory contains a plugin.json and that
# all SKILL.md directories inside it are discoverable (auto-discovery via "skills": "./").

MARKETPLACE=".claude-plugin/marketplace.json"

if [ ! -f "$MARKETPLACE" ]; then
  echo "::error::$MARKETPLACE not found"
  exit 1
fi

errors=0
total_skills=0

# Iterate over each plugin entry in marketplace.json
plugin_count=$(jq '.plugins | length' "$MARKETPLACE")

for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE" | sed 's|^\./||')

  if [ ! -d "$source" ]; then
    echo "::error::Plugin '$name': source directory '$source' does not exist"
    errors=1
    continue
  fi

  if [ ! -f "$source/.claude-plugin/plugin.json" ]; then
    echo "::error::Plugin '$name': missing .claude-plugin/plugin.json in '$source/'"
    errors=1
  fi

  # Find all SKILL.md files inside the plugin source directory
  skill_count=0
  for skill_dir in "$source"/*/SKILL.md; do
    [ -f "$skill_dir" ] || continue
    skill_count=$((skill_count + 1))
  done

  if [ "$skill_count" -eq 0 ]; then
    echo "::error::Plugin '$name': no skills found in '$source/'"
    errors=1
  else
    echo "Plugin '$name': $skill_count skills found in '$source/'"
    total_skills=$((total_skills + skill_count))
  fi
done

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "All plugins valid. $total_skills skills across $plugin_count plugins."
