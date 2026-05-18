#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: editor-config.sh [--dry-run] [--yes] [--target <dir>] <editor> [<editor> ...]

Apply bundled editor configurations to a target repo. Existing files matching
the canonical set are deep-merged with our values winning every conflict;
files we do not define are left alone.

Editors:
  zed      Apply .zed/settings.json
  vscode   Apply .vscode/settings.json and .vscode/extensions.json

Flags:
  --dry-run         Show planned actions without writing
  --yes, -y         Skip the confirmation prompt
  --target <dir>    Target repo directory (default: current directory)
  -h, --help        Show this help

Exit codes:
  0  success (or dry-run)
  1  user aborted, or unrecoverable parse error
  2  bad arguments
  3  jq missing
EOF
}

# ---- Args ----
DRY_RUN=false
YES=false
TARGET=""
EDITORS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) YES=true; shift ;;
    --target)
      [[ $# -ge 2 ]] || { echo "--target needs a value" >&2; exit 2; }
      TARGET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) EDITORS+=("$1"); shift ;;
  esac
done

[[ ${#EDITORS[@]} -gt 0 ]] || { echo "No editors selected." >&2; usage >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)" >&2; exit 3; }

TARGET="${TARGET:-.}"
[[ -d "$TARGET" ]] || { echo "Target is not a directory: $TARGET" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPT_DIR")/assets"
[[ -d "$ASSETS_DIR" ]] || { echo "Bundled assets not found at $ASSETS_DIR" >&2; exit 1; }

KNOWN_EDITORS=(zed vscode)

is_known_editor() {
  local e="$1"
  for k in "${KNOWN_EDITORS[@]}"; do
    [[ "$k" == "$e" ]] && return 0
  done
  return 1
}

for e in "${EDITORS[@]}"; do
  is_known_editor "$e" || { echo "Unknown editor: $e (known: ${KNOWN_EDITORS[*]})" >&2; exit 2; }
done

# ---- Helpers ----

# Strip JSONC comments (// line, /* block */) so jq can parse the result.
# This is intentionally simple — it does not understand strings containing
# // or /*, but real-world settings files rarely have those.
strip_jsonc() {
  local file="$1"
  # Remove /* ... */ block comments (across lines), then // line comments.
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$file"
}

# Parse a JSONC file into normalised JSON. Echoes JSON on stdout; on parse
# failure, prints an error to stderr and returns 1.
parse_jsonc() {
  local file="$1"
  if jq '.' "$file" >/dev/null 2>&1; then
    jq '.' "$file"
    return 0
  fi
  local stripped
  stripped="$(strip_jsonc "$file")"
  if echo "$stripped" | jq '.' >/dev/null 2>&1; then
    echo "$stripped" | jq '.'
    return 0
  fi
  echo "Cannot parse JSON/JSONC: $file" >&2
  return 1
}

# Decide action for a single file. Echoes one of: Write | Merge | Identical
plan_action() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$dst" ]]; then
    echo "Write"
    return
  fi
  local current desired
  current="$(parse_jsonc "$dst")" || { echo "ParseError"; return; }
  desired="$(merge_one "$src" "$dst")" || { echo "ParseError"; return; }
  if [[ "$(echo "$current" | jq -S '.')" == "$(echo "$desired" | jq -S '.')" ]]; then
    echo "Identical"
  else
    echo "Merge"
  fi
}

# Produce the merged JSON for a single file. Behavior depends on basename:
#   extensions.json -> union recommendations + unwantedRecommendations arrays
#   settings.json   -> deep merge with ours winning (jq's * operator)
merge_one() {
  local src="$1"     # our bundled file (plain JSON)
  local dst="$2"     # target file in user's repo (JSONC, may not exist)
  local base
  base="$(basename "$src")"

  local ours theirs
  ours="$(jq '.' "$src")"

  if [[ ! -e "$dst" ]]; then
    echo "$ours"
    return 0
  fi

  theirs="$(parse_jsonc "$dst")" || return 1

  case "$base" in
    extensions.json)
      # Union recommendations + unwantedRecommendations; theirs first, ours
      # appended (de-duplicated). Other top-level keys: deep merge ours-win.
      jq -n \
        --argjson a "$theirs" \
        --argjson b "$ours" '
          ($a * $b) as $merged
          | $merged
            + (
                if ($a.recommendations // $b.recommendations) then
                  { recommendations:
                      ((($a.recommendations // []) + ($b.recommendations // []))
                       | unique_by(.))
                  }
                else {} end
              )
            + (
                if ($a.unwantedRecommendations // $b.unwantedRecommendations) then
                  { unwantedRecommendations:
                      ((($a.unwantedRecommendations // []) + ($b.unwantedRecommendations // []))
                       | unique_by(.))
                  }
                else {} end
              )
        '
      ;;
    *)
      # Deep merge, ours wins.
      jq -n \
        --argjson a "$theirs" \
        --argjson b "$ours" \
        '$a * $b'
      ;;
  esac
}

# ---- Editor manifests ----
# For each editor, define the file pairs as "src_relative_to_assets|dst_relative_to_target".

manifest_zed() {
  cat <<'EOF'
zed/settings.json|.zed/settings.json
EOF
}

manifest_vscode() {
  cat <<'EOF'
vscode/settings.json|.vscode/settings.json
vscode/extensions.json|.vscode/extensions.json
EOF
}

manifest_for() {
  case "$1" in
    zed) manifest_zed ;;
    vscode) manifest_vscode ;;
    *) echo "Unknown editor: $1" >&2; return 1 ;;
  esac
}

# ---- Plan ----

declare -a PLAN_SRC PLAN_DST PLAN_ACTION

for editor in "${EDITORS[@]}"; do
  while IFS='|' read -r rel_src rel_dst; do
    [[ -z "$rel_src" ]] && continue
    local_src="$ASSETS_DIR/$rel_src"
    local_dst="$TARGET/$rel_dst"
    [[ -f "$local_src" ]] || { echo "Bundled asset missing: $local_src" >&2; exit 1; }
    action="$(plan_action "$local_src" "$local_dst")"
    PLAN_SRC+=("$local_src")
    PLAN_DST+=("$local_dst")
    PLAN_ACTION+=("$action")
  done < <(manifest_for "$editor")
done

echo "Target: $TARGET"
echo "Editors: ${EDITORS[*]}"
echo
printf '%-9s  %s\n' "Action" "File"
printf '%-9s  %s\n' "------" "----"
for i in "${!PLAN_DST[@]}"; do
  rel="${PLAN_DST[$i]#$TARGET/}"
  printf '%-9s  %s\n' "${PLAN_ACTION[$i]}" "$rel"
done
echo

# Bail out on parse errors before asking to apply.
for action in "${PLAN_ACTION[@]}"; do
  if [[ "$action" == "ParseError" ]]; then
    echo "Cannot apply: one or more target files failed to parse. Fix and re-run." >&2
    exit 1
  fi
done

if $DRY_RUN; then
  echo "(dry-run; no files written)"
  exit 0
fi

# Skip if everything is Identical.
needs_work=false
for action in "${PLAN_ACTION[@]}"; do
  if [[ "$action" != "Identical" ]]; then needs_work=true; break; fi
done
if ! $needs_work; then
  echo "Nothing to do — all targets already match."
  exit 0
fi

if ! $YES; then
  read -r -p "Apply these changes? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) : ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# ---- Apply ----

for i in "${!PLAN_DST[@]}"; do
  action="${PLAN_ACTION[$i]}"
  src="${PLAN_SRC[$i]}"
  dst="${PLAN_DST[$i]}"
  [[ "$action" == "Identical" ]] && continue

  mkdir -p "$(dirname "$dst")"
  if [[ "$action" == "Write" ]]; then
    cp "$src" "$dst"
  else
    merged="$(merge_one "$src" "$dst")"
    # Write pretty-printed JSON (2-space indent, trailing newline).
    printf '%s\n' "$merged" | jq '.' >"$dst"
  fi
done

echo "Done. Changed files:"
for i in "${!PLAN_DST[@]}"; do
  action="${PLAN_ACTION[$i]}"
  [[ "$action" == "Identical" ]] && continue
  rel="${PLAN_DST[$i]#$TARGET/}"
  echo "  $rel"
done
