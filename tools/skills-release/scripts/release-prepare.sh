#!/bin/bash

# Release Preparation Script
# Validates git status, branch, config files, and version consistency
# For use with the skills-release skill

set -e

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Branch: $CURRENT_BRANCH"

# Check if we're on master or main
if [[ "$CURRENT_BRANCH" != "master" ]] && [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "ERROR: Not on master or main branch"
  exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
  echo "ERROR: Uncommitted changes detected"
  git status --short
  exit 1
fi

# Compare with origin before anything below writes to the tree. Behind would
# only fail at the push, after the release commit and tag exist; ahead would
# ship commits nobody has seen on the remote.
ALLOW_UNPUSHED=false
case "${1:-}" in
  "") ;;
  --allow-unpushed) ALLOW_UNPUSHED=true ;;
  *) echo "ERROR: Unknown argument: $1 (the only option is --allow-unpushed)"; exit 1 ;;
esac

if ! git fetch --quiet origin "$CURRENT_BRANCH"; then
  echo "ERROR: Could not fetch origin/$CURRENT_BRANCH. Check the remote and network, then re-run"
  exit 1
fi

UPSTREAM="refs/remotes/origin/$CURRENT_BRANCH"
if ! git rev-parse --verify --quiet "$UPSTREAM" > /dev/null; then
  echo "ERROR: origin/$CURRENT_BRANCH does not exist"
  exit 1
fi

BEHIND=$(git rev-list --count "HEAD..$UPSTREAM")
if [[ "$BEHIND" -gt 0 ]]; then
  echo "ERROR: $CURRENT_BRANCH is $BEHIND commit(s) behind origin/$CURRENT_BRANCH. Pull first, then re-run"
  git log --oneline "HEAD..$UPSTREAM"
  exit 1
fi

AHEAD=$(git rev-list --count "$UPSTREAM..HEAD")
if [[ "$AHEAD" -gt 0 ]]; then
  echo "Local-only commits ($AHEAD), not on origin/$CURRENT_BRANCH:"
  git log --oneline "$UPSTREAM..HEAD"
  if [[ "$ALLOW_UNPUSHED" != true ]]; then
    echo "STOP: these commits would ship in the release. Re-run with --allow-unpushed once the user approves including them"
    exit 2
  fi
  echo "Including them: --allow-unpushed was passed"
fi

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

# Validate skill registries before checking versions
echo "Validating skill registries..."
bash .github/scripts/validate-skills.sh
./scripts/validate-codex.sh

# Verify generated Codex wrapper files are in sync
echo "Checking generated Codex wrapper files..."
./scripts/skills-packaging.sh sync-repo

if [[ -n $(git status --porcelain) ]]; then
  echo "ERROR: Uncommitted or unsynced changes detected after Codex sync"
  echo "Run ./scripts/skills-packaging.sh sync-repo and commit the generated changes before releasing"
  git status --short
  exit 1
fi

# Verify marketplace.json exists
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CODEX_CATALOG="scripts/codex/catalog.json"
PACKAGE_JSON="package.json"

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

if [[ ! -f "$CODEX_CATALOG" ]]; then
  echo "ERROR: $CODEX_CATALOG not found"
  exit 1
fi

if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "ERROR: $PACKAGE_JSON not found"
  exit 1
fi

# Discover plugins from marketplace.json
PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")

if [[ "$PLUGIN_COUNT" -eq 0 ]]; then
  echo "ERROR: No plugins found in $MARKETPLACE_JSON"
  exit 1
fi

echo "Plugins: $PLUGIN_COUNT"

# Collect all versions and check consistency
VERSIONS=()

for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE_JSON")
  plugin_json="$source/.claude-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "ERROR: $plugin_json not found"
    exit 1
  fi

  pj_version=$(jq -r '.version' "$plugin_json")

  echo "Plugin '$name': marketplace=$mp_version, plugin.json=$pj_version"
  VERSIONS+=("$mp_version" "$pj_version")
done

CODEX_VERSION=$(jq -r '.version' "$CODEX_CATALOG")
echo "Codex catalog: $CODEX_VERSION"
VERSIONS+=("$CODEX_VERSION")

PACKAGE_VERSION=$(jq -r '.version' "$PACKAGE_JSON")
echo "pi package: $PACKAGE_VERSION"
VERSIONS+=("$PACKAGE_VERSION")

while IFS= read -r plugin_name; do
  [[ -n "$plugin_name" ]] || continue
  plugin_json="plugins/$plugin_name/.codex-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "ERROR: $plugin_json not found"
    exit 1
  fi

  pj_version=$(jq -r '.version' "$plugin_json")
  echo "Codex plugin '$plugin_name': $pj_version"
  VERSIONS+=("$pj_version")
done <<EOF
$(jq -r '.plugins[].name' "$CODEX_CATALOG")
EOF

# Check all versions match
FIRST="${VERSIONS[0]}"
for v in "${VERSIONS[@]}"; do
  if [[ "$v" != "$FIRST" ]]; then
    echo "WARNING: Version mismatch detected across config files"
    exit 1
  fi
done

echo ""
echo "Version: $FIRST"
echo ""
echo "SUCCESS: All pre-flight checks passed"
