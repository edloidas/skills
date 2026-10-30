#!/usr/bin/env bash
# release-analyze.sh — read-only, and the input to the bump decision. It cannot
# break a release directly; it can recommend the wrong one.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

ANALYZE="skills/npm-release/scripts/release-analyze.sh"

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

test_a_bang_subject_after_1_0_recommends_major() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat!: drop the old API" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_a_scoped_bang_subject_is_breaking() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "refactor(api)!: rename the entry point" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_a_breaking_change_footer_is_breaking() {
  pkg_repo 2.0.0
  git tag -a v2.0.0 -m "Release v2.0.0"
  FIXTURE_CLOCK=$((FIXTURE_CLOCK + 60))
  _git_dates
  printf 'x\n' > a.txt
  git add a.txt
  git commit --quiet -m "fix: tighten parsing" -m "BREAKING CHANGE: rejects trailing commas"
  analyze
  assert_eq 1 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_a_breaking_change_before_1_0_recommends_minor() {
  pkg_repo 0.4.1
  git tag -a v0.4.1 -m "Release v0.4.1"
  commit "feat!: drop the old API" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "MINOR bump" "recommendation"
}

test_a_breaking_change_with_a_non_semver_version_asks_for_review() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  printf '{"name":"demo"}\n' > package.json
  git add package.json
  git commit --quiet -m "chore: drop version"
  commit "feat!: drop the old API" a.txt
  analyze
  assert_contains "$(recommendation)" "MANUAL review needed" "recommendation"
}

test_break_inside_a_word_is_not_breaking() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "fix: breakfast menu no longer breaks the layout" a.txt
  analyze
  assert_eq 0 "$(summary_of Breaking)" "breaking count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

test_add_inside_a_word_is_not_a_feature() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "fix: address the padding regression" a.txt
  analyze
  assert_eq 0 "$(summary_of Features)" "feature count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

test_a_type_word_mid_subject_is_not_counted() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "chore: feat: and docs: mentioned in passing" a.txt
  analyze
  assert_eq 0 "$(summary_of Features)" "feature count"
  assert_eq 0 "$(summary_of Documentation)" "docs count"
  assert_contains "$(recommendation)" "MANUAL review needed" "recommendation"
}

test_a_scoped_feature_is_counted() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "feat(cli): add a flag" a.txt
  analyze
  assert_eq 1 "$(summary_of Features)" "feature count"
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

test_a_hash_spelling_a_keyword_is_not_counted() {
  pkg_repo 1.2.3
  git tag -a v1.2.3 -m "Release v1.2.3"
  commit "fix: correct the thing" a.txt
  local tries=0
  until git log --oneline -1 | cut -d' ' -f1 | grep -q add; do
    tries=$((tries + 1))
    [ "$tries" -le 20000 ] || fail "no short hash containing 'add' within 20000 amends"
    FIXTURE_CLOCK=$((FIXTURE_CLOCK + 1))
    _git_dates
    git commit --quiet --amend --no-edit
  done
  analyze
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
