#!/usr/bin/env bash
set -euo pipefail

# Validate the Claude marketplace/source-plugin contract for this repo.
#
# Scope:
# - .claude-plugin/marketplace.json exists and is valid JSON
# - each marketplace entry points at a source group directory
# - each source group ships .claude-plugin/plugin.json with the expected
#   matching name and valid JSON structure
# - each source group contains discoverable skills
# - each skill is a real directory at <group>/skills/<name>, not a symlink, and the
#   pre-4.0 <group>/<name> authoring path is gone
# - source groups do not embed Codex wrapper manifests directly
# - each SKILL.md declares a name matching its directory, a description within the
#   discovery caps, and no reference to a bundled file it does not ship
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

# A skill that names Codex, OpenCode, or Pi has to work there. These mechanisms exist
# only in Claude Code, so a portable skill that instructs the agent to use one ships a
# step three of its four declared hosts cannot execute — which is what let the `commit`
# skill sit in the Codex catalog with its whole context-gathering section unresolvable.
# Claude-only skills are exempt: for them these are the correct mechanism.
skill_declares_non_claude_host() {
  local skill_dir="$1"
  read_frontmatter "$skill_dir" | awk '
    /^compatibility:/ {
      if ($0 ~ /Codex|OpenCode|Pi/) {
        found = 1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

claude_only_exempt() {
  local path="$1" row
  while IFS= read -r row; do
    [ "$row" = "$path" ] && return 0
  done <<EOF
$CLAUDE_ONLY_EXEMPT
EOF
  return 1
}

# `(^|[[:space:]])` is deliberately NOT used here: BSD grep treats `^` inside a group as
# a literal, so the anchored alternative silently never matches on macOS while passing on
# CI's GNU grep. Two -e patterns are portable.
# One skill's subject matter *is* these mechanisms: `skill-audit`'s rubric and dispatched
# prompt have to name them to tell an auditor what to look for. Exempting the whole skill
# means a genuine violation inside it would not be caught here — acceptable, because it
# dispatches as intent and holds no workflow of its own that a host could fail to run.
# Adding a row is a deliberate decision that needs a reason in CLAUDE.md.
CLAUDE_ONLY_EXEMPT="audit/skills/skill-audit"

# A tool name in `description` or `when_to_use` is dead weight on every host, Claude Code
# included: discovery text exists to match what a person types, and nobody asks for a skill
# by naming the tool it calls. So unlike CLAUDE_ONLY_PATTERNS this applies to Claude-only
# skills too, and the reason is usefulness rather than portability.
#
# Only unambiguous identifiers are listed. `Task`, `Agent`, `Skill`, `Read`, `Write`, `Edit`,
# `Glob`, `Grep`, and `Bash` are ordinary English and appear legitimately in real
# descriptions — "Audit Agent Skills", "Write Markdown", "Reads and reports only" — so they
# are caught only in the explicit "<Name> tool" phrasing.
DISCOVERY_TOOL_PATTERNS="tool|(AskUserQuestion|ToolSearch|TodoWrite|SlashCommand|NotebookEdit|WebFetch|WebSearch|StructuredOutput)
tool|(Task|Agent|Skill|Read|Write|Edit|Glob|Grep|Bash)[ ]tool
subagent field|subagent_type"

CLAUDE_ONLY_PATTERNS="dynamic-injection|^!\`[^ \`/!][^\`]*\`
dynamic-injection|[[:space:]]!\`[^ \`/!][^\`]*\`
Claude-only substitution|[$]{?CLAUDE_(SESSION_ID|SKILL_DIR|PLUGIN_ROOT)
Claude-only tool|[^A-Za-z](ToolSearch|TodoWrite|SlashCommand)[^A-Za-z]
Claude-only subagent field|subagent_type"

# Body length is a context cost paid on every activation, so it is enforced here
# rather than left to skill-audit's rubric — the repo's rule is that anything
# mechanically checkable belongs in a validator.
#
# The cap is 500 lines, per CLAUDE.md. A skill that genuinely needs more gets an
# explicit ceiling below rather than a blanket exemption, so it cannot keep growing
# unnoticed. Adding a row is a deliberate decision that needs a reason in CLAUDE.md.
BODY_LINE_CAP=500
BODY_LINE_BUDGETS="plan/skills/issue-flow=1000
workflow/skills/solve-issue=540"

# Lines after the closing frontmatter delimiter.
#
# Only the first two `---` lines are delimiters. Skipping every one of them — as this
# did — silently discards each horizontal rule in the body, so a skill measured smaller
# than it is: `issue-writer` reported 498 lines against a real 507 because nine `---`
# rules sit inside its issue templates. The cap has to count what the agent loads.
body_line_count() {
  awk 'BEGIN { delimiter_count = 0 }
    delimiter_count < 2 && $0 == "---" { delimiter_count++; next }
    delimiter_count >= 2 { print }
  ' "$1/SKILL.md" | wc -l | tr -d ' '
}

# The ceiling for one skill: its budgeted allowance, or the default cap.
body_line_budget() {
  local path="$1" row
  while IFS= read -r row; do
    case "$row" in
      "$path="*) printf '%s' "${row#*=}"; return ;;
    esac
  done <<EOF
$BODY_LINE_BUDGETS
EOF
  printf '%s' "$BODY_LINE_CAP"
}

# Reads a single frontmatter scalar, joining YAML folded/literal continuation lines
# into one space-separated string so length caps can be measured on the real value.
frontmatter_scalar() {
  local skill_dir="$1"
  local key="$2"
  awk -v key="$key" '
    BEGIN { depth = 0; capturing = 0; out = "" }
    $0 == "---" { depth++; if (depth >= 2) exit; next }
    depth == 1 {
      if (capturing) {
        if ($0 ~ /^[ \t]/) {
          line = $0
          sub(/^[ \t]+/, "", line)
          out = out (out == "" ? "" : " ") line
          next
        }
        capturing = 0
      }
      if ($0 ~ "^" key ":") {
        value = $0
        sub("^" key ":[ \t]*", "", value)
        if (value == "" || value ~ /^[|>][-+]?$/) {
          capturing = 1
          out = ""
        } else {
          out = value
        }
        next
      }
    }
    END {
      gsub(/^["'"'"']|["'"'"']$/, "", out)
      print out
    }
  ' "$skill_dir/SKILL.md"
}

# Hard per-skill rules. Judgment belongs to the skill-audit skill; everything checked
# here is mechanical, unambiguous, and must never regress.
validate_skill_content() {
  local skill_dir="$1"
  local skill_name="$2"
  local declared_name description when_to_use combined ref body_lines body_budget
  local rule label pattern hit key field match

  if [ "$(head -n 1 "$skill_dir/SKILL.md")" != "---" ]; then
    error "Skill '$skill_name': SKILL.md does not open with a YAML frontmatter block"
    return
  fi

  declared_name=$(frontmatter_scalar "$skill_dir" "name")
  description=$(frontmatter_scalar "$skill_dir" "description")
  when_to_use=$(frontmatter_scalar "$skill_dir" "when_to_use")

  if [ -z "$declared_name" ]; then
    error "Skill '$skill_name': frontmatter is missing a name"
  else
    if [ "$declared_name" != "$skill_name" ]; then
      error "Skill '$skill_name': frontmatter name '$declared_name' does not match the directory name"
    fi
    if ! printf '%s' "$declared_name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      error "Skill '$skill_name': name '$declared_name' must be lowercase a-z, 0-9 and single hyphens, with no leading or trailing hyphen"
    fi
    if [ "${#declared_name}" -gt 64 ]; then
      error "Skill '$skill_name': name is ${#declared_name} chars; the limit is 64"
    fi
  fi

  if [ -z "$description" ]; then
    error "Skill '$skill_name': frontmatter is missing a description"
  elif [ "${#description}" -gt 1024 ]; then
    error "Skill '$skill_name': description is ${#description} chars; the limit is 1024"
  fi

  if [ -n "$when_to_use" ]; then
    combined="$description $when_to_use"
    if [ "${#combined}" -gt 1536 ]; then
      error "Skill '$skill_name': description + when_to_use is ${#combined} chars; the discovery entry is truncated past 1536"
    fi
  fi

  body_lines=$(body_line_count "$skill_dir")
  body_budget=$(body_line_budget "$skill_dir")
  if [ "$body_lines" -gt "$body_budget" ]; then
    if [ "$body_budget" = "$BODY_LINE_CAP" ]; then
      error "Skill '$skill_name': body is $body_lines lines; the cap is $BODY_LINE_CAP. Move reference material into references/, or add a budgeted allowance in validate-skills.sh with a reason in CLAUDE.md"
    else
      error "Skill '$skill_name': body is $body_lines lines; its budgeted allowance is $body_budget. Trim it, or raise the budget deliberately"
    fi
  fi

  for key in description when_to_use; do
    field=$(frontmatter_scalar "$skill_dir" "$key")
    [ -n "$field" ] || continue
    while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      label="${rule%%|*}"
      pattern="${rule#*|}"
      # `|| true` is load-bearing: grep exits 1 when it finds nothing, and under
      # `set -euo pipefail` that aborts the whole script silently instead of passing
      # the skill. Without it the validator exited 1 with no output at all.
      match=$(printf '%s\n' "$field" | grep -oE "$pattern" | head -n 1 || true)
      if [ -n "$match" ]; then
        error "Skill '$skill_name': $key names the $label '$match'. Discovery text is matched against what a user types, so a tool name there can never help it fire — describe the behaviour instead"
      fi
    done <<EOF
$DISCOVERY_TOOL_PATTERNS
EOF
  done

  if skill_declares_non_claude_host "$skill_dir" && ! claude_only_exempt "$skill_dir"; then
    while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      label="${rule%%|*}"
      pattern="${rule#*|}"
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        error "Skill '$skill_name': $label at $hit — the skill declares a non-Claude host, so this step cannot run there. State it as intent, or narrow compatibility"
      done <<INNER
$(find "$skill_dir" -name '*.md' -print0 2>/dev/null | xargs -0 grep -nE -e "$pattern" /dev/null 2>/dev/null | cut -d: -f1,2)
INNER
    done <<EOF
$CLAUDE_ONLY_PATTERNS
EOF
  fi

  # A body that points at references/, scripts/, or assets/ it does not ship sends the
  # agent looking for material that is not there. Paths whose last segment has no
  # extension are prose, not file references, and are skipped.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      */) ;;
      *.*) ;;
      *) continue ;;
    esac
    if [ -e "$skill_dir/$ref" ] || [ -e "$ref" ]; then
      continue
    fi
    error "Skill '$skill_name': SKILL.md references '$ref', which the skill does not ship"
  done <<EOF
$(grep -ohE '(^|[^A-Za-z0-9._/-])(references|scripts|assets)/[A-Za-z0-9._/-]+' "$skill_dir/SKILL.md" | sed -E 's/^[^A-Za-z]//; s/\.$//' | sort -u)
EOF
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

  if [ "$manifest_name" != "$name" ]; then
    error "Plugin '$name': marketplace name does not match $plugin_manifest name '$manifest_name'"
  fi

  # Find all SKILL.md files inside the plugin source directory
  skill_count=0
  codex_compatible_count=0

  while IFS= read -r skill_md; do
    [ -n "$skill_md" ] || continue
    skill_count=$((skill_count + 1))
    skill_dir=$(dirname "$skill_md")
    skill_name=$(basename "$skill_dir")

    # The canonical skill directory is <group>/skills/<name>, and it must be a REAL
    # directory rather than a symlink. Agent skill CLIs discover skills with
    # readdir(withFileTypes) + entry.isDirectory(), which is false for a symlink, so a
    # symlinked skill is invisible to them. Claude Code's plugin loader reads this same
    # path, so one real directory serves every host.
    if [ -L "$skill_dir" ]; then
      error "Plugin '$name': '$skill_dir' is a symlink; it must be a real directory or agent skill CLIs cannot discover it"
    fi

    # Exactly one canonical location per skill — the pre-4.0 <group>/<name> authoring
    # path must not come back, or the same skill gets discovered twice under two paths.
    if [ -e "$source/$skill_name" ]; then
      error "Plugin '$name': legacy skill path '$source/$skill_name' still exists; the canonical location is '$skill_dir'"
    fi

    validate_skill_content "$skill_dir" "$skill_name"

    if skill_has_codex_compatibility "$skill_dir"; then
      codex_compatible_count=$((codex_compatible_count + 1))
    fi
  done <<EOF
$(find "$source/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -print | sort)
EOF

  if [ "$skill_count" -eq 0 ]; then
    error "Plugin '$name': no skills found in '$source/'"
  else
    echo "Plugin '$name': $skill_count skills found in '$source/' ($codex_compatible_count Codex-compatible)"
    total_skills=$((total_skills + skill_count))
    total_codex_compatible_skills=$((total_codex_compatible_skills + codex_compatible_count))
  fi
done

# ------------------------------------------------------ README count drift ----
# The README states the skill and plugin counts in several hand-maintained places.
# Every one of them was wrong at v5.0.0: 38 skills against a real 36, 9 wrapper
# plugins against 10, and a group table summing to 38 while its own rows said 3
# and 6. The correct values are already computed above, so assert them rather
# than trusting a person to remember a number in five places.
#
# This checks counts only. Whether a skill has a table row at all is a different
# question, and one a person reading the diff will notice; a wrong number is not.
validate_readme_counts() {
  local readme="README.md"

  if [ ! -f "$readme" ]; then
    error "README.md not found; the count assertions cannot run"
    return
  fi

  # Three independent statements of the same total: the shields.io badge, the
  # opening sentence, and the sum of the group table's own per-group column.
  local badge intro group_sum
  badge=$(sed -n 's/.*badge\/skills-\([0-9][0-9]*\)-.*/\1/p' "$readme" | head -n 1)
  intro=$(sed -n 's/^\([0-9][0-9]*\) skills for .*/\1/p' "$readme" | head -n 1)
  group_sum=$(awk -F'|' '/^\| \[[a-z]+\]\(#/ { gsub(/[^0-9]/, "", $4); sum += $4 } END { print sum + 0 }' "$readme")

  local pair where value
  for pair in "badge:$badge" "opening sentence:$intro" "group table:$group_sum"; do
    where=${pair%%:*}
    value=${pair#*:}
    if [ -z "$value" ]; then
      error "README: could not read a skill count from the $where"
    elif [ "$value" != "$total_skills" ]; then
      error "README: $where says $value skills, but the repo has $total_skills"
    fi
  done

  # Plugin count, stated once per install/verify surface. Each phrase is matched
  # with its number so a stale one is named rather than merely missed. No
  # `(^|[[:space:]])` anchor group here: BSD grep treats `^` inside a group as a
  # literal, so that alternative silently matches nothing on macOS.
  local phrase found
  for phrase in "plugin groups" "wrapper plugins" '`@edloidas-skills` plugins'; do
    found=$(grep -o -E "[0-9][0-9]* $phrase" "$readme" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)
    found=${found% }
    if [ -z "$found" ]; then
      error "README: no '<count> $phrase' statement found; the plugin count is unasserted"
    elif [ "$found" != "$plugin_count" ]; then
      error "README: '$phrase' is stated as '$found', but the repo has $plugin_count plugins"
    fi
  done
}

validate_readme_counts

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "Claude marketplace valid. $total_skills skills across $plugin_count plugins ($total_codex_compatible_skills marked Codex-compatible)."
echo "README counts agree: $total_skills skills, $plugin_count plugins."
