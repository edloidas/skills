#!/usr/bin/env bash
# Regressions for issue creation side effects and Projects V2 discovery.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

ISSUE_TYPES="plan/skills/issue-flow/scripts/issue-types.sh"
CREATE_ISSUE="plan/skills/issue-flow/scripts/create-issue.sh"
SUGGEST_PROJECTS="plan/skills/issue-flow/scripts/suggest-projects.sh"
REPO_CONTEXT="plan/skills/issue-flow/scripts/repo-context.sh"
ADD_TO_PROJECT="plan/skills/issue-flow/scripts/add-to-project.sh"
CHECK_ENV="plan/skills/issue-flow/scripts/check-env.sh"

long_token() {
  printf '%s' 'ghp_123456789012345678901234567890123456'
}

test_issue_types_uses_graphql_not_rest_catalog() {
  stub gh <<'EOF'
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf '%s\n' '{"data":{"repository":{"isInOrganization":false,"issueTypes":null}}}'
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "repos/edloidas/lictor/issue-types" ]; then
  echo 'REST catalog should not be used' >&2
  exit 9
fi
echo "unexpected gh: $*" >&2
exit 1
EOF

  run bash "$(script "$ISSUE_TYPES")" edloidas/lictor
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "" "$STDOUT" "personal repo issue types"
}

test_issue_types_prints_org_types() {
  stub gh <<'EOF'
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf '%s\n' '{"data":{"repository":{"isInOrganization":true,"issueTypes":{"nodes":[{"name":"Task"},{"name":"Bug"}]}}}}'
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF

  run bash "$(script "$ISSUE_TYPES")" org/repo
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "Task
Bug" "$STDOUT" "org issue types"
}

test_check_env_requires_jq() {
  init_repo repo main
  cd repo
  stub gh <<'EOF'
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF
  unstub jq

  run bash "$(script "$CHECK_ENV")"
  assert_eq 4 "$STATUS" "exit status"
  assert_contains "$STDERR" "jq is not installed" "error"
}

test_create_issue_reuses_partial_create_after_gh_failure() {
  stub gh <<'EOF'
if [ "$1" = "issue" ] && [ "$2" = "create" ]; then
  printf '%s\n' "$*" >> "$SANDBOX/issue-create.calls"
  echo 'failed to add issue type Task' >&2
  exit 1
fi
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  echo 'edloidas'
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  printf '%s\n' '[{"number":86,"title":"Fix the bug","url":"https://github.com/ed/repo/issues/86","createdAt":"2000-01-01T00:00:01Z"}]'
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF

  run bash "$(script "$CREATE_ISSUE")" --started-at 2000-01-01T00:00:00Z -- \
    --title "Fix the bug" --body-file body.md --repo ed/repo --type Task

  assert_eq 0 "$STATUS" "exit status"
  assert_eq "https://github.com/ed/repo/issues/86" "$STDOUT" "reused issue URL"
  assert_contains "$STDERR" "reusing https://github.com/ed/repo/issues/86" "warning"
  assert_eq 1 "$(wc -l < "$SANDBOX/issue-create.calls" | tr -d ' ')" "create invocations"
}

test_create_issue_failure_without_match_stops_before_retry() {
  stub gh <<'EOF'
if [ "$1" = "issue" ] && [ "$2" = "create" ]; then
  printf '%s\n' "$*" >> "$SANDBOX/issue-create.calls"
  echo 'failed to add issue type Task' >&2
  exit 1
fi
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  echo 'edloidas'
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  printf '%s\n' '[]'
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF

  run bash "$(script "$CREATE_ISSUE")" --started-at 2000-01-01T00:00:00Z -- \
    --title "Fix the bug" --body-file body.md --repo ed/repo --type Task

  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Do not retry without manual reconciliation" "error"
  assert_eq 1 "$(wc -l < "$SANDBOX/issue-create.calls" | tr -d ' ')" "create invocations"
}

