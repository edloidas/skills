#!/usr/bin/env bash
# tools/skills-release/scripts/release-analyze.sh — drives this repo's own release
# bump. Unlike the npm-release copy it parses conventional-commit prefixes with
# anchored regexes, so the classification is exact rather than a keyword guess,
# and it reads the version from marketplace.json rather than package.json.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

ANALYZE="tools/skills-release/scripts/release-analyze.sh"

analyze() {
  run bash "$(script "$ANALYZE")"
}

# A repo shaped like this one: a marketplace.json whose first plugin carries the
# version the script reports.
skills_repo() {
  local version="${1:-4.5.2}"
  init_repo repo main
  cd repo
  mkdir -p .claude-plugin
  printf '{"plugins":[{"name":"plan","version":"%s"}]}\n' "$version" > .claude-plugin/marketplace.json
  git add .claude-plugin
  git commit --quiet -m "chore: initial"
}

summary_of() {
  printf '%s\n' "$STDOUT" | sed -n "s/^$1: *//p"
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
  skills_repo
  unstub jq
  analyze
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "jq is required" "output"
}

test_version_comes_from_the_first_marketplace_plugin() {
  skills_repo 9.9.9
  analyze
  assert_contains "$STDOUT" "Current version: 9.9.9" "output"
}

test_no_tags_recommends_minor_as_a_first_release() {
  skills_repo
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No previous release tags found" "output"
  assert_contains "$(recommendation)" "MINOR bump (first release)" "recommendation"
}

test_no_new_commits_since_the_tag() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No new commits" "output"
}

# --------------------------------------------------------------- baseline ----
# The reason this file exists: the baseline must be a version tag, not whatever
# tag happens to be nearest.

test_a_non_version_tag_is_not_used_as_the_baseline() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat: a thing" a.txt
  git tag -a scratch -m "not a release"
  commit "fix: another thing" b.txt

  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Last release tag: v4.5.2" "output"
  assert_contains "$STDOUT" "Commits since last release: 2" "output"
}

test_only_non_version_tags_reports_a_first_release() {
  skills_repo
  git tag -a nightly -m "not a release"
  analyze
  assert_contains "$STDOUT" "No previous release tags found" "output"
}

# --------------------------------------------------------- classification ----
# Anchored regexes, so a prefix only counts at the start of the subject.

test_conventional_prefixes_are_counted_by_type() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat: a feature" a.txt
  commit "fix: a fix" b.txt
  commit "refactor: a refactor" c.txt
  commit "docs: a doc" d.txt
  commit "chore: a chore" e.txt
  commit "style: a style" f.txt
  commit "ci: a ci change" g.txt
  commit "test: a test" h.txt

  analyze
  assert_eq 1 "$(summary_of Features)" "Features"
  assert_eq 1 "$(summary_of Fixes)" "Fixes"
  assert_eq 1 "$(summary_of Refactoring)" "Refactoring"
  assert_eq 1 "$(summary_of Documentation)" "Documentation"
  assert_eq 1 "$(summary_of Chore)" "Chore"
  assert_eq 1 "$(summary_of Style)" "Style"
  assert_eq 1 "$(summary_of CI)" "CI"
  assert_eq 1 "$(summary_of Tests)" "Tests"
  assert_eq 0 "$(summary_of Other)" "Other"
}

test_a_scope_is_accepted_in_the_prefix() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat(plan): a scoped feature" a.txt
  analyze
  assert_eq 1 "$(summary_of Features)" "Features"
  assert_eq 0 "$(summary_of Other)" "Other"
}

# The anchor is the point: the npm-release copy counts "add" anywhere in a subject
# and would classify this as a feature.
test_a_type_word_mid_subject_is_not_counted() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "chore: add a fix for the feature docs" a.txt
  analyze
  assert_eq 0 "$(summary_of Features)" "Features"
  assert_eq 0 "$(summary_of Fixes)" "Fixes"
  assert_eq 1 "$(summary_of Chore)" "Chore"
}

test_an_unclassified_commit_counts_as_other() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "improvement: not a conventional type" a.txt
  analyze
  assert_eq 1 "$(summary_of Other)" "Other"
  assert_contains "$(recommendation)" "MANUAL review" "recommendation"
}

# --------------------------------------------------------------- breaking ----

test_a_bang_suffix_is_a_breaking_change() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat!: drop the old API" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "Breaking"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_a_bang_suffix_with_a_scope_is_a_breaking_change() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "refactor(plan)!: move everything" a.txt
  analyze
  assert_eq 1 "$(summary_of Breaking)" "Breaking"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_a_breaking_change_trailer_in_the_body_counts() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  printf 'x\n' > a.txt
  git add a.txt
  git commit --quiet -m "feat: a thing" -m "BREAKING CHANGE: the old flag is gone"
  analyze
  assert_eq 1 "$(summary_of Breaking)" "Breaking"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

