#!/bin/bash
# existing-work.sh <issue-number | issue-url>
# Finds work already started or finished on an issue, so solve-issue does not
# implement it a second time. Read-only: gh queries and local git reads. It
# never fetches, so remote branches are as of the last fetch.
#
# Output, one KEY=VALUE per line, VERDICT always last:
#   CURRENT=<branch>
#   OPEN_PR=<number> <author> <head-branch>   open PR that closes the issue or is named after it
#   MERGED_PR=<number> <head-branch>          merged PR that closes the issue
#   BRANCH=<ref> <commits-ahead>              issue branch with commits not on the default branch
#   GH=unavailable                            gh failed; PRs were not checked
#   VERDICT=own-branch | merged | in-progress | clear
#
# own-branch wins over everything: the current branch is the issue's branch, or
# the head of an open PR that closes it, so the caller already knows the work —
# unless that branch is the head of an already-merged closing PR and of no open
# one, which is a leftover branch, so merged wins.
#
# Exit codes: 0 = answered, 1 = not a git repository, 2 = usage

N="${1##*/issues/}"
N="${N%%[/?#]*}"
case "$N" in
  '' | *[!0-9]*)
    echo "usage: existing-work.sh <issue-number | issue-url>" >&2
    exit 2
    ;;
esac

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

names_issue() {
  case "${1#origin/}" in
    issue-"$N" | issue-"$N"-* | "$N"-* | */"$N"-* | */issue-"$N" | */issue-"$N"-*) return 0 ;;
  esac
  return 1
}

closes_issue() {
  case ",$1," in
    *",$N,"*) return 0 ;;
  esac
  return 1
}

current=$(git branch --show-current 2>/dev/null)
echo "CURRENT=$current"

# Unit separator, not tab: a tab is IFS whitespace, so an empty field would collapse.
US=$(printf '\037')
own=0
open_head=0
if [ -n "$current" ] && names_issue "$current"; then
  own=1
fi

open_found=0
merged_found=0
gh_ok=1

open_prs=$(gh pr list --state open --limit 100 \
  --json number,author,headRefName,closingIssuesReferences \
  --jq '.[] | [.number, .author.login, .headRefName, ([.closingIssuesReferences[].number] | join(","))] | map(tostring) | join("\u001f")' \
  2>/dev/null) || gh_ok=0

if [ "$gh_ok" = 1 ] && [ -n "$open_prs" ]; then
  while IFS="$US" read -r num author head closing; do
    [ -n "$num" ] || continue
    if closes_issue "$closing" || names_issue "$head"; then
      if [ "$head" = "$current" ]; then
        own=1
        open_head=1
      fi
      echo "OPEN_PR=$num $author $head"
      open_found=1
    fi
  done <<EOF
$open_prs
EOF
fi

if [ "$gh_ok" = 1 ]; then
  merged_prs=$(gh pr list --state merged --limit 50 --search "$N" \
    --json number,headRefName,closingIssuesReferences \
    --jq '.[] | [.number, .headRefName, ([.closingIssuesReferences[].number] | join(","))] | map(tostring) | join("\u001f")' \
    2>/dev/null) || gh_ok=0
  if [ "$gh_ok" = 1 ] && [ -n "$merged_prs" ]; then
    while IFS="$US" read -r num head closing; do
      [ -n "$num" ] || continue
      if closes_issue "$closing"; then
        echo "MERGED_PR=$num $head"
        merged_found=1
        if [ "$head" = "$current" ] && [ "$open_head" = 0 ]; then
          own=0
        fi
      fi
    done <<EOF
$merged_prs
EOF
  fi
fi

[ "$gh_ok" = 1 ] || echo "GH=unavailable"

base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
if [ -z "$base" ]; then
  for candidate in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$candidate" > /dev/null; then
      base="$candidate"
      break
    fi
  done
fi

branch_found=0
if [ -n "$base" ]; then
  locals=" $(git for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ') "
  for ref in $(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin); do
    case "$ref" in
      origin | origin/HEAD) continue ;;
    esac
    names_issue "$ref" || continue
    [ "$ref" = "$current" ] && continue
    # A remote branch with a local twin is reported once, as the local one.
    case "$ref" in
      origin/*)
        case "$locals" in *" ${ref#origin/} "*) continue ;; esac
        ;;
    esac
    ahead=$(git rev-list --count "$base..$ref" 2>/dev/null) || continue
    if [ "$ahead" -gt 0 ]; then
      echo "BRANCH=$ref $ahead"
      branch_found=1
    fi
  done
fi

if [ "$own" = 1 ]; then
  echo "VERDICT=own-branch"
elif [ "$merged_found" = 1 ]; then
  echo "VERDICT=merged"
elif [ "$open_found" = 1 ] || [ "$branch_found" = 1 ]; then
  echo "VERDICT=in-progress"
else
  echo "VERDICT=clear"
fi
