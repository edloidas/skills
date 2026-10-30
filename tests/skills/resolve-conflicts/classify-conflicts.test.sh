#!/usr/bin/env bash
# classify-conflicts.sh — the counts and per-file codes that decide how each
# conflict gets resolved. A miscount sends a file down the wrong resolution
# path, so the codes matter more than the totals.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

CLASSIFY="skills/resolve-conflicts/scripts/classify-conflicts.sh"

classify() {
  run bash "$(script "$CLASSIFY")"
}

# The value of one `KEY=n` line from the counts block.
count_of() {
  printf '%s\n' "$STDOUT" | sed -n "s/^$1=//p"
}

# The code the report assigned to one path.
code_of() {
  printf '%s\n' "$STDOUT" | sed -n "s|^\\([A-Z][A-Z]\\) $1\$|\\1|p"
}

# A repo with `main` and a `feature` branch that conflict when merged. The
# conflicting change is left for the caller to make.
conflict_repo() {
  init_repo repo main
  cd repo
  commit "initial" shared.txt "original"
  git checkout --quiet -b feature
}

# Merges `feature` into `main` and leaves the work tree unmerged.
start_conflicted_merge() {
  git checkout --quiet main
  git merge --quiet feature > /dev/null 2>&1 || true
}

# ------------------------------------------------------------ conflict codes --

test_both_modified_counts_as_uu() {
  conflict_repo
  commit "theirs" shared.txt "theirs"
  git checkout --quiet main
  commit "ours" shared.txt "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 1 "$(count_of UU)" "UU count"
  assert_eq 1 "$(count_of TOTAL)" "TOTAL"
  assert_eq UU "$(code_of shared.txt)" "code for shared.txt"
}

test_both_added_counts_as_aa() {
  conflict_repo
  commit "theirs adds" added.txt "theirs"
  git checkout --quiet main
  commit "ours adds" added.txt "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 1 "$(count_of AA)" "AA count"
  assert_eq AA "$(code_of added.txt)" "code for added.txt"
}

test_delete_against_modify_counts_as_ud() {
  conflict_repo
  # theirs deletes the file, ours modifies it
  git rm --quiet shared.txt
  git commit --quiet -m "theirs deletes"
  git checkout --quiet main
  commit "ours modifies" shared.txt "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 1 "$(count_of UD)" "UD count"
  assert_eq UD "$(code_of shared.txt)" "code for shared.txt"
}

test_modify_against_delete_counts_as_du() {
  conflict_repo
  commit "theirs modifies" shared.txt "theirs"
  git checkout --quiet main
  git rm --quiet shared.txt
  git commit --quiet -m "ours deletes"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 1 "$(count_of DU)" "DU count"
  assert_eq DU "$(code_of shared.txt)" "code for shared.txt"
}

test_mixed_conflicts_are_counted_per_code() {
  conflict_repo
  commit "theirs edits shared" shared.txt "theirs"
  commit "theirs adds both" both.txt "theirs"
  commit "theirs adds gone" gone.txt "theirs"
  git checkout --quiet main
  commit "ours edits shared" shared.txt "ours"
  commit "ours adds both" both.txt "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  local total uu aa
  total="$(count_of TOTAL)"
  uu="$(count_of UU)"
  aa="$(count_of AA)"
  assert_eq "$total" "$((uu + aa + $(count_of DU) + $(count_of UD) + $(count_of DD) + $(count_of AU) + $(count_of UA)))" \
    "TOTAL against the sum of the per-code counts"
  assert_ne 0 "$total" "TOTAL"
}

# Every code the report claims to know has to appear in the counts block, even
# at zero, because callers parse it as a fixed set of keys.
test_every_known_code_is_reported_even_at_zero() {
  conflict_repo
  commit "theirs" shared.txt "theirs"
  git checkout --quiet main
  commit "ours" shared.txt "ours"
  start_conflicted_merge

  classify
  local code
  for code in DU UD UU AA DD AU UA TOTAL; do
    assert_ne "" "$(count_of "$code")" "$code line in the counts block"
  done
}

# `git status --short` shell-quotes any path with a space or a non-ASCII byte, and
# the report has to undo that: SKILL.md feeds each path straight into
# `git checkout --theirs <file>`, so a quoted one names a file that does not exist.
test_path_containing_a_space_is_reported_unquoted() {
  conflict_repo
  commit "theirs" "dir name/a file.txt" "theirs"
  git checkout --quiet main
  commit "ours" "dir name/a file.txt" "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "AA dir name/a file.txt" "files block"
  assert_not_contains "$STDOUT" '"dir name' "files block"
}

test_path_containing_non_ascii_is_reported_unescaped() {
  conflict_repo
  local name
  name="$(printf 'caf\303\251.txt')"
  commit "theirs" "$name" "theirs"
  git checkout --quiet main
  commit "ours" "$name" "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "AA $name" "files block"
  # git's own quoting would have rendered this as "caf\303\251.txt".
  assert_not_contains "$STDOUT" '\303' "files block"
}

# Paths are anchored to the repository root, not the caller's cwd. `--short` would
# honor status.relativePaths and emit "../a.txt" from a subdirectory, which is only
# usable from the exact directory the script happened to run in.
test_paths_are_relative_to_the_repository_root() {
  conflict_repo
  commit "theirs" "nested/dir/a.txt" "theirs"
  git checkout --quiet main
  commit "ours" "nested/dir/a.txt" "ours"
  start_conflicted_merge

  mkdir -p other
  cd other
  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "AA nested/dir/a.txt" "files block"
  assert_not_contains "$STDOUT" ".." "files block"
}

