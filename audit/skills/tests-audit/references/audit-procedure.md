# Audit Procedure

Mechanical scan → dynamic checks → per-test gate pass → verdicts → report. The audit itself
never edits files; §6 is for whoever applies the report afterwards.

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

# Catch-only error tests (1.10): compare try blocks against no-throw guards
grep -rc "try {" --include="*.test.*" . | grep -v ":0$" | sort -t: -k2 -rn | head
grep -rn "expect\.unreachable\|fail(\"\|Assertions\.fail" --include="*.test.*" | wc -l

# Self-fulfilling setup (1.9): the test writes the state it then asserts,
# or asserts the SUT's own source/scripts instead of its output
grep -rn "chmod\|mkdirSync\|writeFileSync\|cpSync" --include="*.test.*"
grep -rn "package\.json\|readFileSync(.*scripts\|toContain('chmod" --include="*.test.*"

# Over-claiming names (1.8): does the assert measure what the name promises?
fd -e test.ts -e test.tsx -e spec.ts | grep -Ei "complex|perf|benchmark|memory|scalab|secur"
rg -n "performance|complexity|O\(n" .github/workflows/ 2>/dev/null   # claims one level up

# Property oracles (1.11): read each property, name the dumbest passing implementation
grep -rn "fc\.assert\|fc\.property\|@Property\|forAll(" --include="*.test.*"
```

## 2b. Dynamic checks

Isolation, flakiness, and runtime don't grep — they have to be observed. Three runs, usually
under a minute, and they produce the only claims in the report backed by evidence rather
than reading.

```bash
<test command>                              # baseline: green? how long for how many tests?
<test command> --shuffle --repeat=5         # vitest; jest: --randomize, JUnit: random order
<test command> --coverage                   # then open the report — read lines, not the %
```

| Observation | What it licenses you to say |
| --- | --- |
| Shuffle + repeat green | Concrete evidence against 2.4/2.5 — state it; most audits can only guess at isolation |
| Shuffle red | An order dependence exists. **High** finding, and the failing pair names it |
| Slow for its size | Real IO, sleeps, or a missing seam — go find which (2.3). A fast suite is evidence the boundary discipline held |
| Coverage report | Judge the *uncovered lines*. Defensive branches and exhaustiveness guards uncovered = correct, say so. A whole error path or module uncovered = a real gap and a finding |

Never report the coverage percentage as a finding in either direction, and don't recommend
raising a threshold to round a number up — see the Core Principle corollary in SKILL.md.

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
- Name or CI job promises a property no assertion measures → 1.8, **Rewrite + rename** (the
  claim is the defect; the underlying assert is often worth keeping under an honest name).
- Arrange writes the state the Assert reads, or the assert greps the SUT's own source →
  1.9, **Rewrite** around the real artifact.
- Every assertion inside a `catch` → 1.10, **Tighten**. Report the whole set as one finding
  with a file list, not one finding per occurrence.
- Property satisfied by a constant / identity / first-argument implementation → 1.11,
  **Tighten** to a two-sided or metamorphic oracle; **Delete** if exact tests already pin it.
- Feature-named tests that all exercise one mechanism → 3.6, **Delete opportunistically** —
  list under suite-level observations, not under a severity heading.
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
  tautologies on critical modules; a guarantee the project *relies on* (a CI gate, a
  documented promise) that no assertion actually measures (1.8/1.9); a proven order
  dependence.
- **Medium** — change detectors blocking refactors; flaky tests; over-mocked orchestrators;
  error suites that can pass without throwing (1.10).
- **Low** — naming, copy-paste arrange, weak asserts on low-risk paths, weak property
  oracles where exact tests already cover the rule.
- **Not a finding** — redundant deterministic coverage (3.6). Suite-level observation only.

A test that is technically fine but *claims* more than it delivers outranks a test that is
merely weak: the weak test leaves the question open, the over-claiming one closes it wrongly.

When criticality can't be judged from the test alone (unknown callers, unclear domain), place
the finding at Medium and note what would raise it — don't guess High.

## 5. Report template

```
## Test Audit: <scope> (N files, M tests)

