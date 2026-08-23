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
# Paths are printed verbatim and relative to the REPOSITORY ROOT, so each one can
# be passed to git as a single argument from the root of the work tree. A path
# containing a literal newline is the one case this format cannot represent.
#
# Exit codes: 0=conflicts found, 1=not git repo, 2=no conflicts,
#             3=a conflicted path contains a newline and cannot be reported

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
# `--porcelain -z`, not `--short`, for two reasons:
#
# 1. `-z` prints paths verbatim. Without it git shell-quotes any path with a space
#    or a non-ASCII byte ("dir name/a file.txt", "caf\303\251.txt"), and those
#    quotes and octal escapes end up in the report — where SKILL.md feeds them
#    into `git checkout --theirs <file>`, which then looks for a filename that
#    really does start with a double quote.
# 2. `--porcelain` is the documented stable format and ignores user config.
#    `--short` honors `status.relativePaths`, so its paths are relative to the
#    caller's cwd. `--porcelain` paths are always relative to the repository root,
#    which is the only anchor a caller can rely on. Callers must run the
#    resolution commands from the root — see SKILL.md.
#
# A path containing a literal newline cannot survive line-oriented output, and the
# failure is not a clean omission: "bad\nname.txt" splits into "UU bad" and
# "name.txt", the first of which still matches the code pattern. The report would
# then name a path that does not exist while quietly losing the one that does — a
# fabricated entry in a machine-read report, which is worse than no report. So
# detect it and refuse. NUL records are the true entry count; if converting them
# to lines yields more lines than there were records, some path carried a newline.
Z_RECORDS=$(git status --porcelain -z | tr -dc '\0' | wc -c | tr -d ' ')
Z_LINES=$(git status --porcelain -z | tr '\0' '\n' | grep -c '' | tr -d ' ')

if [[ "$Z_RECORDS" != "$Z_LINES" ]]; then
    echo "ERROR: a path in this work tree contains a newline" >&2
    echo "       The report is line-oriented and cannot represent it without" >&2
    echo "       fabricating a path. Rename the file and re-run:" >&2
    echo "         git status --porcelain -z | tr '\0' '\n'" >&2
    exit 3
fi

CONFLICT_LINES=$(git status --porcelain -z | tr '\0' '\n' | grep -E '^(UU|UD|DU|AU|UA|AA|DD) ' || true)

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
