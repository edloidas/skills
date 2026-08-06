#!/usr/bin/env bash
set -euo pipefail

# Per-host discovery smoke test.
#
# The other validators check this repo's manifests against each other. That is not enough:
# a layout can satisfy every internal contract and still be invisible to the agents that
# have to load it. Three real bugs shipped that way before 4.0.0 —
#
#   1. `npx skills add edloidas/skills` reported a single skill (the internal release
#      tool) because the CLI stops at the first matching priority directory.
#   2. The five `build/` skills were unreachable at any flag combination, because the
#      CLI's hardcoded skip list contains `build`.
#   3. Symlinked skill directories were invisible to that CLI entirely, since it filters
#      on readdir's `entry.isDirectory()`, which is false for a symlink.
#
# None of them tripped a validator. This script asserts what each host actually resolves,
# so a regression fails CI instead of silently shipping.
#
# Usage: validate-discovery.sh [--skip-network]

SKIP_NETWORK=0
[ "${1:-}" = "--skip-network" ] && SKIP_NETWORK=1

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO_ROOT"

errors=0

error() {
  echo "::error::$*" >&2
  errors=1
}

pass() {
  echo "  ok  $*"
}

# --- Expected counts, derived from the source tree rather than hardcoded ---------------

count_all_skills() {
  local group total=0
  for group in plan build review audit maintain ship assist write obsidian workflow; do
    total=$((total + $(find "$group/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)))
  done
  printf '%s' "$total"
}

# Skills declaring a host token in `compatibility:`. Split on commas so "Codex" cannot
# match "OpenCode" by substring.
count_host_skills() {
  local label="$1" group count=0 skill_md
  for group in plan build review audit maintain ship assist write obsidian workflow; do
    while IFS= read -r skill_md; do
      [ -n "$skill_md" ] || continue
      if awk -v label="$label" '
        /^---$/ { d++; next }
        d == 1 && /^compatibility:/ {
          sub(/^compatibility: */, "")
          n = split($0, parts, ",")
          for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
            if (parts[i] == label) { found = 1 }
          }
        }
        d >= 2 { exit }
        END { exit(found ? 0 : 1) }
      ' "$skill_md"; then
        count=$((count + 1))
      fi
    done <<EOF
$(find "$group/skills" -mindepth 2 -maxdepth 2 -name SKILL.md)
EOF
  done
  printf '%s' "$count"
}

TOTAL=$(count_all_skills)
OPENCODE_EXPECTED=$(count_host_skills OpenCode)
PI_EXPECTED=$(count_host_skills Pi)
CODEX_EXPECTED=$(count_host_skills Codex)

echo "Source tree: $TOTAL skills (Codex $CODEX_EXPECTED, OpenCode $OPENCODE_EXPECTED, Pi $PI_EXPECTED)"

# --- 1. Canonical layout: real directories, no legacy paths ----------------------------

echo
echo "Canonical layout"
symlinked=$(find plan build review audit maintain ship assist write obsidian workflow \
  -mindepth 2 -maxdepth 2 -path '*/skills/*' -type l | wc -l | tr -d ' ')
if [ "$symlinked" -ne 0 ]; then
  error "$symlinked skill directories are symlinks; agent skill CLIs cannot discover them"
else
  pass "all $TOTAL skill directories are real directories"
fi

# --- 2. Generated per-host trees resolve and match the declared sets -------------------

echo
echo "Generated host trees"
check_tree() {
  local dir="$1" expected="$2" label="$3" found dangling=0 link
  if [ ! -d "$dir" ]; then
    error "$label tree missing: $dir (run ./scripts/skills-packaging.sh sync-repo)"
    return
  fi
  found=$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  for link in "$dir"/*; do
    [ -e "$link" ] || dangling=$((dangling + 1))
  done
  if [ "$dangling" -ne 0 ]; then
    error "$label tree has $dangling dangling symlinks in $dir"
  elif [ "$found" -ne "$expected" ]; then
    error "$label tree has $found entries, expected $expected (run ./scripts/skills-packaging.sh sync-repo)"
  else
    pass "$label tree: $found skills, none dangling"
  fi
}
check_tree ".opencode/skills" "$OPENCODE_EXPECTED" "OpenCode"
check_tree ".pi/skills" "$PI_EXPECTED" "pi"
check_tree ".agents/skills" "$CODEX_EXPECTED" "Codex"

# --- 3. pi: the package manifest must resolve every Pi skill ---------------------------

echo
echo "pi package manifest"
manifest_dirs=$(node -e '
  const p = require("./package.json");
  if (!p.pi || !Array.isArray(p.pi.skills)) { console.error("package.json has no pi.skills array"); process.exit(1) }
  console.log(p.pi.skills.join("\n"))
' 2>/dev/null) || error "package.json is missing a pi.skills array"

if [ -n "$manifest_dirs" ]; then
  missing=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "${d#./}" ] || { error "pi.skills points at a missing directory: $d"; missing=1; }
  done <<EOF
$manifest_dirs
EOF

  # pi.skills must point at the generated .pi/skills tree, not at the group directories.
  # Group directories hold every skill regardless of `compatibility:`, so listing them
  # would ship the Claude-only skills to pi as well; the generated tree is exactly the
  # set that declared Pi support.
  case "$manifest_dirs" in
    *"./.pi/skills"*) ;;
    *) error "pi.skills must list ./.pi/skills so pi receives exactly the declared Pi set" ;;
  esac
  for group in plan build review audit maintain ship assist write obsidian workflow; do
    case "$manifest_dirs" in
      *"./$group/skills"*) error "pi.skills lists ./$group/skills; that ships Claude-only skills to pi. Use ./.pi/skills instead." ;;
    esac
  done
  [ "$missing" -eq 0 ] && pass "pi.skills points at the generated .pi/skills tree"
fi

# --- 4. skills CLI: the count it actually resolves -------------------------------------

echo
echo "skills CLI discovery"
if [ "$SKIP_NETWORK" -eq 1 ]; then
  echo "  -- skipped (--skip-network)"
elif ! command -v npx >/dev/null 2>&1; then
  echo "  -- skipped (npx unavailable)"
else
  # `add <path> --list` only enumerates; it installs nothing.
  #
  # Match on skill NAMES, not on the CLI's line formatting. An earlier version of this
  # check counted lines matching '^│    <name>$', which is decorative output that differs
  # between a TTY and CI — so it reported 0 on a perfectly good tree. Names are the actual
  # contract, and a name still disappears if its directory becomes a symlink or its group
  # hits the CLI's skip list, so this keeps the regressions it was written to catch.
  cli_raw=$(cd "$(mktemp -d)" && npx --yes skills@latest add "$REPO_ROOT" --list 2>&1 || true)

  # The CLI prints each skill name alone on its own line and its description on a later,
  # more deeply indented line. Strip ANSI codes and the leading box-drawing gutter, then a
  # name is any line whose entire remaining content is a single slug. Anchoring per line
  # matters: several descriptions mention other skills by name ("commit", "codex", "ask"),
  # so searching the whole blob would let a description mask a genuinely missing skill.
  cli_names=$(printf '%s\n' "$cli_raw" |
    sed -e $'s/\033\\[[?0-9;]*[A-Za-z]//g' |
    sed -e 's/^[^[:alnum:]]*//' -e 's/[[:space:]]*$//' |
    grep -E '^[a-z0-9][a-z0-9-]*$' | sort -u)

  if [ -z "$cli_names" ]; then
    error "skills CLI returned no parseable skill names. Its output format may have changed."
    echo "--- skills CLI output (last 40 lines) ---" >&2
    printf '%s\n' "$cli_raw" | tail -40 >&2
  else
    cli_missing=""
    for group in plan build review audit maintain ship assist write obsidian workflow; do
      while IFS= read -r skill_md; do
        [ -n "$skill_md" ] || continue
        skill_name=$(basename "$(dirname "$skill_md")")
        printf '%s\n' "$cli_names" | grep -qxF "$skill_name" ||
          cli_missing="$cli_missing $skill_name"
      done <<EOF
$(find "$group/skills" -mindepth 2 -maxdepth 2 -name SKILL.md)
EOF
    done

    if [ -z "$cli_missing" ]; then
      pass "skills CLI resolves all $TOTAL skills with no extra flags"
    else
      error "skills CLI cannot see these skills:$cli_missing"
      error "A group directory name may collide with the CLI's skip list (node_modules/.git/dist/build/__pycache__), or a skill directory may have become a symlink."
    fi
  fi
fi

echo
if [ "$errors" -ne 0 ]; then
  echo "Discovery validation FAILED" >&2
  exit 1
fi
echo "Discovery validation passed."
