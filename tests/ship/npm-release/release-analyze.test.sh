#!/usr/bin/env bash
# release-analyze.sh — read-only, and the input to the bump decision. It cannot
# break a release directly; it can recommend the wrong one.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

ANALYZE="ship/skills/npm-release/scripts/release-analyze.sh"

analyze() {
  run bash "$(script "$ANALYZE")"
}

pkg_repo() {
  local version="${1:-1.2.3}"
  init_repo repo main
  cd repo
  printf '{"name":"demo","version":"%s"}\n' "$version" > package.json
  git add package.json
  git commit --quiet -m "chore: initial"
}

# The value of one `Label: n` line from the summary block.
summary_of() {
  printf '%s\n' "$STDOUT" | sed -n "s/^$1: //p"
}

recommendation() {
  printf '%s\n' "$STDOUT" | sed -n '/^=== Recommendation ===$/,$p' | tail -n +2
}

# ------------------------------------------------------------- preconditions --

test_outside_a_git_repository_exits_1() {
  mkdir -p empty
  cd empty
  analyze
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Not a git repository" "output"
}

test_missing_jq_exits_1() {
  pkg_repo
  unstub jq
  analyze
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "jq is required" "output"
}

# ---------------------------------------------------------------- first release --

test_no_tags_reports_a_first_release() {
  pkg_repo 0.1.0
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No previous release tags found" "output"
  assert_contains "$STDOUT" "Current version: 0.1.0" "output"
  assert_contains "$STDOUT" "Recent commits" "output"
}

# ------------------------------------------------------------------- analysis --

test_no_new_commits_since_the_tag() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Last release tag: v1.2.3" "output"
  assert_contains "$STDOUT" "No new commits since last release" "output"
  assert_not_contains "$STDOUT" "=== Recommendation ===" "output"
}

test_commit_count_since_the_tag() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "fix: one" a.txt
  commit "fix: two" b.txt
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Commits since last release: 2" "output"
  assert_contains "$STDOUT" "fix: one" "commit history block"
  assert_contains "$STDOUT" "fix: two" "commit history block"
}

test_a_feature_commit_recommends_minor() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat: add a thing" a.txt
  analyze
  assert_eq 1 "$(summary_of Features)" "feature count"
  assert_contains "$(recommendation)" "MINOR bump" "recommendation"
}

test_a_breaking_commit_recommends_minor() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "breaking: drop the old API" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "MINOR bump" "recommendation"
}

test_only_fixes_recommend_patch() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "fix: correct the thing" a.txt
  analyze
  assert_eq 1 "$(summary_of Fixes)" "fix count"
  assert_eq 0 "$(summary_of Features)" "feature count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

test_only_refactors_recommend_patch() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "refactor: move the thing" a.txt
  analyze
  assert_eq 1 "$(summary_of Refactoring)" "refactor count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

test_only_docs_recommend_patch() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "docs: rewrite the readme" a.txt
  analyze
  assert_eq 1 "$(summary_of Documentation)" "docs count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

# A commit subject matching none of the patterns has to fall through to a human
# rather than default to a bump.
test_an_unclassifiable_commit_asks_for_manual_review() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "chore: bump the lockfile" a.txt
  analyze
  assert_contains "$(recommendation)" "MANUAL review needed" "recommendation"
}

# Every summary label the block claims has to be present, because the caller
# reads them as a fixed set.
test_every_summary_label_is_reported() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat: a thing" a.txt
  analyze
  local label
  for label in Features Fixes Refactoring Documentation Breaking; do
    assert_ne "" "$(summary_of "$label")" "$label line in the summary block"
  done
}

# The baseline must be a version tag. `git describe --tags --abbrev=0` alone takes
# the nearest reachable tag of any kind, so a scratch tag becomes the baseline and
# every count and the recommendation are measured from the wrong place.
test_a_non_version_tag_is_not_used_as_the_baseline() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat: a thing" a.txt
  git tag -a scratch -m "not a release"
  commit "fix: another thing" b.txt

  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Last release tag: v1.2.3" "output"
  assert_contains "$STDOUT" "Commits since last release: 2" "output"
}

# A lightweight scratch tag is the same hazard by a different route.
test_a_lightweight_non_version_tag_is_not_used_as_the_baseline() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat: a thing" a.txt
  git tag nightly
  commit "fix: another thing" b.txt

  analyze
  assert_contains "$STDOUT" "Last release tag: v1.2.3" "output"
  assert_contains "$STDOUT" "Commits since last release: 2" "output"
}

# A repo whose only tags are non-version ones has no baseline, which is the
# first-release path rather than a wrong measurement.
test_only_non_version_tags_reports_a_first_release() {
  pkg_repo 0.1.0
  git tag -a scratch -m "not a release"
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No previous release tags found" "output"
}

# `describe` only sees reachable tags. A branch that forked before the last release
# has version tags in the repo but none as an ancestor — and calling that a first
# release is a confidently wrong bump recommendation, not a missing one.
test_unreachable_version_tags_are_refused_not_called_a_first_release() {
  pkg_repo 1.2.3
  local root
  root="$(git rev-parse HEAD)"
  # The release line: tags land on commits after the fork point.
  commit "chore: release work" rel.txt
  git tag -a v1.0.0 -m "Release v1.0.0"
  commit "chore: more release work" rel.txt
  git tag -a v2.0.0 -m "Release v2.0.0"
  # This branch left before either tag, so neither is an ancestor of HEAD.
  git checkout --quiet -b forked-early "$root"
  commit "feat: work off the release line" a.txt
  assert_eq "" "$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)" \
    "reachable version tag from the forked branch"

  analyze
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "none is reachable from HEAD" "output"
  assert_contains "$STDOUT" "v2.0.0" "output names the newest tag"
  assert_not_contains "$STDOUT" "first release" "output"
}

run_tests
