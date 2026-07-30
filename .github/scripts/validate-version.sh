#!/usr/bin/env bash
set -euo pipefail

# Validate that all plugin.json and marketplace.json versions match the given tag version.
# Usage: validate-version.sh <version>
#   e.g. validate-version.sh 1.3.0

TAG_VERSION="${1:?Usage: validate-version.sh <version>}"
MARKETPLACE=".claude-plugin/marketplace.json"
CODEX_CATALOG="scripts/codex/catalog.json"
PACKAGE_JSON="package.json"

echo "Tag version: $TAG_VERSION"

errors=0

# Check each marketplace plugin entry
plugin_count=$(jq '.plugins | length' "$MARKETPLACE")

for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")

  echo "Marketplace '$name': $mp_version"

  if [ "$TAG_VERSION" != "$mp_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match marketplace.json plugin '$name' ($mp_version)"
    errors=1
  fi
done

# Check each plugin.json
for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"

  if [ ! -f "$plugin_json" ]; then
    echo "::error::Plugin '$name': $plugin_json not found"
    errors=1
    continue
  fi

  pj_version=$(jq -r '.version' "$plugin_json")
  echo "Plugin '$name' ($plugin_json): $pj_version"

  if [ "$TAG_VERSION" != "$pj_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match $plugin_json ($pj_version)"
    errors=1
  fi
done

# Check Codex catalog version
if [ ! -f "$CODEX_CATALOG" ]; then
  echo "::error::$CODEX_CATALOG not found"
  errors=1
else
  codex_catalog_version=$(jq -r '.version' "$CODEX_CATALOG")
  echo "Codex catalog ($CODEX_CATALOG): $codex_catalog_version"

  if [ "$TAG_VERSION" != "$codex_catalog_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match $CODEX_CATALOG ($codex_catalog_version)"
    errors=1
  fi
fi

# Check generated Codex plugin manifests
if [ -f "$CODEX_CATALOG" ]; then
  while IFS= read -r plugin_name; do
    [ -n "$plugin_name" ] || continue
    plugin_json="plugins/$plugin_name/.codex-plugin/plugin.json"

    if [ ! -f "$plugin_json" ]; then
      echo "::error::Codex plugin '$plugin_name': $plugin_json not found"
      errors=1
      continue
    fi

    pj_version=$(jq -r '.version' "$plugin_json")
    echo "Codex plugin '$plugin_name' ($plugin_json): $pj_version"

    if [ "$TAG_VERSION" != "$pj_version" ]; then
      echo "::error::Tag version ($TAG_VERSION) does not match $plugin_json ($pj_version)"
      errors=1
    fi
  done <<EOF
$(jq -r '.plugins[].name' "$CODEX_CATALOG")
EOF
fi

# Check the pi package manifest — pi reads the version from package.json, so it is a
# release file like every plugin.json and must not drift from the tag.
if [ ! -f "$PACKAGE_JSON" ]; then
  echo "::error::$PACKAGE_JSON not found"
  errors=1
else
  pkg_version=$(jq -r '.version' "$PACKAGE_JSON")
  echo "pi package ($PACKAGE_JSON): $pkg_version"

  if [ "$TAG_VERSION" != "$pkg_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match $PACKAGE_JSON ($pkg_version)"
    errors=1
  fi
fi

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "All versions match: $TAG_VERSION"