# ---------------------------------------------------------- recommendation ----
# Precedence: breaking, then feature, then fix/refactor, then the low-risk types.

test_a_feature_recommends_minor() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat: a thing" a.txt
  commit "fix: a fix" b.txt
  analyze
  assert_contains "$(recommendation)" "MINOR bump" "recommendation"
}

test_fixes_alone_recommend_patch() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "fix: a fix" a.txt
  analyze
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

test_breaking_outranks_a_feature() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "feat: a plain feature" a.txt
  commit "fix!: a breaking fix" b.txt
  analyze
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

test_low_risk_types_alone_recommend_patch() {
  skills_repo
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "ci: tweak a workflow" a.txt
  commit "test: add a case" b.txt
  analyze
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

# `describe` only sees reachable tags. A branch that forked before the last release
# has version tags in the repo but none as an ancestor — and calling that a first
# release is a confidently wrong bump recommendation, not a missing one.
test_unreachable_version_tags_are_refused_not_called_a_first_release() {
  skills_repo
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

# ------------------------------------------------- removed-skill detection ----
# The conventional-commit counters above only see a breaking change when someone
# writes `!:` or a BREAKING CHANGE trailer. v5.0.0 deleted 17 skills and renamed 2
# under `refactor:` and `chore:` subjects, so the script reported Breaking: 0 and
# recommended MINOR. These cases pin the tree-based rule that replaces that trust.

# Adds a skill at the canonical path so the removal rule has something to lose.
add_skill() {
  local group="$1" name="$2"
  mkdir -p "$group/skills/$name"
  printf -- '---\nname: %s\ndescription: Test skill.\n---\n\nBody.\n' "$name" \
    > "$group/skills/$name/SKILL.md"
  git add "$group/skills/$name/SKILL.md"
  git commit --quiet -m "feat: add $name"
}

removed_section() {
  printf '%s\n' "$STDOUT" | sed -n '/^=== Skills Removed or Renamed Since /,/^$/p'
}

test_a_deleted_skill_forces_major_despite_a_refactor_subject() {
  skills_repo
  add_skill review adversarial-review
  git tag -a v4.5.2 -m "Release v4.5.2"
  git rm --quiet -r review/skills/adversarial-review
  git commit --quiet -m "refactor: merge adversarial-review into changes-review"
  analyze
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 0 "$(summary_of Breaking)" "conventional breaking count"
  assert_eq 1 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
  assert_contains "$(removed_section)" "adversarial-review (review)" "removed list"
}

# A rename is the case a user notices as "my slash command vanished", and it is the
# one `--diff-filter=D` alone would miss.
test_a_skill_renamed_across_groups_counts_as_removed() {
  skills_repo
  add_skill review test-quality
  git tag -a v4.5.2 -m "Release v4.5.2"
  mkdir -p audit/skills/tests-audit
  git mv review/skills/test-quality/SKILL.md audit/skills/tests-audit/SKILL.md
  git commit --quiet -m "chore: relocate misfiled skills"
  analyze
  assert_eq 1 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
  assert_contains "$(removed_section)" "test-quality (review)" "removed list"
}

test_removed_skills_outrank_a_feature() {
  skills_repo
  add_skill assist ask
  git tag -a v4.5.2 -m "Release v4.5.2"
  add_skill assist explain
  git rm --quiet -r assist/skills/ask
  git commit --quiet -m "refactor: replace the ask skill with explain"
  analyze
  assert_eq 1 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "MAJOR bump" "recommendation"
}

# Adding skills is not breaking, and must not be reported as such — a rule that
# fires on every release is a rule nobody reads.
test_added_skills_alone_do_not_force_major() {
  skills_repo
  add_skill assist explain
  git tag -a v4.5.2 -m "Release v4.5.2"
  add_skill audit tsconfig-audit
  analyze
  assert_eq 0 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "MINOR bump" "recommendation"
  assert_not_contains "$STDOUT" "Skills Removed or Renamed" "no removal section"
}

test_an_edited_skill_is_not_a_removal() {
  skills_repo
  add_skill review changes-review
  git tag -a v4.5.2 -m "Release v4.5.2"
  commit "refactor: rework changes-review" review/skills/changes-review/SKILL.md
  analyze
  assert_eq 0 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

# Files that merely live near a skill must not be mistaken for one, or a deleted
# reference file would advertise itself as a breaking change.
test_deleting_a_bundled_reference_is_not_a_removed_skill() {
  skills_repo
  add_skill review changes-review
  mkdir -p review/skills/changes-review/references
  commit "docs: add a reference" review/skills/changes-review/references/lenses.md
  git tag -a v4.5.2 -m "Release v4.5.2"
  git rm --quiet review/skills/changes-review/references/lenses.md
  git commit --quiet -m "refactor: fold the lens reference into the body"
  analyze
  assert_eq 0 "$(summary_of 'Skills gone')" "removed skill count"
  assert_contains "$(recommendation)" "PATCH bump" "recommendation"
}

run_tests
