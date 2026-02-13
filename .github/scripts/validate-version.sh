#!/usr/bin/env bash
set -euo pipefail

# Validate that plugin.json and marketplace.json versions match the given tag version.
# Usage: validate-version.sh <version>
#   e.g. validate-version.sh 1.2.0

TAG_VERSION="${1:?Usage: validate-version.sh <version>}"

MARKETPLACE_VERSION=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
PLUGIN_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)

echo "Tag version:         $TAG_VERSION"
echo "Marketplace version: $MARKETPLACE_VERSION"
echo "Plugin version:      $PLUGIN_VERSION"

errors=0

if [ "$TAG_VERSION" != "$MARKETPLACE_VERSION" ]; then
  echo "::error::Tag version ($TAG_VERSION) does not match marketplace.json ($MARKETPLACE_VERSION)"
  errors=1
fi

if [ "$TAG_VERSION" != "$PLUGIN_VERSION" ]; then
  echo "::error::Tag version ($TAG_VERSION) does not match plugin.json ($PLUGIN_VERSION)"
  errors=1
fi

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "All versions match: $TAG_VERSION"