test_add_to_project_finds_user_owned_project() {
  stub gh <<EOF
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  echo '$(long_token)'
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
  echo 'ed/repo'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "graphql" ]; then
  case "\$*" in
    *'issue(number:'*)
      echo 'ISSUE_node'
      exit 0
      ;;
    *'repositoryOwner(login:'*)
      printf '%s\n' '{"data":{"repository":{"projectsV2":{"nodes":[]}},"repositoryOwner":{"projectsV2":{"nodes":[{"id":"PVT_user","title":"User Roadmap"}]}}}}'
      exit 0
      ;;
    *'addProjectV2ItemById'*)
      printf '%s\n' 'PVI_item'
      exit 0
      ;;
  esac
fi
echo "unexpected gh: \$*" >&2
exit 1
EOF

  run bash "$(script "$ADD_TO_PROJECT")" 86 "User Roadmap"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "SUCCESS: Issue #86 added to 'User Roadmap'" "output"
}

test_suggest_projects_zero_projects_exits_success() {
  stub gh <<EOF
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  echo '$(long_token)'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "user" ]; then
  echo 'edloidas'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "graphql" ]; then
  printf '%s\n' '{"data":{"repository":{"issues":{"nodes":[]},"projectsV2":{"nodes":[]}},"repositoryOwner":{"projectsV2":{"nodes":[]}}}}'
  exit 0
fi
echo "unexpected gh: \$*" >&2
exit 1
EOF

  run bash "$(script "$SUGGEST_PROJECTS")" ed/repo
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "" "$STDOUT" "suggestions"
}

test_suggest_projects_graphql_failure_names_scope_fix() {
  stub gh <<EOF
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  echo '$(long_token)'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "user" ]; then
  echo 'edloidas'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "graphql" ]; then
  echo 'GraphQL: Resource not accessible by integration' >&2
  exit 1
fi
echo "unexpected gh: \$*" >&2
exit 1
EOF

  run bash "$(script "$SUGGEST_PROJECTS")" ed/repo
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "GraphQL: Resource not accessible" "original error"
  assert_contains "$STDERR" "gh auth refresh -s read:project" "scope fix"
}

stub_repo_context_gh() {
  local owner_kind="$1"
  local projects_json="$2"
  stub gh <<EOF
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
  echo 'ed/repo'
  exit 0
fi
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "repos/ed/repo/collaborators" ]; then
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "repos/ed/repo/contributors" ]; then
  exit 0
fi
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  echo '$(long_token)'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "graphql" ]; then
  printf '%s\n' '{"data":{"repository":{"projectsV2":{"nodes":[]}},"repositoryOwner":{"__typename":"$owner_kind","projectsV2":{"nodes":$projects_json}}}}'
  exit 0
fi
echo "unexpected gh: \$*" >&2
exit 1
EOF
}

test_repo_context_graphql_failure_names_scope_fix() {
  stub gh <<EOF
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
  echo 'ed/repo'
  exit 0
fi
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "repos/ed/repo/collaborators" ]; then
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "repos/ed/repo/contributors" ]; then
  exit 0
fi
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  echo '$(long_token)'
  exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "graphql" ]; then
  echo 'GraphQL: Resource not accessible by integration' >&2
  exit 1
fi
echo "unexpected gh: \$*" >&2
exit 1
EOF

  run bash "$(script "$REPO_CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDERR" "GraphQL: Resource not accessible" "original error"
  assert_contains "$STDOUT" "gh auth refresh -s read:project" "scope fix"
}

test_repo_context_finds_user_owned_projects() {
  stub_repo_context_gh User '[{"id":"PVT_user","title":"User Roadmap","updatedAt":"2026-01-01T00:00:00Z"}]'
  run bash "$(script "$REPO_CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" $'PVT_user\tUser Roadmap' "projects"
  assert_not_contains "$STDOUT" "token lacks read:project" "projects"
}

test_repo_context_finds_org_owned_projects() {
  stub_repo_context_gh Organization '[{"id":"PVT_org","title":"Org Roadmap","updatedAt":"2026-01-01T00:00:00Z"}]'
  run bash "$(script "$REPO_CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" $'PVT_org\tOrg Roadmap' "projects"
  assert_not_contains "$STDOUT" "token lacks read:project" "projects"
}

test_repo_context_zero_projects_is_explicit_empty_result() {
  stub_repo_context_gh User '[]'
  run bash "$(script "$REPO_CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "(no projects found)" "projects"
  assert_not_contains "$STDOUT" "token lacks read:project" "projects"
}

run_tests
