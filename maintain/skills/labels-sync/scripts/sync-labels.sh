#!/usr/bin/env bash
# sync-labels.sh
# Generic GitHub labels synchronization script
#
# Reads label definitions from stdin (JSON array) and syncs with repository,
# or exports the current repository labels in the same reusable JSON format.
#
# Usage: echo "$LABELS_JSON" | sync-labels.sh [--apply] [--no-delete]
#        sync-labels.sh --get
#
# Input format (stdin):
#   [
#     {"name": "bug", "description": "Something isn't working", "color": "B60205"},
#     {"name": "feature", "description": "New functionality", "color": "1D76DB"}
#   ]
#
# Flags:
#   --apply          Apply changes (default: dry-run, show what would change)
#   --no-delete      Keep labels absent from the definition; they are reported
#                    under "kept" instead of "delete"
#   --get, --export  Print the current repository labels as reusable JSON
#
# Output: JSON report of changes to stdout; with --apply, a progress log and a
# final "Created N, updated N, deleted N" line on stderr. The first failing
# gh call stops the run with its own error, before any later step — deletes run last.
#
# Examples:
#   echo "$LABELS" | sync-labels.sh                         # Dry-run
#   echo "$LABELS" | sync-labels.sh --apply                 # Apply changes
#   cat labels.json | sync-labels.sh --apply --no-delete    # Apply, keep extras
#   sync-labels.sh --get                                    # Export current repo labels

set -euo pipefail

APPLY=false
EXPORT=false
NO_DELETE=false

usage() {
    cat >&2 <<'EOF'
Usage:
  echo '$LABELS_JSON' | sync-labels.sh [--apply] [--no-delete]
  sync-labels.sh --get

Flags:
  --apply          Apply changes (default: dry-run, show what would change)
  --no-delete      Keep labels that are not in the definition
  --get, --export  Print current repository labels as reusable JSON
EOF
}

fetch_current_labels() {
    gh label list --limit 1000 --json name,description,color || {
        echo "ERROR: Failed to fetch labels. Check 'gh auth status' and repo access." >&2
        exit 1
    }
}

while [ $# -gt 0 ]; do
    case $1 in
        --apply)
            APPLY=true
            shift
            ;;
        --no-delete)
            NO_DELETE=true
            shift
            ;;
        --get|--export)
            EXPORT=true
            shift
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ "$EXPORT" = true ] && { [ "$APPLY" = true ] || [ "$NO_DELETE" = true ]; }; then
    echo "ERROR: --apply and --no-delete cannot be combined with --get/--export" >&2
    usage
    exit 1
fi

if [ "$EXPORT" = true ]; then
    CURRENT_LABELS=$(fetch_current_labels)
    printf '%s\n' "$CURRENT_LABELS" | jq '
        map({
            name,
            description: (.description // ""),
            color: ((.color // "") | ascii_upcase | ltrimstr("#"))
        })
        | sort_by(.name | ascii_downcase)
    '
    exit 0
fi

if [ -t 0 ]; then
    echo "ERROR: No labels provided via stdin" >&2
    usage
    exit 1
fi

DEFINED_LABELS_JSON=$(cat)

if ! printf '%s\n' "$DEFINED_LABELS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON input (expected an array of labels)" >&2
    exit 1
fi

CURRENT_LABELS=$(fetch_current_labels)

RESULT=$(jq -n \
    --argjson defined "$DEFINED_LABELS_JSON" \
    --argjson current "$CURRENT_LABELS" \
    --argjson no_delete "$NO_DELETE" \
'
# Names match case-insensitively; colors compare lowercase without "#"
def normalize_color: ascii_downcase | ltrimstr("#");
def normalize_name: ascii_downcase;

($current | map({key: (.name | normalize_name), value: .}) | from_entries) as $current_map |
($defined | map(.name | normalize_name)) as $defined_keys |
($current | map(.name | normalize_name)) as $current_keys |

($defined | map(select((.name | normalize_name) as $k | $current_keys | index($k) | not))) as $to_create |

($current | map(select((.name | normalize_name) as $k | $defined_keys | index($k) | not)) | map({name})) as $extra |

($defined | map(
    (.name | normalize_name) as $key |
    select($current_keys | index($key)) |
    $current_map[$key] as $curr |
    {
        defined_name: .name,
        current_name: $curr.name,
        defined_desc: (.description // ""),
        current_desc: ($curr.description // ""),
        defined_color: (.color | normalize_color),
        current_color: ($curr.color | normalize_color)
    } |
    if .defined_name != .current_name or .defined_desc != .current_desc or .defined_color != .current_color then
        {
            name: .current_name,
            target_name: .defined_name,
            changes: (
                (if .defined_name != .current_name then [{field: "name", from: .current_name, to: .defined_name}] else [] end) +
                (if .defined_desc != .current_desc then [{field: "description", from: .current_desc, to: .defined_desc}] else [] end) +
                (if .defined_color != .current_color then [{field: "color", from: .current_color, to: .defined_color}] else [] end)
            ),
            target_desc: .defined_desc,
            target_color: .defined_color
        }
    else
        {unchanged: .current_name}
    end
)) as $compared |

{
    create: $to_create,
    update: [$compared[] | select(.changes) | {name, target_name, changes, target_desc, target_color}],
    delete: (if $no_delete then [] else $extra end),
    kept: (if $no_delete then $extra else [] end),
    unchanged: [$compared[] | select(.unchanged) | .unchanged]
}
')

printf '%s\n' "$RESULT" | jq .

if [ "$APPLY" != true ]; then
    exit 0
fi

echo "" >&2
echo "Applying changes..." >&2

created=0
updated=0
deleted=0

# --force makes create idempotent if the label appeared since the diff was read
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name=$(printf '%s\n' "$entry" | jq -r '.name')
    desc=$(printf '%s\n' "$entry" | jq -r '.description // ""')
    color=$(printf '%s\n' "$entry" | jq -r '.color | ltrimstr("#")')
    echo "  Creating: $name" >&2
    gh label create "$name" --description "$desc" --color "$color" --force
    created=$((created + 1))
done <<EOF
$(printf '%s\n' "$RESULT" | jq -c '.create[]')
EOF

while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name=$(printf '%s\n' "$entry" | jq -r '.name')
    target_name=$(printf '%s\n' "$entry" | jq -r '.target_name')
    desc=$(printf '%s\n' "$entry" | jq -r '.target_desc')
    color=$(printf '%s\n' "$entry" | jq -r '.target_color')
    echo "  Updating: $name" >&2
    if [ "$name" != "$target_name" ]; then
        gh label edit "$name" --name "$target_name" --description "$desc" --color "$color"
    else
        gh label edit "$name" --description "$desc" --color "$color"
    fi
    updated=$((updated + 1))
done <<EOF
$(printf '%s\n' "$RESULT" | jq -c '.update[]')
EOF

while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name=$(printf '%s\n' "$entry" | jq -r '.name')
    echo "  Deleting: $name" >&2
    gh label delete "$name" --yes
    deleted=$((deleted + 1))
done <<EOF
$(printf '%s\n' "$RESULT" | jq -c '.delete[]')
EOF

kept=$(printf '%s\n' "$RESULT" | jq '.kept | length')
if [ "$kept" -gt 0 ]; then
    echo "Created $created, updated $updated, deleted $deleted, kept $kept" >&2
else
    echo "Created $created, updated $updated, deleted $deleted" >&2
fi
