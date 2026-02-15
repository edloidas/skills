#!/bin/zsh
# sync-labels.sh
# Generic GitHub labels synchronization script
#
# Reads label definitions from stdin (JSON array) and syncs with repository.
#
# Usage: echo "$LABELS_JSON" | sync-labels.sh [--apply]
#
# Input format (stdin):
#   [
#     {"name": "bug", "description": "Something isn't working", "color": "B60205"},
#     {"name": "feature", "description": "New functionality", "color": "1D76DB"}
#   ]
#
# Flags:
#   --apply     Apply changes (default: dry-run, show what would change)
#
# Output: JSON report of changes to stdout
#
# Examples:
#   echo "$LABELS" | sync-labels.sh            # Dry-run
#   echo "$LABELS" | sync-labels.sh --apply    # Apply changes
#   cat labels.json | sync-labels.sh --apply   # From file

set -e

# Parse arguments
APPLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --apply)
            APPLY=true
            shift
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Usage: echo '\$LABELS_JSON' | sync-labels.sh [--apply]" >&2
            exit 1
            ;;
    esac
done

# Read labels from stdin
if [[ -t 0 ]]; then
    echo "ERROR: No labels provided via stdin" >&2
    echo "Usage: echo '\$LABELS_JSON' | sync-labels.sh [--apply]" >&2
    exit 1
fi

DEFINED_LABELS_JSON=$(cat)

# Validate JSON input
if ! echo "$DEFINED_LABELS_JSON" | jq empty 2>/dev/null; then
    echo "ERROR: Invalid JSON input" >&2
    exit 1
fi

# Fetch current labels from repository
CURRENT_LABELS=$(gh label list --json name,description,color) || {
    echo "ERROR: Failed to fetch labels. Check 'gh auth status' and repo access." >&2
    exit 1
}

# Use jq to compute all differences
RESULT=$(jq -n \
    --argjson defined "$DEFINED_LABELS_JSON" \
    --argjson current "$CURRENT_LABELS" \
'
# Normalize: lowercase name as key, lowercase color
def normalize_color: . | ascii_downcase | ltrimstr("#");
def normalize_name: . | ascii_downcase;

# Build lookup maps
($defined | map({key: (.name | normalize_name), value: .}) | from_entries) as $defined_map |
($current | map({key: (.name | normalize_name), value: .}) | from_entries) as $current_map |
($defined | map(.name | normalize_name)) as $defined_keys |
($current | map(.name | normalize_name)) as $current_keys |

# Find labels to create (in defined but not in current)
($defined | map(select((.name | normalize_name) as $k | $current_keys | index($k) | not))) as $to_create |

# Find labels to delete (in current but not in defined)
($current | map(select((.name | normalize_name) as $k | $defined_keys | index($k) | not))) as $to_delete |

# Find labels to update or unchanged
($defined | map(
    (.name | normalize_name) as $key |
    select($current_keys | index($key)) |
    $current_map[$key] as $curr |
    {
        defined_name: .name,
        current_name: $curr.name,
        defined_desc: .description,
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
    delete: [$to_delete[] | {name}],
    unchanged: [$compared[] | select(.unchanged) | .unchanged]
}
')

# Output report
echo "$RESULT" | jq .

# Apply changes if requested
if [[ "$APPLY" = true ]]; then
    echo "" >&2
    echo "Applying changes..." >&2

    # Create new labels (--force updates if already exists)
    echo "$RESULT" | jq -c '.create[]' 2>/dev/null | while read -r entry; do
        name=$(echo "$entry" | jq -r '.name')
        desc=$(echo "$entry" | jq -r '.description')
        color=$(echo "$entry" | jq -r '.color')
        echo "  Creating: $name" >&2
        gh label create "$name" --description "$desc" --color "$color" --force
    done

    # Update existing labels
    echo "$RESULT" | jq -c '.update[]' 2>/dev/null | while read -r entry; do
        name=$(echo "$entry" | jq -r '.name')
        target_name=$(echo "$entry" | jq -r '.target_name')
        desc=$(echo "$entry" | jq -r '.target_desc')
        color=$(echo "$entry" | jq -r '.target_color')
        echo "  Updating: $name" >&2
        # If name changed, include --name flag
        if [[ "$name" != "$target_name" ]]; then
            gh label edit "$name" --name "$target_name" --description "$desc" --color "$color"
        else
            gh label edit "$name" --description "$desc" --color "$color"
        fi
    done

    # Delete extra labels
    echo "$RESULT" | jq -c '.delete[]' 2>/dev/null | while read -r entry; do
        name=$(echo "$entry" | jq -r '.name')
        echo "  Deleting: $name" >&2
        gh label delete "$name" --yes
    done

    echo "Done!" >&2
fi
