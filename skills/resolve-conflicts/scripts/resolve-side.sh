#!/bin/bash
# resolve-side.sh
# Resolves the conflict blocks of one both-modified (UU) or both-added (AA)
# file toward one side, keeping every hunk git already merged cleanly, then
# stages the file.
#
# Usage: resolve-side.sh <ours|theirs> <path>
#   <path> is relative to the repository root, as classify-conflicts.sh prints it.
#
# `git checkout --ours|--theirs <path>` would take that side's whole file and
# drop the other side's non-conflicting changes to it. This instead re-runs the
# three-way merge from the index stages with `git merge-file --ours|--theirs`,
# which settles only the conflicting regions. A both-added file has no base
# stage, so an empty base stands in for it.
#
# Exit codes:
#   0 = resolved and staged
#   1 = usage error or not a git repository
#   2 = <path> is not an unmerged file with both an ours and a theirs stage
#   3 = git merge-file could not merge it (binary file, unreadable stage);
#       the work tree file is left as it was

set -e

SIDE="$1"
FILE="$2"

case "$SIDE" in
    ours|theirs) ;;
    *)
        echo "Usage: resolve-side.sh <ours|theirs> <path>" >&2
        exit 1
        ;;
esac

if [[ -z "$FILE" ]]; then
    echo "Usage: resolve-side.sh <ours|theirs> <path>" >&2
    exit 1
fi

if ! TOP=$(git rev-parse --show-toplevel 2> /dev/null); then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi
cd "$TOP"

if ! git rev-parse -q --verify ":2:$FILE" > /dev/null 2>&1 ||
    ! git rev-parse -q --verify ":3:$FILE" > /dev/null 2>&1; then
    echo "ERROR: $FILE is not unmerged on both sides (expected a UU or AA conflict)" >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/resolve-side.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --filters applies the same smudge and line-ending conversion a checkout would,
# so the result matches what git wrote into the work tree.
: > "$TMP/base"
if git rev-parse -q --verify ":1:$FILE" > /dev/null 2>&1; then
    git cat-file --filters ":1:$FILE" > "$TMP/base"
fi
git cat-file --filters ":2:$FILE" > "$TMP/ours"
git cat-file --filters ":3:$FILE" > "$TMP/theirs"

if ! git merge-file -p "--$SIDE" "$TMP/ours" "$TMP/base" "$TMP/theirs" > "$TMP/result"; then
    echo "ERROR: git merge-file could not merge $FILE; it is left unresolved" >&2
    exit 3
fi

# Writing through the existing file keeps its mode bits.
cat "$TMP/result" > "$FILE"
git add -- "$FILE"
