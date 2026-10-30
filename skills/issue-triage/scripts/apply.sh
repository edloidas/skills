#!/usr/bin/env bash
# apply.sh — reconcile GitHub issues with an approved triage manifest.
#
#   apply.sh preflight <manifest>                    check identity, scopes and every name the manifest uses
#   apply.sh plan      <manifest> [--only N,N]       print the writes still needed; last line: manifest <id> ops <n>
#   apply.sh apply     <manifest> --expect <id> [--only N,N]
#   apply.sh audit     <manifest>                    exit 0 only when live state matches the manifest
#
# The manifest states the end state of each issue, not the steps (see references/acting.md), so a
# rerun only does what is still missing. Text files are posted unchanged apart from one hidden
# marker line, which is how a rerun recognises its own comments and body notes.
#
# Exit codes: 0 done · 1 gh or jq failure · 2 invalid manifest or --expect mismatch · 3 preflight
# failed · 4 permission denied · 5 rate limited · 6 audit mismatch, or a board workflow closed an
# issue that should stay open.
#
# Env: ISSUE_TRIAGE_PAUSE seconds between writes (default 1), ISSUE_TRIAGE_SETTLE seconds before
# re-reading an issue after a status write (default 3).

set -euo pipefail

PAUSE="${ISSUE_TRIAGE_PAUSE:-1}"
SETTLE="${ISSUE_TRIAGE_SETTLE:-3}"

die() { local code="$1"; shift; echo "apply.sh: $*" >&2; exit "$code"; }

usage() { sed -n '2,7p' "$0" >&2; exit 2; }

[ $# -ge 2 ] || usage
CMD="$1"; MANIFEST="$2"; shift 2
ONLY=""; EXPECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --expect) EXPECT="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || die 1 "jq is required"
command -v gh >/dev/null 2>&1 || die 1 "gh is required"
[ -f "$MANIFEST" ] || die 2 "no manifest at $MANIFEST"

DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
CREATED="$DIR/created.json"
[ -f "$CREATED" ] || echo '{}' > "$CREATED"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/issue-triage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The approved id covers the manifest and every text it names, so a text edited after the gate
# changes the id and needs a new plan.
manifest_id() {
  {
    cat "$MANIFEST"
    jq -r '[((.issues // [])[] | .comment_file, .body.file?), ((.new_issues // [])[] | .body_file)]
           | map(select(. != null)) | unique[]' "$MANIFEST" 2>/dev/null | while IFS= read -r f; do
      printf '\n== %s\n' "$f"; cat "$DIR/$f" 2>/dev/null || true
    done
  } | git hash-object --stdin
}
MANIFEST_ID="$(manifest_id)"

# ------------------------------------------------------------------ validate --