Frameworks: vitest 3 (unit), wdio 9 (e2e)
Verdicts: Keep 61 · Tighten 18 · Rewrite 7 · Delete 5
Observed: 1,285 tests in 1.8s; shuffled ×5 green (6,425 runs, 4.2s); 99.9% lines covered

One-paragraph calibration: where this suite sits, and what the substantive problems are.
"Well above typical library quality but not yet SOTA — core coverage is unusually thoughtful;
the weaknesses are three tests that claim protection they do not provide, plus avoidable
duplication."

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
- `integration.test.ts` re-proves seeded reproducibility for six features through one RNG
  forwarding path (3.6) — consolidate when next in the area, not as its own task

### Strengths (protect these)
- Randomness injected at the one unmanaged boundary; no mocking of owned modules
- `Record<ErrorCode, Case>` makes a missing error-code test a compile error
- Seeded-RNG golden vectors pin a documented compatibility promise, incl. rejection sampling
- Part-tree structure asserted separately from source spans — span churn can't bury a
  structural diff
- Coverage threshold is correctly capped: the uncovered lines are defensive branches;
  raising it would manufacture theater

### Path to fixing
1. Remove the false guarantees (1.8, 1.9) — highest value, smallest diff
2. Make every error assertion impossible to pass silently (1.10)
3. Strengthen or drop the weak properties (1.11)
4. Consider mutation testing on the riskiest modules
5. Prune duplication only when already touching the area
```

Delete verdicts appear only in the Delete section (with a one-line justification each), not
duplicated under severity headings.

**Strengths are not padding.** They calibrate severity (twelve Low findings on an excellent
suite ≠ twelve on a rotten one), and an unnamed good pattern is one refactor from deletion.
Name the mechanism, not the vibe — "randomness injected at the boundary", not "good tests".

## 6. Fix pass (after an approved audit)

The audit never edits the suite. This section is for whoever applies the report afterwards.

Work the report top-down by severity:

1. **Tighten** first — small, safe, mechanical (precise asserts, renames, `it.each`
   conversion, fake timers, builder extraction).
2. **Rewrite** next — re-anchor to the contract; this requires reading the SUT, not just the
   test. `writing-tests.md` is the procedure: list the contract sentences first, then write the
   test that pins one. Keep the old test's *intent list* and check every intent is re-covered
   or consciously dropped.
3. **Delete** last, in one reviewable group, each with its one-line justification.
4. **Never weaken an assertion to get to green.** If a tightened assert exposes a real
   failure, that's a found bug — report it, don't blur the test back.

Verification, in order:

```bash
<test command>                              # full suite green
<test command> --shuffle --repeat=5         # rewrites and deletions didn't add coupling
```

Then **mutation spot-check** every Rewrite: break the SUT rule the test claims to pin (flip
a boundary, change a constant, invert a condition), run, confirm red, revert. A rewritten
test that can't go red just relocated the theater. For broader checks on critical modules,
suggest mutation tooling (Stryker for TS/JS, PIT for Java) — but the manual spot-check is
mandatory either way.

Report what changed grouped by verdict, with before/after test counts and any bugs the
tightened asserts exposed.

Traps specific to the fix pass:

- **Weakening an assert to stop a flake.** The flake is the bug — fix the determinism, keep the
  precision.
- **"Fixing" a tautology by asserting more of the mock.** More tautology is still tautology;
  re-anchor to what the module *does* to the data, or delete.
- **Renaming without re-anchoring.** A behavior-sentence name on an implementation-coupled body
  is worse than before — the label lies.
- **Mock-padding a slow test instead of extracting logic.** Slowness is design feedback; pull
  the pure part out and test it mock-free.
