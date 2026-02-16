#!/usr/bin/env bash
set -euo pipefail

# Lists skill names by finding */SKILL.md relative to CWD.
# Usage: list-skills.sh [--exclude skill1 skill2 ...]

excludes=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        excludes+=("$1")
        shift
      done
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: list-skills.sh [--exclude skill1 skill2 ...]" >&2
      exit 1
      ;;
  esac
done

# Find all SKILL.md files two levels deep (group/skill), extract paths
skills=()
for f in */*/SKILL.md; do
  [[ -f "$f" ]] || continue
  skills+=("${f%/SKILL.md}")
done

if [[ ${#skills[@]} -eq 0 ]]; then
  echo "No skills found in current directory" >&2
  exit 1
fi

# Apply exclusions and print
for skill in "${skills[@]}"; do
  skip=false
  for exc in "${excludes[@]+"${excludes[@]}"}"; do
    if [[ "$skill" == "$exc" ]]; then
      skip=true
      break
    fi
  done
  $skip || echo "$skill"
done