validate() {
  local errors
  errors="$(jq -r --arg dir "$DIR" '
    def file_ok($f): ($f | type) == "string" and ($f | length) > 0;
    [ (if .version != 1 then "version must be 1" else empty end),
      (if ((.repo // "") | test("^[^/ ]+/[^/ ]+$") | not) then "repo must be owner/name" else empty end),
      (if ((.marker // "") | length) == 0 then "marker is required" else empty end),
      ((.issues // []) | group_by(.number)[] | select(length > 1) | "issue #\(.[0].number) listed twice"),
      ((.new_issues // []) | group_by(.key)[] | select(length > 1) | "new issue \(.[0].key) listed twice"),
      ((.issues // [])[] |
        . as $r |
        (if ($r.number | type) != "number" then "an issue row has no number" else empty end),
        (if ($r.state // "open" | IN("open", "closed")) | not then "#\($r.number): state must be open or closed" else empty end),
        (if $r.state == "closed" and (($r.reason // "") | IN("completed", "not_planned", "duplicate") | not)
          then "#\($r.number): a closed row needs reason completed, not_planned or duplicate" else empty end),
        (if $r.reason == "duplicate" and ($r.duplicate_of == null) then "#\($r.number): duplicate needs duplicate_of" else empty end),
        (if $r.duplicate_of != null and $r.duplicate_of == $r.number then "#\($r.number): duplicate of itself" else empty end),
        (if $r.body != null and (($r.body.mode // "") | IN("prepend", "append") | not)
          then "#\($r.number): body.mode must be prepend or append" else empty end),
        (if $r.status != null and $root.project == null then "#\($r.number): status needs a project" else empty end)
      ),
      ((.new_issues // [])[] |
        (if ((.title // "") | length) == 0 then "new issue \(.key): title is required" else empty end),
        (if file_ok(.body_file) | not then "new issue \(.key): body_file is required" else empty end))
    ] | .[]' --argjson root "$(jq '{project}' "$MANIFEST")" "$MANIFEST" 2>&1)" || die 2 "manifest is not valid JSON: $errors"
  local f missing=""
  for f in $(jq -r '[((.issues // [])[] | .comment_file, .body.file?), ((.new_issues // [])[] | .body_file)] | .[] | select(. != null)' "$MANIFEST"); do
    [ -f "$DIR/$f" ] || missing="$missing
text file missing: $f"
  done
  errors="$errors$missing"
  if [ -n "$(printf '%s' "$errors" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$errors" | sed '/^$/d' >&2
    exit 2
  fi
}

# --------------------------------------------------------------------- gh io --

REPO="$(jq -r .repo "$MANIFEST")"
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"
MARKER="$(jq -r .marker "$MANIFEST")"
HAS_PROJECT="$(jq -r 'if .project then "yes" else "no" end' "$MANIFEST")"
STATUS_FIELD="$(jq -r '.project.status_field // "Status"' "$MANIFEST")"

# Runs a write. Classifies a failure so the caller stops on the right exit code.
gh_write() {
  local err="$WORK/err"
  if gh "$@" > "$WORK/out" 2> "$err"; then
    return 0
  fi
  if grep -qi 'rate limit' "$err"; then
    cat "$err" >&2; die 5 "rate limited on: gh $*"
  fi
  if grep -qiE 'Resource not accessible|INSUFFICIENT_SCOPES|HTTP 401|HTTP 403|must have .* permission|not authorized' "$err"; then
    cat "$err" >&2; die 4 "permission denied on: gh $* — stopping; nothing after this was run"
  fi
  cat "$err" >&2; die 1 "failed: gh $*"
}

fetch_issue() {
  local n="$1" proj="" fvar="" fdecl=""
  if [ "$HAS_PROJECT" = yes ]; then
    proj='projectItems(first:20){nodes{id project{number owner{... on Organization{login} ... on User{login}}} fieldValueByName(name:$f){... on ProjectV2ItemFieldSingleSelectValue{name}}}}'
    fvar="f=$STATUS_FIELD"; fdecl=',$f:String!'
  fi
  # GraphQL rejects a declared variable the query does not use, so $f exists only with a project.
  gh api graphql -F n="$n" -f o="$OWNER" -f r="$NAME" ${fvar:+-f "$fvar"} -f query='
    query($o:String!,$r:String!,$n:Int!'"$fdecl"'){repository(owner:$o,name:$r){issue(number:$n){
      id number state stateReason duplicateOf{number} title body issueType{name}
      labels(first:100){nodes{name}} milestone{title} parent{number} comments(last:100){nodes{body}}
      '"$proj"'}}}' | jq --argjson pn "$(jq '.project.number // 0' "$MANIFEST")" --arg po "$(jq -r '.project.owner // ""' "$MANIFEST")" '
      .data.repository.issue as $i
      | if $i == null then error("issue not found") else . end
      | {number: $i.number, id: $i.id, state: ($i.state | ascii_downcase),
         reason: ($i.stateReason // null | if . then ascii_downcase else null end),
         dup: $i.duplicateOf.number, title: $i.title, body: ($i.body // ""),
         type: $i.issueType.name, labels: [$i.labels.nodes[].name], milestone: $i.milestone.title,
         parent: $i.parent.number, comments: [$i.comments.nodes[].body],
         item: ([($i.projectItems.nodes // [])[] | select(.project.number == $pn and .project.owner.login == $po)
                 | {id, status: .fieldValueByName.name}] | first)}' 2>/dev/null \
    || die 1 "could not read #$n in $REPO"
}

fetch_context() {
  local ctx='{"project":null}'
  if [ "$HAS_PROJECT" = yes ]; then
    ctx="$(gh api graphql -f o="$(jq -r .project.owner "$MANIFEST")" -F n="$(jq .project.number "$MANIFEST")" -f f="$STATUS_FIELD" -f query='
      query($o:String!,$n:Int!,$f:String!){repositoryOwner(login:$o){
        ... on Organization{projectV2(number:$n){...P}} ... on User{projectV2(number:$n){...P}}}}
      fragment P on ProjectV2{id title workflows(first:50){nodes{name enabled}}
        field(name:$f){... on ProjectV2SingleSelectField{id options{id name}}}}' 2>/dev/null \
      | jq '.data.repositoryOwner.projectV2 as $p | if $p == null then error("no project") else . end
            | {project: {id: $p.id, title: $p.title, field: $p.field.id,
                         options: ([$p.field.options[]? | {key: .name, value: .id}] | from_entries),
                         workflows: [$p.workflows.nodes[] | select(.enabled) | .name]}}' 2>/dev/null)" \
      || die 3 "cannot read project $(jq -r '"\(.project.owner)/\(.project.number)"' "$MANIFEST") — the token needs read:project"
  fi
  local ms
  ms="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '[.[] | {title, number, state}]')" || die 1 "cannot list milestones"
  printf '%s' "$ctx" | jq --argjson ms "$ms" '. + {milestones: $ms}'
}

# ---------------------------------------------------------------------- plan --

# Writes $WORK/ops.json: the ordered writes needed to reach the manifest from live state.
compute_ops() {
  local n rows
  rows="$(jq -c --arg only "$ONLY" '
    ($only | split(",") | map(select(length > 0) | tonumber)) as $o
    | [(.issues // [])[] | select(.skip != true) | select(($o | length) == 0 or (.number as $n | $o | index($n)))]' "$MANIFEST")"
  echo '{}' > "$WORK/live.json"
  for n in $(printf '%s' "$rows" | jq -r '.[].number') $(jq -r '.[]' "$CREATED"); do
    fetch_issue "$n" > "$WORK/one.json"
    jq --slurpfile one "$WORK/one.json" --arg n "$n" '. + {($n): $one[0]}' "$WORK/live.json" > "$WORK/live.next" && mv "$WORK/live.next" "$WORK/live.json"
  done
  fetch_context > "$WORK/ctx.json"

  jq -n --argjson rows "$rows" --slurpfile m "$MANIFEST" --slurpfile live "$WORK/live.json" \
     --slurpfile ctx "$WORK/ctx.json" --slurpfile created "$CREATED" --arg only "$ONLY" '
    $m[0] as $m | $live[0] as $live | $ctx[0] as $ctx | $created[0] as $created
    | ("<!-- issue-triage:" + $m.marker + ":note -->") as $note
    | ("<!-- issue-triage:" + $m.marker + ":comment -->") as $cmark
    | def resolve($x): if ($x | type) == "string" and ($x | startswith("new:"))
                       then $created[$x | ltrimstr("new:")] else $x end;
      def has_any($arr; $s): any($arr[]; contains($s));
      def row_ops($r; $l):
        $r.number as $n
        | (if $r.title != null and $r.title != $l.title then {n: $n, op: "title", arg: $r.title} else empty end),
          (if $r.type != null and $r.type != $l.type then {n: $n, op: "type", arg: $r.type} else empty end),
          (($r.labels.add // [])[] | select(. as $x | ($l.labels | index($x)) == null) | {n: $n, op: "label-add", arg: .}),
          (($r.labels.remove // [])[] | select(. as $x | ($l.labels | index($x)) != null) | {n: $n, op: "label-remove", arg: .}),
          (if $r.milestone != null and $r.milestone != $l.milestone then {n: $n, op: "milestone", arg: $r.milestone} else empty end),
          (if $m.project != null and $r.project != false and $l.item == null then {n: $n, op: "project-add"} else empty end),
          (resolve($r.parent) as $p | if $p != null and $p != $l.parent then {n: $n, op: "parent", arg: $p, replace: ($l.parent != null)} else empty end),
          (if $r.body != null and ($l.body | contains($note) | not) then {n: $n, op: "body", arg: $r.body.file, mode: $r.body.mode} else empty end),
          (if $r.comment_file != null and (has_any($l.comments; $cmark) | not) then {n: $n, op: "comment", arg: $r.comment_file} else empty end),
          (resolve($r.duplicate_of) as $d
           | if ($r.state // null) == "closed" then
               if $l.state == "open" then
                 (if $r.reason == "duplicate" and $d == null then empty
                  else {n: $n, op: "close", arg: $r.reason, dup: $d} end)
               elif $r.reason == "duplicate" then
                 (if $d != null and ($l.reason != "duplicate" or $l.dup != $d) then {n: $n, op: "redup", dup: $d} else empty end)
               elif $l.reason != $r.reason then {n: $n, op: "reason", arg: $r.reason}
               else empty end
             elif ($r.state // null) == "open" and $l.state == "closed" then {n: $n, op: "reopen"}
             else empty end),
          (if $r.status != null and ($l.item.status // null) != $r.status
           then {n: $n, op: "status", arg: $r.status, stays_open: (($r.state // $l.state) == "open")} else empty end);
    [ ( if ($only | length) == 0 then ($m.new_issues // [])[] | select($created[.key] == null)
          | {n: ("new:" + .key), op: "create", arg: .title, body: .body_file} else empty end ),
      ( $rows[] | . as $r | row_ops($r; $live[$r.number | tostring]) ),
      ( if ($only | length) == 0 then ($m.new_issues // [])[] | select($created[.key] != null)
          | . as $ni | ($ni + {number: $created[$ni.key], labels: {add: ($ni.labels // [])}, state: null})
          | . as $r | row_ops($r; $live[$r.number | tostring]) else empty end ),
      ( if ($only | length) == 0 then ($m.milestones_close // [])[] as $t
          | ($ctx.milestones[] | select(.title == $t)) as $ms
          | if $ms.state == "open" then {n: ("milestone:" + $t), op: "milestone-close", arg: $ms.number} else empty end
        else empty end ) ]' > "$WORK/ops.json"

  # A Status that a board workflow turns into a close must not be set on an issue meant to stay open.
  local closing
  closing="$(jq -r --slurpfile ctx "$WORK/ctx.json" --slurpfile m "$MANIFEST" '
    ($m[0].project.closed_status // null) as $cs
    | if $cs != null and any(($ctx[0].project.workflows // [])[]; test("auto.?close"; "i"))
      then [.[] | select(.op == "status" and .stays_open and .arg == $cs) | "#\(.n)"] | join(" ") else "" end' "$WORK/ops.json")"
  [ -z "$closing" ] || die 2 "Status \"$(jq -r .project.closed_status "$MANIFEST")\" auto-closes issues on this board; it is set on rows meant to stay open: $closing"
}

print_ops() {
  jq -r '.[] | "\(.n)\t\(.op)\t\(
    if .op == "close" then .arg + (if .dup then " of #\(.dup)" else "" end)
    elif .op == "redup" then "reopen, close as duplicate of #\(.dup)"
    elif .op == "parent" then "#\(.arg)" + (if .replace then " (replaces current parent)" else "" end)
    elif .op == "body" then "\(.mode) \(.arg)"
    else (.arg // "" | tostring) end)"' "$WORK/ops.json"
  echo "manifest $MANIFEST_ID ops $(jq length "$WORK/ops.json")"
}

# ---------------------------------------------------------------- preflight --

preflight() {
  local login scopes problems=""
  login="$(gh api user --jq .login 2>/dev/null)" || die 3 "gh is not authenticated"
  scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1) == "x-oauth-scopes" {print $2}')"
  echo "identity: $login${GH_TOKEN:+ (from GH_TOKEN in the environment)} · scopes: ${scopes:-unknown (fine-grained token)}"
  if [ "$HAS_PROJECT" = yes ] && [ -n "$scopes" ] && ! printf '%s' "$scopes" | grep -qw project; then
    if [ -n "${GH_TOKEN:-}" ]; then
      problems="$problems
GH_TOKEN in the environment overrides the stored gh login and lacks the project scope"
    else
      problems="$problems
token lacks the project scope: gh auth refresh -s project"
    fi
    printf '%s\n' "$problems" | sed '/^$/d' >&2
    exit 3
  fi

  gh label list -R "$REPO" --limit 1000 --json name --jq '.[].name' > "$WORK/labels" || die 3 "cannot list labels"
  gh api graphql -f o="$OWNER" -f r="$NAME" -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:50){nodes{name}}}}' \
    --jq '.data.repository.issueTypes.nodes[]?.name' > "$WORK/types" || die 3 "cannot list issue types"
  fetch_context > "$WORK/ctx.json"

  local x
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    grep -qxF "$x" "$WORK/labels" || problems="$problems
label does not exist: $x (labels-sync owns the label set)"
  done < <(jq -r '[((.issues // [])[] | .labels.add[]?), ((.new_issues // [])[] | .labels[]?)] | unique[]' "$MANIFEST")
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    grep -qxF "$x" "$WORK/types" || problems="$problems
issue type does not exist: $x"
  done < <(jq -r '[(.issues // [])[], (.new_issues // [])[] | .type // empty] | unique[]' "$MANIFEST")
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    jq -e --arg x "$x" '.project.options[$x]' "$WORK/ctx.json" >/dev/null || problems="$problems
status option does not exist: $x"
  done < <(jq -r '[(.issues // [])[], (.new_issues // [])[] | .status // empty] | unique[]' "$MANIFEST")
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    jq -e --arg x "$x" '.milestones[] | select(.title == $x)' "$WORK/ctx.json" >/dev/null || problems="$problems
milestone does not exist: $x"
  done < <(jq -r '[((.issues // [])[] | .milestone // empty), (.milestones_close // [])[]] | unique[]' "$MANIFEST")

  if [ "$HAS_PROJECT" = yes ]; then
    echo "project: $(jq -r '.project.title' "$WORK/ctx.json") · workflows on: $(jq -r '.project.workflows | join(", ")' "$WORK/ctx.json")"
  fi
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" | sed '/^$/d' >&2
    exit 3
  fi
  echo "preflight ok"
}

# --------------------------------------------------------------------- apply --

item_for() {
  # Project item id for issue $1: one added this run, else the live one.
  if [ -f "$WORK/item.$1" ]; then cat "$WORK/item.$1"; else jq -r --arg n "$1" '.[$n].item.id // empty' "$WORK/live.json"; fi
}

compose() {
  # compose <kind> <file> → a temp file with the text and its hidden marker
  local out="$WORK/text.$RANDOM"
  { cat "$DIR/$2"; printf '\n<!-- issue-triage:%s:%s -->\n' "$MARKER" "$1"; } > "$out"
  printf '%s' "$out"
}

exec_op() {
  local op="$1" n arg
  n="$(printf '%s' "$op" | jq -r .n)"; arg="$(printf '%s' "$op" | jq -r '.arg // empty')"
  case "$(printf '%s' "$op" | jq -r .op)" in
    title) gh_write issue edit "$n" -R "$REPO" --title "$arg" ;;
    type) gh_write issue edit "$n" -R "$REPO" --type "$arg" ;;
    label-add) gh_write issue edit "$n" -R "$REPO" --add-label "$arg" ;;
    label-remove) gh_write issue edit "$n" -R "$REPO" --remove-label "$arg" ;;
    milestone) gh_write issue edit "$n" -R "$REPO" --milestone "$arg" ;;
    project-add)
      gh_write project item-add "$(jq .project.number "$MANIFEST")" --owner "$(jq -r .project.owner "$MANIFEST")" \
        --url "https://github.com/$REPO/issues/$n" --format json
      jq -r .id "$WORK/out" > "$WORK/item.$n" ;;
    parent)
      local child; child="$(gh api "repos/$REPO/issues/$n" --jq .id)" || die 1 "cannot read #$n"
      if [ "$(printf '%s' "$op" | jq -r .replace)" = true ]; then
        gh_write api -X POST "repos/$REPO/issues/$arg/sub_issues" -F sub_issue_id="$child" -F replace_parent=true
      else
        gh_write api -X POST "repos/$REPO/issues/$arg/sub_issues" -F sub_issue_id="$child"
      fi ;;
    body)
      local text body="$WORK/body.$n"
      text="$(compose note "$arg")"
      gh api "repos/$REPO/issues/$n" --jq '.body // ""' > "$WORK/orig.$n" || die 1 "cannot read #$n"
      if [ "$(printf '%s' "$op" | jq -r .mode)" = prepend ]; then
        { cat "$text"; printf '\n'; cat "$WORK/orig.$n"; } > "$body"
      else
        { cat "$WORK/orig.$n"; printf '\n\n'; cat "$text"; } > "$body"
      fi
      gh_write issue edit "$n" -R "$REPO" --body-file "$body" ;;
    comment) gh_write issue comment "$n" -R "$REPO" --body-file "$(compose comment "$arg")" ;;
    close)
      case "$arg" in
        duplicate) gh_write issue close "$n" -R "$REPO" --duplicate-of "$(printf '%s' "$op" | jq -r .dup)" ;;
        not_planned) gh_write issue close "$n" -R "$REPO" --reason "not planned" ;;
        *) gh_write issue close "$n" -R "$REPO" --reason completed ;;
      esac ;;
    reason) gh_write api -X PATCH "repos/$REPO/issues/$n" -f state=closed -f state_reason="$arg" ;;
    redup)
      gh_write issue reopen "$n" -R "$REPO"
      gh_write issue close "$n" -R "$REPO" --duplicate-of "$(printf '%s' "$op" | jq -r .dup)" ;;
    reopen) gh_write issue reopen "$n" -R "$REPO" ;;
    status)
      local item; item="$(item_for "$n")"
      [ -n "$item" ] || die 1 "#$n is not on the project; cannot set $arg"
      gh_write project item-edit --id "$item" --project-id "$(jq -r .project.id "$WORK/ctx.json")" \
        --field-id "$(jq -r .project.field "$WORK/ctx.json")" \
        --single-select-option-id "$(jq -r --arg s "$arg" '.project.options[$s]' "$WORK/ctx.json")"
      if [ "$(printf '%s' "$op" | jq -r .stays_open)" = true ]; then
        sleep "$SETTLE"
        [ "$(gh issue view "$n" -R "$REPO" --json state --jq .state)" = OPEN ] \
          || die 6 "a board workflow closed #$n when its Status became \"$arg\"; nothing after this was run"
      fi ;;
    create)
      local key="${n#new:}" url
      gh_write issue create -R "$REPO" --title "$arg" --body-file "$(compose "new:$key" "$(printf '%s' "$op" | jq -r .body)")"
      url="$(tail -n 1 "$WORK/out")"
      jq --arg k "$key" --argjson v "${url##*/}" '. + {($k): $v}' "$CREATED" > "$CREATED.next" && mv "$CREATED.next" "$CREATED"
      n="#${url##*/} (new:$key)" ;;
    milestone-close) gh_write api -X PATCH "repos/$REPO/milestones/$arg" -f state=closed ;;
  esac
  printf 'done\t%s\t%s\t%s\n' "$n" "$(printf '%s' "$op" | jq -r .op)" "$arg"
  sleep "$PAUSE"
}

run_pass() {
  compute_ops
  local count i
  count="$(jq length "$WORK/ops.json")"
  i=0
  while [ "$i" -lt "$count" ]; do
    exec_op "$(jq -c ".[$i]" "$WORK/ops.json")"
    i=$((i + 1))
  done
  CREATED_THIS_PASS="$(jq '[.[] | select(.op == "create")] | length' "$WORK/ops.json")"
}

# ---------------------------------------------------------------------- main --

validate
case "$CMD" in
  preflight) preflight ;;
  plan) compute_ops; print_ops ;;
  audit)
    compute_ops
    if [ "$(jq length "$WORK/ops.json")" -eq 0 ]; then echo "audit: live state matches manifest $MANIFEST_ID"; exit 0; fi
    print_ops; echo "audit: $(jq length "$WORK/ops.json") writes still differ" >&2; exit 6 ;;
  apply)
    [ -n "$EXPECT" ] || die 2 "apply needs --expect <manifest id> from the approved plan"
    [ "$EXPECT" = "$MANIFEST_ID" ] || die 2 "manifest changed since the approved plan ($EXPECT, now $MANIFEST_ID); re-plan and re-approve"
    run_pass
    # New issues get their type, labels, parent and status once they exist.
    if [ "$CREATED_THIS_PASS" -gt 0 ]; then run_pass; fi
    echo "applied manifest $MANIFEST_ID" ;;
  *) usage ;;
esac
