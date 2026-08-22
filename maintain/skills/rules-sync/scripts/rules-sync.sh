#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: rules-sync.sh [--dry-run] [--yes] [<target-dir>]

Sync canonical agent rule files into a target repo's .claude/rules/ or
.agents/rules/. Existing files matching the canonical set are overwritten.
Missing canonical files are added only when the project actually uses the
relevant technology. Files outside the canonical set are preserved.

  --dry-run    Show planned actions without writing
  --yes, -y    Skip confirmation prompt
  --no-init    Refuse to create rules dir when neither side exists
  -h, --help   Show this help
  <target>     Target repo directory (default: current directory)

Exit codes:
  0  success (or dry-run)
  1  user aborted, or nothing to do but flagged
  2  bad arguments
  3  ambiguous storage state (both .claude/rules and .agents/rules are real,
     independent directories with different contents)
EOF
}

# ---- Args ----
DRY_RUN=false
YES=false
NO_INIT=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y) YES=true ;;
    --no-init) NO_INIT=true ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown flag: $arg" >&2; usage >&2; exit 2 ;;
    *)  if [[ -n "$TARGET" ]]; then echo "Multiple target dirs given" >&2; exit 2; fi
        TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-.}"
[[ -d "$TARGET" ]] || { echo "Target is not a directory: $TARGET" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SOURCE="$(dirname "$SCRIPT_DIR")/assets/rules"
[[ -d "$RULES_SOURCE" ]] || { echo "Canonical rules not found at $RULES_SOURCE" >&2; exit 1; }

# Canonical rule set — the eight files we manage.
RULE_FILES=(comments.md frontend-structure.md kotlin.md radix.md react.md storybook.md tailwind.md testing.md typescript.md)

# ---- Storage detection ----
CLAUDE_RULES="$TARGET/.claude/rules"
AGENTS_RULES="$TARGET/.agents/rules"

claude_exists=false; claude_is_symlink=false; claude_real=""
agents_exists=false; agents_is_symlink=false; agents_real=""

if [[ -L "$CLAUDE_RULES" ]]; then
  claude_exists=true; claude_is_symlink=true
  claude_real="$(cd "$CLAUDE_RULES" 2>/dev/null && pwd -P || true)"
elif [[ -d "$CLAUDE_RULES" ]]; then
  claude_exists=true
  claude_real="$(cd "$CLAUDE_RULES" && pwd -P)"
fi

if [[ -L "$AGENTS_RULES" ]]; then
  agents_exists=true; agents_is_symlink=true
  agents_real="$(cd "$AGENTS_RULES" 2>/dev/null && pwd -P || true)"
elif [[ -d "$AGENTS_RULES" ]]; then
  agents_exists=true
  agents_real="$(cd "$AGENTS_RULES" && pwd -P)"
fi

INIT_MODE=false
RULES_DIR=""

if ! $claude_exists && ! $agents_exists; then
  INIT_MODE=true
  RULES_DIR="$CLAUDE_RULES"
elif $claude_exists && $agents_exists; then
  if $claude_is_symlink && ! $agents_is_symlink; then
    RULES_DIR="$AGENTS_RULES"
  elif $agents_is_symlink && ! $claude_is_symlink; then
    RULES_DIR="$CLAUDE_RULES"
  elif $claude_is_symlink && $agents_is_symlink; then
    # Both symlinks; if they resolve to the same path, write through .claude side.
    if [[ -n "$claude_real" && "$claude_real" = "$agents_real" ]]; then
      RULES_DIR="$claude_real"
    else
      echo "Both .claude/rules and .agents/rules are symlinks to different targets:" >&2
      echo "  .claude/rules -> $claude_real" >&2
      echo "  .agents/rules -> $agents_real" >&2
      exit 3
    fi
  else
    # Both real directories.
    if [[ "$claude_real" = "$agents_real" ]]; then
      RULES_DIR="$CLAUDE_RULES"
    else
      # Compare contents — if identical, treat .claude/rules as canonical.
      if diff -rq "$claude_real" "$agents_real" >/dev/null 2>&1; then
        RULES_DIR="$CLAUDE_RULES"
        echo "Note: .claude/rules and .agents/rules are independent dirs with identical content; using .claude/rules." >&2
      else
        echo "Both .claude/rules and .agents/rules are real, independent directories with differing content." >&2
        echo "  .claude/rules: $claude_real" >&2
        echo "  .agents/rules: $agents_real" >&2
        echo "Pick one as the canonical, replace the other with a symlink, then re-run." >&2
        exit 3
      fi
    fi
  fi
elif $claude_exists; then
  RULES_DIR="$CLAUDE_RULES"
else
  RULES_DIR="$AGENTS_RULES"
fi

if $INIT_MODE && $NO_INIT; then
  echo "No rules directory exists and --no-init was passed." >&2
  exit 1
fi

# ---- Stack detection ----
PKG_JSON="$TARGET/package.json"
TSCONFIG="$TARGET/tsconfig.json"
STORYBOOK_DIR="$TARGET/.storybook"

has_dep() {
  local pat="$1"
  [[ -f "$PKG_JSON" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg pat "$pat" '
    ((.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {}) + (.optionalDependencies // {}))
    | to_entries
    | map(select(.key | test($pat)))
    | length > 0
  ' "$PKG_JSON" >/dev/null 2>&1
}

uses_typescript() { [[ -f "$TSCONFIG" ]] || has_dep '^typescript$'; }
uses_react()      { has_dep '^react$'; }
uses_radix()      { has_dep '^(radix-ui|@radix-ui/)'; }
uses_storybook()  { [[ -d "$STORYBOOK_DIR" ]] || has_dep '^@storybook/'; }
uses_tailwind()   { has_dep '^(tailwindcss|@tailwindcss/)'; }
uses_vitest()     { has_dep '^vitest$'; }
uses_react_like() { has_dep '^(react|preact)$'; }
uses_kotlin() {
  find "$TARGET/src" -name '*.kt' -print -quit 2>/dev/null | grep -q . \
    || grep -q 'kotlin(' "$TARGET/build.gradle.kts" 2>/dev/null
}

applies() {
  case "$1" in
    comments.md|typescript.md) uses_typescript ;;
    frontend-structure.md) uses_react_like ;;
    kotlin.md)    uses_kotlin ;;
    react.md)     uses_react ;;
    radix.md)     uses_radix ;;
    storybook.md) uses_storybook ;;
    tailwind.md)  uses_tailwind ;;
    testing.md)   uses_vitest ;;
    *) return 1 ;;
  esac
}

