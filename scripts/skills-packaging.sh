#!/usr/bin/env bash

# Packaging for every host this collection ships to.
#
# `sync-repo` generates all of the distribution layers from two sources of truth:
#   - scripts/codex/catalog.json   Codex wrapper plugins (names, metadata, grouping)
#   - `compatibility:` frontmatter  which hosts each skill declares support for
#
# Outputs: .agents/plugins/marketplace.json, plugins/<name>/{.codex-plugin,skills}/,
# .agents/skills/, .opencode/skills/, .pi/skills/. All generated — never hand-edited.
#
# `install-host` installs one host's set into that host's global skill directory.
#
# Contract validation lives elsewhere: .github/scripts/validate-skills.sh (Claude
# marketplace + canonical layout), .github/scripts/validate-discovery.sh (what each host
# actually resolves), and scripts/validate-codex.sh — which despite its name also enforces
# the cross-host rule that the Codex set must be a subset of every other host's set.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
CATALOG_PATH="$SCRIPT_DIR/codex/catalog.json"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

require_catalog() {
  [ -f "$CATALOG_PATH" ] || die "Catalog not found: $CATALOG_PATH"
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

catalog_jq() {
  jq -er "$1" "$CATALOG_PATH"
}

catalog_jq_raw() {
  jq -r "$1" "$CATALOG_PATH"
}

catalog_plugin_groups() {
  catalog_jq_raw '.plugins[].group'
}

catalog_plugin_field() {
  local group="$1"
  local field="$2"
  jq -er --arg group "$group" ".plugins[] | select(.group == \$group) | .$field" "$CATALOG_PATH"
}

catalog_branding_field() {
  local field="$1"
  jq -er ".pluginBranding.$field" "$CATALOG_PATH"
}

catalog_plugin_manifest_json() {
  local group="$1"
  jq -n \
    --slurpfile catalog "$CATALOG_PATH" \
    --arg group "$group" \
    '
      ($catalog[0]) as $catalog |
      ($catalog.plugins[] | select(.group == $group)) as $plugin |
      {
        name: $plugin.name,
        version: $catalog.version,
        description: $plugin.description,
        author: $catalog.author,
        homepage: $catalog.repository,
        repository: $catalog.repository,
        license: $catalog.license,
        keywords: $plugin.keywords,
        skills: "./skills/",
        interface: {
          displayName: $plugin.displayName,
          shortDescription: $plugin.shortDescription,
          longDescription: $plugin.longDescription,
          developerName: $catalog.author.name,
          category: $plugin.category,
          websiteURL: $plugin.websiteURL,
          brandColor: $catalog.pluginBranding.brandColor,
          composerIcon: $catalog.pluginBranding.composerIcon,
          logo: $catalog.pluginBranding.logo
        }
      }
    '
}

catalog_plugin_skills() {
  local group="$1"
  jq -r --arg group "$group" '.plugins[] | select(.group == $group) | .skills[]' "$CATALOG_PATH"
}

catalog_marketplace_manifest_json() {
  jq '
    {
      name: .marketplace.name,
      interface: {
        displayName: .marketplace.displayName
      },
      plugins: [
        .plugins[] |
        {
          name: .name,
          source: {
            source: "local",
            path: ("./plugins/" + .name)
          },
          policy: {
            installation: "AVAILABLE",
            authentication: "ON_INSTALL"
          },
          category: .category
        }
      ]
    }
  ' "$CATALOG_PATH"
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

ensure_dir() {
  mkdir -p "$1"
}

ensure_symlink() {
  local target="$1"
  local destination="$2"
  ensure_dir "$(dirname "$destination")"
  if [ -L "$destination" ]; then
    if [ "$(readlink "$destination")" = "$target" ]; then
      return
    fi
    unlink "$destination"
  elif [ -e "$destination" ]; then
    die "Refusing to replace non-symlink path: $destination"
  fi
  ln -s "$target" "$destination"
}

remove_stale_entries() {
  local directory="$1"
  local keep_names="$2"
  local entry
  local name

  [ -d "$directory" ] || return

  for entry in "$directory"/* "$directory"/.*; do
    case "$entry" in
      "$directory/*" | "$directory/.*" | "$directory/." | "$directory/..")
        continue
        ;;
    esac

    name=$(basename "$entry")
    if list_contains "$keep_names" "$name"; then
      continue
    fi

    if [ -L "$entry" ]; then
      unlink "$entry"
    elif [ -d "$entry" ] && [ -z "$(find "$entry" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
      rmdir "$entry"
    else
      die "Refusing to remove unexpected non-symlink path: $entry"
    fi
  done
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

validate_skill() {
  local skill_dir="$1"
  [ -d "$skill_dir" ] || die "Skill directory not found: $skill_dir"
  [ -f "$skill_dir/SKILL.md" ] || die "SKILL.md not found in $skill_dir"
  [ -f "$skill_dir/agents/openai.yaml" ] || die "agents/openai.yaml missing in $skill_dir"
  if ! read_frontmatter "$skill_dir" | grep -q 'Codex'; then
    die "Codex compatibility missing in $skill_dir/SKILL.md"
  fi
}

# Hosts that get their own generated skill tree, and where that tree lives.
#
# .agents/skills/ deliberately stays the Codex-vetted set only: Codex, OpenCode, and pi
# all read it, so putting an OpenCode-only skill there would expose it to Codex too.
# Each other host reads its own directory in addition to .agents/skills/, so the set a
# host actually sees is its own tree unioned with the Codex tree — which is why
# validate-codex.sh requires the Codex set to be a subset of every other host's set.
HOST_NAMES=(opencode pi)

host_repo_dir() {
  case "$1" in
    opencode) printf '.opencode/skills' ;;
    pi) printf '.pi/skills' ;;
    codex) printf '.agents/skills' ;;
    *) die "Unknown host: $1" ;;
  esac
}

host_global_dir() {
  case "$1" in
    opencode) printf '%s/.config/opencode/skills' "$HOME" ;;
    pi) printf '%s/.pi/agent/skills' "$HOME" ;;
    codex) printf '%s/.agents/skills' "$HOME" ;;
    *) die "Unknown host: $1" ;;
  esac
}

# The `compatibility:` frontmatter field is the single source of truth for host support.
# Matching is on a comma-separated token so "Codex" cannot match "OpenCode" by substring.
host_label() {
  case "$1" in
    opencode) printf 'OpenCode' ;;
    pi) printf 'Pi' ;;
    codex) printf 'Codex' ;;
    *) die "Unknown host: $1" ;;
  esac
}

skill_supports_host() {
  local skill_dir="$1"
  local label
  label=$(host_label "$2")
  read_frontmatter "$skill_dir" | awk -v label="$label" '
    /^compatibility:/ {
      sub(/^compatibility: */, "")
      n = split($0, parts, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
        if (parts[i] == label) { found = 1 }
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

# Every canonical skill directory, as repo-relative paths.
all_skill_dirs() {
  local group
  for group in plan build review audit maintain ship assist obsidian workflow; do
    find "$REPO_ROOT/$group/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -print 2>/dev/null |
      sed -e "s#^$REPO_ROOT/##" -e 's#/SKILL\.md$##'
  done | sort
}

# Materialize <host>/skills as symlinks into the canonical <group>/skills/<name> dirs.
# Claude Code, Codex, OpenCode, and pi all resolve symlinks, so only the canonical
# directory needs to be real.
sync_host_tree() {
  local host="$1"
  local dir depth prefix keep_names="" skill_path skill_name

  dir="$REPO_ROOT/$(host_repo_dir "$host")"
  ensure_dir "$dir"

  # Symlink targets resolve from the directory holding the link, so ".opencode/skills"
  # (two components) needs two "../" hops to reach the repo root.
  depth=$(host_repo_dir "$host" | awk -F/ '{print NF}')
  prefix=$(printf '../%.0s' $(seq 1 "$depth"))

  while IFS= read -r skill_path; do
    [ -n "$skill_path" ] || continue
    skill_supports_host "$REPO_ROOT/$skill_path" "$host" || continue
    skill_name=${skill_path##*/}
    keep_names=$(append_line "$keep_names" "$skill_name")
    ensure_symlink "${prefix}${skill_path}" "$dir/$skill_name"
  done <<EOF
$(all_skill_dirs)
EOF

  remove_stale_entries "$dir" "$keep_names"
  printf '%s' "$(printf '%s\n' "$keep_names" | awk 'NF')" >/dev/null
}

validate_catalog() {
  require_catalog
  catalog_jq '.version | strings | select(length > 0)' >/dev/null || die "Catalog version is required"
  catalog_jq '.marketplace.name | strings | select(length > 0)' >/dev/null || die "Marketplace name is required"
  catalog_jq '.marketplace.displayName | strings | select(length > 0)' >/dev/null || die "Marketplace displayName is required"
  catalog_jq '.author.name | strings | select(length > 0)' >/dev/null || die "Author name is required"
  catalog_jq '.author.url | strings | select(length > 0)' >/dev/null || die "Author URL is required"
  catalog_jq '.pluginBranding.brandColor | strings | test("^#[0-9A-Fa-f]{6}$")' >/dev/null || die "Shared plugin brandColor is required"
  catalog_jq '.pluginBranding.assetSource | strings | select(startswith("./"))' >/dev/null || die "Shared plugin assetSource must start with ./"
  catalog_jq '.pluginBranding.logo | strings | select(startswith("./assets/"))' >/dev/null || die "Shared plugin logo path must be under ./assets/"
  catalog_jq '.pluginBranding.composerIcon | strings | select(startswith("./assets/"))' >/dev/null || die "Shared plugin composerIcon path must be under ./assets/"
  catalog_jq '.repository | strings | select(length > 0)' >/dev/null || die "Repository URL is required"
  catalog_jq '.license | strings | select(length > 0)' >/dev/null || die "License is required"

  catalog_jq '([.plugins[].group] | length) == ([.plugins[].group] | unique | length)' >/dev/null || die "Duplicate plugin group in catalog"
  catalog_jq '([.plugins[].name] | length) == ([.plugins[].name] | unique | length)' >/dev/null || die "Duplicate plugin name in catalog"
  catalog_jq '([.plugins[].skills[] | split("/")[-1]] | length) == ([.plugins[].skills[] | split("/")[-1]] | unique | length)' >/dev/null || die "Duplicate exposed skill name across Codex plugins"
  catalog_jq '.plugins | length > 0' >/dev/null || die "Catalog must define at least one plugin"
  catalog_jq 'all(.plugins[]; (.group | strings | length > 0) and (.name | strings | length > 0) and (.displayName | strings | length > 0) and (.description | strings | length > 0) and (.shortDescription | strings | length > 0) and (.longDescription | strings | length > 0) and (.category | strings | length > 0) and (.websiteURL | strings | length > 0) and (.keywords | type == "array" and length > 0) and (.skills | type == "array" and length > 0))' >/dev/null || die "Each plugin must define complete metadata, keywords, and skills"
}

sync_plugin_branding_assets() {
  local plugin_name="$1"
  local plugin_root="$REPO_ROOT/plugins/$plugin_name"
  local asset_source
  local logo_path
  local composer_icon_path

  asset_source=$(catalog_branding_field 'assetSource')
  logo_path=$(catalog_branding_field 'logo')
  composer_icon_path=$(catalog_branding_field 'composerIcon')

  [ -f "$REPO_ROOT/${asset_source#./}" ] || die "Shared plugin asset not found: $asset_source"

  case "$logo_path" in
    ./assets/*) ;;
    *) die "Shared plugin logo path must stay under ./assets/: $logo_path" ;;
  esac

  case "$composer_icon_path" in
    ./assets/*) ;;
    *) die "Shared plugin composerIcon path must stay under ./assets/: $composer_icon_path" ;;
  esac

  ensure_symlink "../../../${asset_source#./}" "$plugin_root/${logo_path#./}"
  ensure_symlink "../../../${asset_source#./}" "$plugin_root/${composer_icon_path#./}"
}

write_json_file() {
  local path="$1"
  local content="$2"
  local tmp_path

  ensure_dir "$(dirname "$path")"
  tmp_path="${path}.tmp"
  printf '%s\n' "$content" > "$tmp_path"
  mv "$tmp_path" "$path"
}

write_plugin_manifest() {
  local group="$1"
  local plugin_name
  local manifest_path

  plugin_name=$(catalog_plugin_field "$group" 'name')
  manifest_path="$REPO_ROOT/plugins/$plugin_name/.codex-plugin/plugin.json"
  write_json_file "$manifest_path" "$(catalog_plugin_manifest_json "$group")"
}

write_marketplace_manifest() {
  write_json_file "$REPO_ROOT/.agents/plugins/marketplace.json" "$(catalog_marketplace_manifest_json)"
}

sync_repo() {
  local group
  local plugin_name
  local plugin_skills_dir
  local repo_keep_names=""
  local plugin_keep_names
  local skill_path
  local skill_name

  require_jq
  validate_catalog
  ensure_dir "$REPO_ROOT/.agents/skills"

  while IFS= read -r group; do
    [ -n "$group" ] || continue
    plugin_name=$(catalog_plugin_field "$group" 'name')
    plugin_skills_dir="$REPO_ROOT/plugins/$plugin_name/skills"

    write_plugin_manifest "$group"
    sync_plugin_branding_assets "$plugin_name"
    plugin_keep_names=""

    while IFS= read -r skill_path; do
      [ -n "$skill_path" ] || continue
      validate_skill "$REPO_ROOT/$skill_path"
      skill_name=${skill_path##*/}

      plugin_keep_names=$(append_line "$plugin_keep_names" "$skill_name")
      if ! list_contains "$repo_keep_names" "$skill_name"; then
        repo_keep_names=$(append_line "$repo_keep_names" "$skill_name")
      fi

      ensure_symlink "../../../$skill_path" "$plugin_skills_dir/$skill_name"
      ensure_symlink "../../$skill_path" "$REPO_ROOT/.agents/skills/$skill_name"
    done <<EOF
$(catalog_plugin_skills "$group")
EOF

    remove_stale_entries "$plugin_skills_dir" "$plugin_keep_names"
  done <<EOF
$(catalog_plugin_groups)
EOF

  remove_stale_entries "$REPO_ROOT/.agents/skills" "$repo_keep_names"
  write_marketplace_manifest

  # Per-host trees for the hosts that read their own directory rather than .agents/skills.
  local host
  for host in "${HOST_NAMES[@]}"; do
    sync_host_tree "$host"
  done
}

group_requested() {
  local target="$1"
  shift
  local group
  for group in "$@"; do
    [ "$group" = "$target" ] && return 0
  done
  return 1
}

validate_requested_groups() {
  local requested_group
  local known_groups=""

  known_groups=$(catalog_plugin_groups)

  for requested_group in "$@"; do
    if [ "$requested_group" = "all" ]; then
      continue
    fi
    list_contains "$known_groups" "$requested_group" || die "Unknown group name(s): $requested_group"
  done
}

# Install every skill that declares support for one host into that host's global skill
# directory. Unlike install_links, this is driven by `compatibility:` frontmatter rather
# than the Codex catalog, so OpenCode and pi are no longer limited to the Codex subset.
install_host() {
  local host=""
  local destination=""
  local skill_path skill_name keep_names="" count=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dest)
        [ "$#" -ge 2 ] || die "--dest requires a path"
        destination="$2"
        shift 2
        ;;
      --prune)
        shift
        ;;
      *)
        [ -z "$host" ] || die "install-host takes exactly one host name"
        host="$1"
        shift
        ;;
    esac
  done

  [ -n "$host" ] || die "A host name is required (one of: codex opencode pi)"
  case "$host" in
    codex | opencode | pi) ;;
    *) die "Unknown host '$host' (expected one of: codex opencode pi)" ;;
  esac

  [ -n "$destination" ] || destination=$(host_global_dir "$host")
  ensure_dir "$destination"

  while IFS= read -r skill_path; do
    [ -n "$skill_path" ] || continue
    skill_supports_host "$REPO_ROOT/$skill_path" "$host" || continue
    skill_name=${skill_path##*/}
    keep_names=$(append_line "$keep_names" "$skill_name")
    ensure_symlink "$REPO_ROOT/$skill_path" "$destination/$skill_name"
    count=$((count + 1))
  done <<EOF
$(all_skill_dirs)
EOF

  # Only prune links this repo owns, so unrelated skills in a shared directory survive.
  local entry name target
  for entry in "$destination"/*; do
    [ -L "$entry" ] || continue
    target=$(readlink "$entry")
    case "$target" in "$REPO_ROOT"/*) ;; *) continue ;; esac
    name=$(basename "$entry")
    list_contains "$keep_names" "$name" && continue
    unlink "$entry"
    echo "Removed stale link: $name"
  done

  echo "Installed $count $(host_label "$host") skills into $destination"
}

install_links() {
  local destination="${HOME}/.agents/skills"
  local requested_groups=()
  local group
  local skill_path
  local skill_name

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dest)
        [ "$#" -ge 2 ] || die "--dest requires a path"
        destination="$2"
        shift 2
        ;;
      *)
        requested_groups+=("$1")
        shift
        ;;
    esac
  done

  [ "${#requested_groups[@]}" -gt 0 ] || die "At least one group name or 'all' is required"

  require_jq
  validate_catalog
  validate_requested_groups "${requested_groups[@]}"
  ensure_dir "$destination"

  if group_requested "all" "${requested_groups[@]}"; then
    requested_groups=()
    while IFS= read -r group; do
      [ -n "$group" ] || continue
      requested_groups+=("$group")
    done <<EOF
$(catalog_plugin_groups)
EOF
  fi

  while IFS= read -r group; do
    [ -n "$group" ] || continue
    if ! group_requested "$group" "${requested_groups[@]}"; then
      continue
    fi

    while IFS= read -r skill_path; do
      [ -n "$skill_path" ] || continue
      validate_skill "$REPO_ROOT/$skill_path"
      skill_name=${skill_path##*/}
      ensure_symlink "$REPO_ROOT/$skill_path" "$destination/$skill_name"
    done <<EOF
