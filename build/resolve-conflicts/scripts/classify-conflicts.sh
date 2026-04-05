#!/bin/bash
# classify-conflicts.sh
# Groups conflicted files by git status code (UU, DU, UD, AA, DD, AU, UA)
#
# Usage: classify-conflicts.sh
#
# Output format:
#   # counts
#   DU=3
#   UD=23
#   UU=26
#   AA=0
#   DD=0
#   AU=0
#   UA=0
#   TOTAL=52
#
#   # files
#   DU path/to/file1.ts
#   UD path/to/file2.ts
#   UU path/to/file3.ts
#
# Exit codes: 0=conflicts found, 1=not git repo, 2=no conflicts

set -e

# Validate git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

# Capture conflict status lines
# git status --short shows two-letter codes for unmerged files:
#   UU = both modified
#   DU = deleted by theirs, modified by ours
#   UD = deleted by ours, modified by theirs
#   AA = both added
#   DD = both deleted
#   AU = added by us, unmerged by theirs
#   UA = added by theirs, unmerged by us
CONFLICT_LINES=$(git status --short | grep -E '^(UU|UD|DU|AU|UA|AA|DD) ' || true)

if [[ -z "$CONFLICT_LINES" ]]; then
    echo "ERROR: No conflicts found" >&2
    exit 2
fi

# Count per status code
DU=0; UD=0; UU=0; AA=0; DD=0; AU=0; UA=0

while IFS= read -r line; do
    CODE="${line:0:2}"
    case "$CODE" in
        DU) DU=$((DU + 1)) ;;
        UD) UD=$((UD + 1)) ;;
        UU) UU=$((UU + 1)) ;;
        AA) AA=$((AA + 1)) ;;
        DD) DD=$((DD + 1)) ;;
        AU) AU=$((AU + 1)) ;;
        UA) UA=$((UA + 1)) ;;
    esac
done <<< "$CONFLICT_LINES"

TOTAL=$((DU + UD + UU + AA + DD + AU + UA))

# Output counts
echo "# counts"
echo "DU=$DU"
echo "UD=$UD"
echo "UU=$UU"
echo "AA=$AA"
echo "DD=$DD"
echo "AU=$AU"
echo "UA=$UA"
echo "TOTAL=$TOTAL"
echo ""

# Output files with status codes
echo "# files"
while IFS= read -r line; do
    CODE="${line:0:2}"
    # File path starts at position 3 (after code + space)
    FILE="${line:3}"
    echo "$CODE $FILE"
done <<< "$CONFLICT_LINES"