# ---- Plan ----
PLANNED_OVERWRITE=()
PLANNED_ADD=()
PLANNED_SKIP=()
IDENTICAL=()
EXTRAS=()

for rule in "${RULE_FILES[@]}"; do
  src="$RULES_SOURCE/$rule"
  dest="$RULES_DIR/$rule"
  if [[ -f "$dest" ]]; then
    if cmp -s "$src" "$dest"; then
      IDENTICAL+=("$rule")
    else
      PLANNED_OVERWRITE+=("$rule")
    fi
  else
    if applies "$rule"; then
      PLANNED_ADD+=("$rule")
    else
      PLANNED_SKIP+=("$rule")
    fi
  fi
done

# Detect non-canonical extras (only meaningful when the dir already exists).
if ! $INIT_MODE && [[ -d "$RULES_DIR" ]]; then
  while IFS= read -r f; do
    name="$(basename "$f")"
    canonical=false
    for r in "${RULE_FILES[@]}"; do
      [[ "$r" = "$name" ]] && { canonical=true; break; }
    done
    $canonical || EXTRAS+=("$name")
  done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi

# ---- Print summary ----
# bash 3-safe empty-array formatter: callers pass count first, then expanded
# elements with the `${ARRAY[@]+"${ARRAY[@]}"}` idiom (no-op when empty).
fmt_list() {
  local count="$1"; shift
  if [[ "$count" -eq 0 ]]; then echo "(none)"; else echo "$*"; fi
}

echo "Target:    $TARGET"
if $INIT_MODE; then
  echo "Mode:      INIT  (will create .claude/rules + .agents/rules symlink)"
else
  rel="${RULES_DIR#$TARGET/}"
  echo "Rules dir: $rel"
fi
echo
echo "Plan:"
echo "  Overwrite (${#PLANNED_OVERWRITE[@]}): $(fmt_list "${#PLANNED_OVERWRITE[@]}" ${PLANNED_OVERWRITE[@]+"${PLANNED_OVERWRITE[@]}"})"
echo "  Add       (${#PLANNED_ADD[@]}): $(fmt_list "${#PLANNED_ADD[@]}" ${PLANNED_ADD[@]+"${PLANNED_ADD[@]}"})"
echo "  Identical (${#IDENTICAL[@]}): $(fmt_list "${#IDENTICAL[@]}" ${IDENTICAL[@]+"${IDENTICAL[@]}"})"
echo "  Skip      (${#PLANNED_SKIP[@]}): $(fmt_list "${#PLANNED_SKIP[@]}" ${PLANNED_SKIP[@]+"${PLANNED_SKIP[@]}"})  [canonical, project doesn't use the tech]"
echo "  Preserve  (${#EXTRAS[@]}): $(fmt_list "${#EXTRAS[@]}" ${EXTRAS[@]+"${EXTRAS[@]}"})  [project-specific, untouched]"

WRITE_COUNT=$(( ${#PLANNED_OVERWRITE[@]} + ${#PLANNED_ADD[@]} ))

if $DRY_RUN; then
  echo
  echo "Dry run — no changes made."
  exit 0
fi

if [[ $WRITE_COUNT -eq 0 ]] && ! $INIT_MODE; then
  echo
  echo "Nothing to do."
  exit 0
fi

# ---- Confirm ----
if ! $YES; then
  echo
  printf "Apply changes? [y/N] "
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# ---- Apply ----
if $INIT_MODE; then
  mkdir -p "$RULES_DIR"
  AGENTS_DIR="$TARGET/.agents"
  if [[ ! -e "$AGENTS_DIR/rules" && ! -L "$AGENTS_DIR/rules" ]]; then
    mkdir -p "$AGENTS_DIR"
    ln -s "../.claude/rules" "$AGENTS_DIR/rules"
    echo "Created .agents/rules -> ../.claude/rules"
  fi
fi

for rule in ${PLANNED_OVERWRITE[@]+"${PLANNED_OVERWRITE[@]}"} ${PLANNED_ADD[@]+"${PLANNED_ADD[@]}"}; do
  cp "$RULES_SOURCE/$rule" "$RULES_DIR/$rule"
  echo "Wrote $rule"
done

echo "Done."
