# Audit Procedure

Mechanical scan → per-test gate pass → verdicts → report. Audit mode never edits files.

## 1. Scope and inventory

Resolve scope: explicit argument → exactly that. Otherwise test files among uncommitted
changes (`git diff --name-only HEAD`); otherwise ask, or sample the suite — a mix of small
and large files, pure-logic and mock-heavy, plus any e2e specs.

Inventory the landscape first (frameworks, count, location):

```bash
# TS/JS
fd -e test.ts -e test.tsx -e spec.ts -e spec.js | head -50   # or: find . -name "*.test.*"
cat vitest.config.* vite.config.* jest.config.* 2>/dev/null
# Java
fd -g "*Test.java" | wc -l
```

## 2. Mechanical scan

Grep-able smells, mapped to the catalog (`anti-patterns.md`). Findings here are *leads* — a
hit still needs the per-test pass to confirm; e.g. `toHaveBeenCalledWith` at a real boundary
is legitimate.

```bash
# Weak asserts (catalog 1.3)
grep -rn "toBeDefined()\|toBeTruthy()\|not\.toThrow()" --include="*.test.*"
grep -rn "assertNotNull\|assertTrue(true" --include="*Test.java"

# Tautology leads (1.1): expected value near a mock return in the same file
grep -rln "mockReturnValue\|mockResolvedValue" --include="*.test.*"   # then inspect

# Change detectors (2.1)
grep -rn "toHaveBeenCalledTimes\|toHaveBeenCalled()" --include="*.test.*"
grep -rn "verify(.*times(\|verify(.*never()" --include="*Test.java"

# Over-mocking (2.2): mock count per file
grep -rc "vi\.mock(" --include="*.test.*" . | sort -t: -k2 -rn | head

# Flaky time (2.3)
grep -rn "Thread.sleep\|await sleep\|setTimeout.*resolve" --include="*test*" --include="*Test.java"
grep -rn "new Date()\|Date\.now()\|System\.currentTimeMillis" --include="*.test.*" --include="*Test.java"

# Logic in tests (3.2)
grep -rn "^\s*for (\|^\s*if (" --include="*.test.*"      # inside it()/test() bodies

# Rot (3.5) and focus leaks
grep -rn "\.skip\|\.only\|xit(\|xdescribe(" --include="*.test.*"
grep -rn "@Disabled\|@Ignore" --include="*Test.java"

# Snapshots (1.4)
fd -e snap | xargs wc -l 2>/dev/null | sort -rn | head
```

## 3. Per-test gate pass

For each test in scope, answer the Five-Question Gate (SKILL.md) and tag catalog hits.

Two resolution rules before the shortcuts:

- **Shortcuts never override the gate.** Before any Delete, run question 1 — if the test's
  intent names a real, otherwise-untested promise, the verdict upgrades to Rewrite.
- **When several shortcuts match one test**, resolve by contract: no unique contract pinned →
  Delete beats Tighten; real contract anchored to a mock or implementation → Rewrite beats
  Tighten. Tighten is only for tests already pointed at the right contract.

Shortcuts that usually settle a verdict fast:

- Expected value traceable to a mock return in the same test → 1.1, **Rewrite or Delete**.
- Only assertion is existence/no-throw → 1.3, **Tighten**.
- Interaction assert on an owned collaborator → 2.1, **Rewrite**.
- Name is a method name or ticket → 3.1, **Tighten** (rename) — then re-check question 1:
  if no rule-sentence exists for it, escalate to **Rewrite/Delete**.
- Sleeps / real clock → 2.3, **Tighten**.
- Disabled without a linked issue (use git blame for age when it matters) → 3.5, **Delete**
  — unless its intent names a real, otherwise-uncovered promise, then **Rewrite**.
- Asserts an acknowledged-wrong value → 1.7, **Surface separately** (it's a bug report).

## 4. Verdicts and severity

| Verdict | Meaning | Cost |
| --- | --- | --- |
| **Keep** | Passes the gate | — |
| **Tighten** | Right contract, weak execution | Minutes per test |
| **Rewrite** | Real contract, wrong anchor (mock/implementation) | Needs understanding the SUT |
| **Delete** | No contract, duplicate, trivia, rot | Free — and a quality improvement |

Severity, for ordering the report:

- **High** — false confidence on money/security/data-loss paths; pinned known-wrong values;
  tautologies on critical modules.
- **Medium** — change detectors blocking refactors; flaky tests; over-mocked orchestrators.
- **Low** — naming, copy-paste arrange, weak asserts on low-risk paths.

When criticality can't be judged from the test alone (unknown callers, unclear domain), place
the finding at Medium and note what would raise it — don't guess High.

## 5. Report template

```
## Test Audit: <scope> (N files, M tests)

Frameworks: vitest 3 (unit), wdio 9 (e2e)
Verdicts: Keep 61 · Tighten 18 · Rewrite 7 · Delete 5

### High
- `nodes.test.ts:54` — tautology: asserts mock's `total` round-trips (1.1) → Rewrite
  against query-param mapping and response shaping
- `SyncWorkTest.java:173` — pins acknowledged-wrong count ("should be 4, left as is") (1.7)
  → file issue, mark test, surface to team

### Medium
- `init.test.tsx` — 13 module mocks; verifies choreography of mocks (2.2) → keep ONE
  orchestration test, drop per-feature clones
- `watcher.spec.ts:88` — `await sleep(150)` (2.3) → fake timers

### Low
- 16× duplicated "returns 403 for non-admin" across apis/ (3.4) → one parameterized test
  over the route table
- `SlashApiHandlerTest.java` — `@BeforeEach` with 15 when() chains (3.3) → builders

### Delete (no contract pinned)
- `api.test.ts:41` — `expect(result).toBeDefined()` only; duplicate of :38 (1.3)
- `LegacyMapperTest.java` — @Disabled since 2024, no issue link (3.5)

### Suite-level observations
- No error-path coverage in apis/exports
- e2e specs share state via "Precondition" test (2.5)
```

Delete verdicts appear only in the Delete section (with a one-line justification each), not
duplicated under severity headings.

## 6. Improve pass (after an approved audit)

Work the report top-down by severity:

1. **Tighten** first — small, safe, mechanical (precise asserts, renames, `it.each`
   conversion, fake timers, builder extraction).
2. **Rewrite** next — re-anchor to the contract; this requires reading the SUT, not just the
   test. Keep the old test's *intent list* and check every intent is re-covered or
   consciously dropped.
3. **Delete** last, in one reviewable group, each with its one-line justification.
4. **Never weaken an assertion to get to green.** If a tightened assert exposes a real
   failure, that's a found bug — report it, don't blur the test back.

Verification, in order:

```bash
<test command>                  # full suite green
```

Then **mutation spot-check** every Rewrite: break the SUT rule the test claims to pin (flip
a boundary, change a constant, invert a condition), run, confirm red, revert. A rewritten
test that can't go red just relocated the theater. For broader checks on critical modules,
suggest mutation tooling (Stryker for TS/JS, PIT for Java) — but the manual spot-check is
mandatory either way.

Report what changed grouped by verdict, with before/after test counts and any bugs the
tightened asserts exposed.