# And from the root those paths are directly usable, which is the contract SKILL.md
# relies on.
test_a_reported_path_is_usable_from_the_repository_root() {
  conflict_repo
  commit "theirs" "nested/dir/a file.txt" "theirs"
  git checkout --quiet main
  commit "ours" "nested/dir/a file.txt" "ours"
  start_conflicted_merge

  classify
  local reported
  reported="$(printf '%s\n' "$STDOUT" | sed -n 's/^AA //p')"
  assert_eq "nested/dir/a file.txt" "$reported" "reported path"
  git checkout --theirs "$reported"
  git add "$reported"
  assert_eq "" "$(git status --porcelain -z | tr '\0' '\n' | grep -E '^(UU|AA) ' || true)" \
    "remaining conflicts"
}

# ------------------------------------------------------------ delete/modify --

# The rating of one path in the delete-modify block.
rating_of() {
  printf '%s\n' "$STDOUT" | sed -n "s|^[A-Z][A-Z] \\([a-z]*\\) $1\$|\\1|p"
}

# main deletes shared.txt; feature rewrites it with the given content.
delete_against_modify() {
  conflict_repo
  printf '%s' "$1" > shared.txt
  git commit --quiet -am "theirs modifies"
  git checkout --quiet main
  git rm --quiet shared.txt
  git commit --quiet -m "ours deletes"
  start_conflicted_merge
}

# A real edit on the surviving side is the work an unconditional `git rm` would
# have thrown away.
test_du_with_a_substantive_change_is_rated_substantive() {
  delete_against_modify 'original
new logic
'
  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq DU "$(code_of shared.txt)" "code for shared.txt"
  assert_eq substantive "$(rating_of shared.txt)" "rating"
  assert_contains "$(git status --porcelain)" "DU shared.txt" "still unresolved"
}

test_du_with_a_whitespace_only_change_is_rated_trivial() {
  delete_against_modify '  original

'
  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_eq trivial "$(rating_of shared.txt)" "rating"
}

test_ud_with_a_substantive_change_is_rated_substantive() {
  conflict_repo
  git rm --quiet shared.txt
  git commit --quiet -m "theirs deletes"
  git checkout --quiet main
  commit "ours modifies" shared.txt "more"
  start_conflicted_merge

  classify
  assert_eq UD "$(code_of shared.txt)" "code for shared.txt"
  assert_eq substantive "$(rating_of shared.txt)" "rating"
}

test_delete_modify_rates_a_path_containing_a_space() {
  conflict_repo
  commit "base" "dir name/a file.txt" "base"
  git checkout --quiet main
  git merge --quiet feature
  git checkout --quiet feature
  commit "theirs modifies" "dir name/a file.txt" "more"
  git checkout --quiet main
  git rm --quiet "dir name/a file.txt"
  git commit --quiet -m "ours deletes"
  start_conflicted_merge

  classify
  assert_contains "$STDOUT" "DU substantive dir name/a file.txt" "delete-modify block"
}

# Callers parse the block by its header, so it is there even with no DU/UD.
test_delete_modify_header_is_printed_without_entries() {
  conflict_repo
  commit "theirs" shared.txt "theirs"
  git checkout --quiet main
  commit "ours" shared.txt "ours"
  start_conflicted_merge

  classify
  assert_eq "# delete-modify" "$(last_line "$STDOUT")" "last line"
}

# ------------------------------------------------------------ failure modes --

# A newline in a path splits the record, and the leading half still matches a
# conflict code — so the report would name a fabricated path and drop the real
# one. Refusing is the only honest answer a line-oriented format can give.
test_a_path_containing_a_newline_is_refused() {
  conflict_repo
  local nl
  nl="$(printf 'bad\nname.txt')"
  commit "theirs" "$nl" "theirs"
  git checkout --quiet main
  commit "ours" "$nl" "ours"
  start_conflicted_merge

  classify
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDERR" "contains a newline" "error output"
  # The fabricated half must not reach stdout as if it were a real path.
  assert_not_contains "$STDOUT" "AA bad" "files block"
}

# And the check must not fire on the ordinary case, including a path with a space,
# which is the one that superficially resembles a split record.
test_a_path_containing_a_space_does_not_trip_the_newline_check() {
  conflict_repo
  commit "theirs" "dir name/a file.txt" "theirs"
  git checkout --quiet main
  commit "ours" "dir name/a file.txt" "ours"
  start_conflicted_merge

  classify
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$STDERR" "newline" "error output"
}

test_outside_a_git_repository_exits_1() {
  mkdir -p empty
  cd empty
  classify
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Not a git repository" "error output"
}

test_clean_tree_exits_2() {
  init_repo repo main
  cd repo
  commit "initial"
  classify
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "No conflicts found" "error output"
}

# A merge that finished cleanly is not a conflict, and must not be reported as
# one just because the tree has staged changes.
test_staged_changes_without_conflicts_exit_2() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'staged\n' > staged.txt
  git add staged.txt
  classify
  assert_eq 2 "$STATUS" "exit status"
}

run_tests
