#!/usr/bin/env bash
# check-spec.sh <spec-dir> <repo-root>
#
# Mechanical checks on a code-to-spec output tree (modules/, acceptance/, and
# contracts.md when present): record formats, case-kind coverage, orphan cases,
# dangling dependencies, inferred obligations without a basis, and every
# `path:line` citation against the repository. Prints one problem per line as
# `<spec file>:<line>: <problem>`, then a summary line.
#
# Exit: 0 no problems, 1 problems found, 2 usage error.

set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: check-spec.sh <spec-dir> <repo-root>" >&2
  exit 2
fi

spec="${1%/}"
root="${2%/}"

if [ ! -d "$spec/modules" ]; then
  echo "check-spec: no modules/ directory in $spec" >&2
  exit 2
fi
if [ ! -d "$root" ]; then
  echo "check-spec: repository root not found: $root" >&2
  exit 2
fi

set --
for f in "$spec"/modules/*.md "$spec"/contracts.md "$spec"/acceptance/*.md; do
  if [ -f "$f" ]; then set -- ${1+"$@"} "$f"; fi
done
if [ "$#" -eq 0 ]; then
  echo "check-spec: no spec files under $spec" >&2
  exit 2
fi

awk -v root="$root" -v spec="$spec/" '
function rel(f) { return index(f, spec) == 1 ? substr(f, length(spec) + 1) : f }
function problem(msg) { problems++; print rel(FILENAME) ":" FNR ": " msg }
function is_test(p,   name) {
  if (p ~ /(^|\/)(test|tests|__tests__|spec)\//) return 1
  name = p; sub(/.*\//, "", name)
  return name ~ /(\.test\.|\.spec\.|_test\.|-test\.|_spec\.|^test_|Test\.java$|Tests\.java$|Tests\.cs$|IT\.java$)/
}
function line_count(p,   path, n, l, r) {
  if (p in lines) return lines[p]
  path = root "/" p; n = 0
  while ((r = (getline l < path)) > 0) n++
  close(path)
  lines[p] = (r < 0 && n == 0) ? -1 : n
  return lines[p]
}
function check_citations(s,   span, body, path, rest, parts, i, a, hi, n, ext) {
  while (match(s, /`[^`]+`/)) {
    span = substr(s, RSTART + 1, RLENGTH - 2)
    s = substr(s, RSTART + RLENGTH)
    if (span !~ /^[A-Za-z0-9_.\/-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$/) continue
    path = span; sub(/:.*/, "", path)
    rest = span; sub(/^[^:]*:/, "", rest)
    if (substr(path, 1, 1) == "/") { citations++; problem("absolute path in citation `" span "`"); continue }
    if (path !~ /\//) {
      ext = path; sub(/.*\./, "", ext)
      if (ext ~ /^(java|kt|kts|scala|ts|tsx|js|jsx|mjs|cjs|py|go|rs|cs|rb|php|swift|c|h|cc|cpp|hpp|sh|sql|xml|yml|yaml|json|html|md|toml|gradle|properties)$/) {
        citations++; problem("citation without a repository path `" span "`")
      }
      continue
    }
    citations++
    n = line_count(path)
    if (n < 0) { problem("cited file not found `" span "`"); continue }
    hi = 0
    split(rest, parts, ",")
    for (i in parts) { a = parts[i]; sub(/^[0-9]+-/, "", a); if (a + 0 > hi) hi = a + 0 }
    if (hi > n) problem("cited line " hi " is past the end of " path " (" n " lines)")
  }
}
function close_ob() {
  if (cur_ob != "" && cur_state == "inferred" && !cur_basis) {
    problems++; print cur_where ": inferred obligation " cur_ob " has no Basis line"
  }
  if (cur_ob != "" && !cur_cases) {
    problems++; print cur_where ": obligation " cur_ob " has no Cases line"
  }
  cur_ob = ""
}
function close_ac() {
  if (cur_ac != "" && !cur_source) { problems++; print cur_ac_where ": case " cur_ac " has no Source line" }
  cur_ac = ""
}
FNR == 1 { close_ob(); close_ac(); in_acc = (FILENAME ~ /\/acceptance\//) }
/^### / { close_ob(); close_ac() }
!in_acc && /^### OB-/ {
  if ($0 !~ /^### OB-[a-z0-9-]+-[0-9][0-9][0-9] · (interface|data|rule|state|error|config|integration|timing) · (observed|inferred|unknown)$/) {
    problem("malformed obligation heading: " $0); next
  }
  id = $2; state = $NF
  if (id in ob_where) problem("duplicate obligation " id)
  ob_where[id] = rel(FILENAME) ":" FNR; obligations++
  cur_ob = id; cur_state = state; cur_basis = 0; cur_cases = 0; cur_where = rel(FILENAME) ":" FNR
  next
}
!in_acc && cur_ob != "" && /^- Basis:/ { cur_basis = 1 }
!in_acc && cur_ob != "" && /^- Cases:/ {
  cur_cases = 1
  kinds = $0; sub(/^- Cases:[ ]*/, "", kinds)
  nk = split(kinds, ks, /,[ ]*/)
  for (i = 1; i <= nk; i++) {
    k = ks[i]; gsub(/[ \t]+$/, "", k)
    if (k !~ /^(positive|negative|malformed|edge|concurrency|teardown)$/) problem("unknown case kind \"" k "\" on " cur_ob)
    else need[cur_ob SUBSEP k] = rel(FILENAME) ":" FNR
  }
}
!in_acc && cur_ob != "" && /^- Depends on:/ {
  deps = $0
  while (match(deps, /OB-[a-z0-9-]+-[0-9][0-9][0-9]/)) {
    dep_ref[++ndeps] = substr(deps, RSTART, RLENGTH); dep_where[ndeps] = rel(FILENAME) ":" FNR; dep_of[ndeps] = cur_ob
    deps = substr(deps, RSTART + RLENGTH)
  }
}
in_acc && /^### AC-/ {
  if ($0 !~ /^### AC-[a-z0-9-]+-[0-9][0-9][0-9]-[a-z]+ · OB-[a-z0-9-]+-[0-9][0-9][0-9] · (positive|negative|malformed|edge|concurrency|teardown)$/) {
    problem("malformed case heading: " $0); next
  }
  cases++
  have[$4 SUBSEP $NF] = 1
  ac_ob[cases] = $4; ac_where[cases] = rel(FILENAME) ":" FNR
  cur_ac = $2; cur_source = 0; cur_ac_where = rel(FILENAME) ":" FNR
  next
}
in_acc && cur_ac != "" && /^- Source:/ {
  cur_source = 1
  if ($0 ~ /^- Source: test/) {
    tp = $0
    if (match(tp, /`[^`:]+/)) {
      tp = substr(tp, RSTART + 1, RLENGTH - 1)
      if (!is_test(tp)) problem("case " cur_ac " says Source: test but cites a non-test file " tp)
    } else problem("case " cur_ac " says Source: test but cites no file")
  } else if ($0 !~ /^- Source: code/) problem("case " cur_ac " has a Source that is neither test nor code")
}
{ check_citations($0) }
END {
  close_ob(); close_ac()
  for (key in need) {
    if (!(key in have)) {
      split(key, kp, SUBSEP)
      problems++; print need[key] ": " kp[1] " lists " kp[2] " but no acceptance case covers it"
    }
  }
  for (i = 1; i <= cases; i++) if (!(ac_ob[i] in ob_where)) { problems++; print ac_where[i] ": case for unknown obligation " ac_ob[i] }
  for (i = 1; i <= ndeps; i++) if (!(dep_ref[i] in ob_where)) { problems++; print dep_where[i] ": " dep_of[i] " depends on unknown obligation " dep_ref[i] }
  printf "check-spec: %d obligations, %d cases, %d citations, %d problems.\n", obligations, cases, citations, problems
  exit problems > 0 ? 1 : 0
}
' "$@"