$(catalog_plugin_skills "$group")
EOF
  done <<EOF
$(catalog_plugin_groups)
EOF
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/skills-packaging.sh sync-repo
  ./scripts/skills-packaging.sh install-host [--dest PATH] <codex|opencode|pi>
  ./scripts/skills-packaging.sh install-links [--dest PATH] <group> [group...]

Commands:
  sync-repo      Regenerate the repo-local Codex marketplace, wrapper plugins, and the
                 per-host skill trees (.agents/skills, .opencode/skills, .pi/skills).
  install-host   Install every skill that declares support for one host into that host's
                 global skill directory. Driven by `compatibility:` frontmatter, so it is
                 not limited to the Codex subset. Prunes only links owned by this repo.
  install-links  Install one or more Codex skill groups into another skills directory.
                 Codex-catalog driven; prefer install-host.

Default destinations for install-host:
  codex     ~/.agents/skills
  opencode  ~/.config/opencode/skills
  pi        ~/.pi/agent/skills

Examples:
  ./scripts/skills-packaging.sh sync-repo
  ./scripts/skills-packaging.sh install-host opencode
  ./scripts/skills-packaging.sh install-host pi --dest "$HOME/.agents/skills"
  ./scripts/skills-packaging.sh install-links review build
EOF
}

main() {
  local command="${1:-}"
  case "$command" in
    sync-repo)
      shift
      [ "$#" -eq 0 ] || die "sync-repo does not accept extra arguments"
      sync_repo
      ;;
    install-host)
      shift
      require_jq
      install_host "$@"
      ;;
    install-links)
      shift
      install_links "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    "")
      usage
      exit 1
      ;;
    *)
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
