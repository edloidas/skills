# Anti-Pattern Catalog

Each entry: what it looks like, why it's bad (the mechanism, not just the vibe), how to detect
it, and the smallest fix. Grouped by which direction of the core criterion it violates.

A test is good iff it **fails exactly when a promised behavior breaks**. Group 1 stays green
when behavior breaks (false confidence). Group 2 fails when behavior didn't break (false
alarms). Group 3 doesn't break the criterion directly but destroys diagnosis and maintenance.

---

## Group 1 — False confidence (green while broken)

### 1.1 Mock round-trip tautology

```ts
mockedQuery.mockReturnValue({ total: 2, hits: [a, b] });
const res = get(request);
expect(res.body.total).toBe(2); // asserts the mock's value came back out
```

**Mechanism:** the asserted value never passed through any logic — the test verifies the
mocking framework. Production code could drop, double, or mislabel the value and a
sufficiently thin pipe would still pass.

**Detect:** the expected value appears verbatim in a `mockReturnValue` / `thenReturn` in the
same test. If deleting the SUT's logic (returning input unchanged) would keep it green, it's
a round-trip.

**Fix:** find the *translation* the module performs — field mapping, filtering, status
mapping, authorization — and assert that. If the module performs no translation, delete the
test; the contract lives at integration level.

### 1.2 Implementation mirror

```ts
const expected = Math.round(price * (1 - discount / 100)); // copied from the SUT
expect(total(price, discount)).toBe(expected);
```

**Mechanism:** the test re-derives the expectation with the same formula as the
implementation, so the test and the bug always agree. A wrong formula passes; only a *typo
divergence* between two copies fails.

**Detect:** arithmetic or transformation logic in the Assert/Arrange that mirrors the SUT.
Any computed `expected` deserves suspicion.

**Fix:** hand-compute the constant (`expect(total(999, 10)).toBe(899)`), choosing inputs
where the rule's edge shows (rounding, boundary).

### 1.3 Weak asserts / coverage theater

```ts
expect(result).toBeDefined();
assertNotNull(response);
expect(() => run()).not.toThrow();   // as the only assertion
```

**Mechanism:** executes every line, falsifies nothing — `{ ok: false }` is also "defined".
These exist to satisfy a coverage number, which is Goodhart's law in action: once coverage is
the target it stops measuring protection.

**Detect:** `toBeDefined|toBeTruthy|not\.toThrow` (TS), `assertNotNull|assertTrue\(true`
(Java) as a test's only assertion.

**Fix:** assert the precise value, shape (`toEqual` on the full object), or typed error.
`toMatchObject` is acceptable for partial shapes but knowingly ignores extra properties —
prefer `toEqual` when the whole shape is the contract.

### 1.4 Snapshot rubber-stamp

**Mechanism:** a large snapshot has no oracle — nobody decided what correct looks like, so
"press `u` to update" becomes muscle memory and the test asserts "whatever the code currently
does is correct", i.e. nothing. (Small, deliberate inline snapshots of a value someone
actually reviewed are fine.)

**Detect:** `toMatchSnapshot` with multi-screen `.snap` files; snapshot updates routinely
bundled into unrelated PRs.

**Fix:** replace with explicit asserts on the few properties that are the contract. If no one
can say which properties matter, the test has no contract — delete.

**Not this:** *golden vectors* — exact expected outputs pinning a documented external promise
(a seeded RNG's sequence, a wire format, a hash, a payload other systems parse). They look
like snapshots and are their opposite: the values were chosen and reviewed, and changing one
is a breaking change rather than a keystroke. Credit them in an audit, don't flag them.

### 1.5 Wait-as-assert (e2e)

```js
await contentBrowsePanel.waitForPublishButtonVisible(); // end of test
```

**Mechanism:** the wait doubles as the assertion — if it times out the test fails, but
nothing checks the *outcome* (enabled state, label, count). Passing means "a thing eventually
appeared", which is far weaker than the scenario's intent.

**Detect:** spec ends in `waitFor*` with no assert after it; asserts on element presence
where the scenario is about element *state* or data.

**Fix:** follow every terminal wait with an explicit assertion of the expected outcome.

### 1.6 Trivia tests

**Mechanism:** getters, framework wiring, generated code, constructors. Cost > 0
(maintenance, runtime, noise), information yield = 0 — these can essentially never fail for
a reason anyone cares about.

**Fix:** delete. A test that has never failed and documents nothing is a liability.

### 1.7 Pinned known-wrong value

```java
// "Should be 4 IMO. Has been discussed internally and left as it is for now"
assertEquals(5, result.size());
```

**Mechanism:** the suite now *defends* a bug — anyone fixing the behavior breaks the test and
learns the wrong lesson. This is a bug-tracker entry wearing a test costume.

**Fix:** file/locate the issue, link it, and either fix the behavior or mark the test
explicitly (`it.fails`, `@Disabled("XP-1234: returns 5, should be 4")`) so green never
endorses the wrong value. Surface these in any audit report — they're high-signal.

### 1.8 Proxy metric sold as a guarantee

```ts
// complexity.test.ts — "guards against quadratic keep/drop"
expect(rng.callCount).toBe(20);
```

**Mechanism:** the assertion pins a proxy (draw count, call count, byte size, line count)
that merely correlates with the promised property (time/space complexity, performance,
security, thread-safety). A quadratic implementation makes exactly the same number of draws.
The test isn't wrong about its proxy — it's wrong about its *claim*, and the claim is what
the file name, the CI job description, and the next maintainer act on. Worse than no test:
it retires the question.

**Detect:** file or test names containing `complexity`, `perf`, `performance`, `benchmark`,
`memory`, `scalab*`, `security` whose assertions count something else. Read the CI docs
alongside — a workflow that advertises a "performance gate" no assertion measures is the
same defect one level up.

**Fix:** split the claim from the measurement. Keep the count assertion under its true name
(deterministic consumption and draw order — a real contract), and measure the promised
property with the right instrument: instrumented operation counters, a benchmark with a
regression threshold, or an explicit scaling assertion (10× input ⇒ < 20× operations). If
none is practical, drop the claim rather than let CI keep advertising it.

### 1.9 Self-fulfilling test

```ts
await chmod(cliPath, 0o755);                       // arrange
expect((await stat(cliPath)).mode & 0o111).toBeTruthy();   // asserts what arrange just did

expect(pkg.scripts.build).toContain('chmod +x');   // asserts the script's text, not its effect
```

**Mechanism:** two shapes of one failure — the code under test never influences the
assertion. In the first, Arrange establishes the exact postcondition Assert checks, so
deleting the build step entirely keeps it green. In the second the test greps the
implementation's *source*, pinning one spelling of a step while proving nothing about the
artifact it produces.

**Detect:** an Arrange line writing the same state the assert reads (`chmod`/`mkdir`/`write`
then `stat`/`exists`); assertions that read the SUT's own scripts, config, or source text;
a test that runs the TypeScript entrypoint directly while claiming to check the built
output.

**Fix:** exercise the real producer — run the actual build/packaging command into a temp dir
and inspect its untouched output. If that's too slow for the unit suite, move it to a
build-verification job rather than faking it locally; a slow truth beats a fast lie.

### 1.10 Error test that can pass without an error

```ts
try {
  lex('2d');
} catch (e) {
  expect(e.code).toBe('UNEXPECTED_EOF');   // the only assertions live here
}
```

**Mechanism:** when the SUT stops throwing — precisely the regression the test exists to
catch — the `catch` block is skipped and the test reports green. Silent by construction: it
can never fail, so it never reaches triage.

**Detect:** `try {` in a test body with no `expect.unreachable()` / `fail()` / post-call
assertion. Count the ratio across the tree — 65 `try` blocks against 11 guards is a
systematic gap, not a one-off, and should be reported as one finding with a list, not 54.

**Fix:** `expect(() => …).toThrow(X)` / `assertThatThrownBy` when the type is the contract.
When the assertion needs the error's payload (code, position, fields), use a helper that
fails if nothing threw and returns the typed error. Most repos already have one — find it
(and check whether the repo's own rules already mandate it) before writing another.

### 1.11 One-sided property oracle

```ts
fc.assert(fc.property(fc.double(), x => Number.isInteger(floor(x)) && floor(x) <= x));
```

**Mechanism:** property tests swap specific expectations for invariants, so a weak invariant
constrains almost nothing across an enormous input space while reading as the most rigorous
test in the file. The example above is satisfied by returning a large negative constant;
`abs(x) >= 0` is satisfied by `() => 0`.

**Detect:** a single-sided comparison, a type check, or a range check as the whole property.
The test: name the dumbest implementation that satisfies it — constant, identity, "return
the first argument". If one exists, the property is decorative.

**Fix:** make the oracle two-sided (`floor(x) <= x && x < floor(x) + 1`) or metamorphic — a
relation only the correct answer satisfies: round-trip (`parse(print(x)) === x`), agreement
with a slow reference implementation, invariance under reordering, consistency with an exact
example at chosen points. When exact example tests already pin the rule harder, delete the
property rather than pad it.

---

## Group 2 — False alarms (red while behavior unchanged)

### 2.1 Change detector

```ts
expect(internalHelper).toHaveBeenCalledTimes(3);
verify(repository, times(2)).save(any());  // count is not documented behavior
```

**Mechanism:** asserts *how* the result was produced — call order, call counts, private
state. Detects change, not breakage: any behavior-preserving refactor turns it red. Feels
rigorous while being a pure false-positive generator.

**Detect:** interaction asserts on collaborators the module owns; counts/order without a
documented rule behind them ("retries exactly once" is documented; "calls save twice" is
incidental).

**Fix:** assert the observable outcome (return value, state change, outgoing message at the
boundary). Keep an interaction assert only where the outgoing call *is* the contract.

### 2.2 Over-mocking owned code

```ts
vi.mock('@our/ui', () => /* 60 lines re-implementing the component library */);
// or: 13 vi.mock() calls so the "unit" is alone in the universe
```

**Mechanism:** every collaborator stubbed means the test verifies that your mocks talk to
each other — a parallel universe where all dependencies behave as imagined. Ten green tests,
and the door still doesn't fit the frame. Also maximally brittle: any signature change breaks
dozens of mock setups.

**Detect:** `vi.mock` count per file in the high single digits or above; mocks of modules
from the same package/repo; mock setup longer than the tests.

**Fix:** use real collaborators for owned code; mock only the unmanaged boundary (network,
clock, fs). For orchestrators/coordinators where mocking subsystems is the point, keep one
such test and accept its brittleness consciously — don't replicate the pattern per feature.

### 2.3 Flaky time

```ts
await sleep(150);           // hope the debounce fired
Thread.sleep(2000);         // hope the watcher noticed
expect(isExpired(coupon)).toBe(true);  // depends on the real clock / midnight / CI timezone
```

**Mechanism:** converts red from a signal into noise; noise is contagious — one flaky test
teaches the team to ignore the whole suite.

**Detect:** `sleep|setTimeout` awaited in tests, `Thread.sleep`, `new Date()` /
`System.currentTimeMillis()` / `Date.now()` reaching the SUT, tests that fail "sometimes".

**Fix:** fake timers (`vi.useFakeTimers` + `advanceTimersByTimeAsync`); clock as an argument
or injected `Clock`; condition-based waiting (poll for the condition with a deadline) where a
real async boundary genuinely exists.

### 2.4 Shared / global state leak

```ts
globalThis.app.config = { ... };   // mutated, never restored
```

**Mechanism:** tests pass alone, fail together (or vice versa) depending on order — failures
stop correlating with the code change that caused them.

**Detect:** module-level mutable fixtures; `beforeEach` without the matching restore;
static singletons mutated in tests; suites that fail under `--shuffle` / parallel runs.

**Fix:** save-and-restore in `afterEach` (or `vi.stubGlobal` / JUnit extensions); better,
pass config as an argument so there's nothing global to mutate.

### 2.5 Order-dependent tests

```js
it('Precondition: add two folders', ...);   // later tests assume the folders exist
```

**Mechanism:** one failure cascades into N misleading failures; tests can't be run, debugged,
or parallelized individually. Common in e2e suites where setup is expensive.

**Fix:** each test arranges its own world. In e2e, move shared setup into `before` hooks or
API-level fixture creation — explicit, named, and re-runnable — never into "test #1".

---

## Group 3 — Diagnosis and maintenance killers

### 3.1 Bug-shaped name

```ts
it('fixes JIRA-4521', () => { ... });
test('test applyCoupon #2', ...);
testHandleApi()   // method name, not rule
```

**Mechanism:** at 3 AM in CI the name is the first (often only) thing read. A ticket number
or method name says nothing about which promise broke. Regression tests are valuable — *after*
being renamed to the rule the bug violated.

**Fix:** name = one sentence of the contract, readable as documentation:
`rounds a fractional discount to the nearest cent`,
`resolveSyncWork excludes children of a moved-out parent`.

### 3.2 Logic in tests

```ts
mockConnect.mockImplementation(() => {
  if (callCount <= 1) return firstConnection;   // branching mock
  return secondConnection;
});
for (const req of cases) { expect(get(req).status).toBe(400); }  // which case failed?
```

**Mechanism:** tests have no tests — `if`/`for`/`try-catch` means the test itself can be
wrong in interesting ways, and a loop reports "one of these failed" without saying which.

**Fix:** loops over cases → `it.each` / `@ParameterizedTest` (each case gets a name and an
individual failure). Branching mocks → `mockReturnValueOnce` chains, or split into one test
per scenario. `try/catch` asserting in `catch` → `expect(...).toThrow` /
`assertThatThrownBy` — and note this one is not merely a diagnosis problem: it also passes
silently when nothing throws (1.10), so it belongs in Group 1 severity-wise.

### 3.3 Setup labyrinth (mystery guest)

```java
@BeforeEach  // 40 lines, 15 when() chains, 8 mocks
// or: class FooTest extends AbstractContentServiceTest extends AbstractElasticsearchIntegrationTest
```

**Mechanism:** the failing test no longer shows what mattered — the relevant arrangement
lives three files up. Deep base-class chains also accrete state (executors, contexts) that
leaks between tests.

**Fix:** builders/factory functions with *valid defaults*, where each test states only the
deviation that matters (`coupon(50, { expiresAt: PAST })`). Keep shared infrastructure
(embedded ES, app context) in fixtures, but keep *data arrangement* in the test. DAMP over
DRY: duplication in tests is cheaper than coupling between them.

### 3.4 Copy-paste arrange blocks

**Mechanism:** the same 5-line builder chain pasted into 10+ tests with one-field variations.
Every contract change costs 10 edits; reviewers stop reading Arrange blocks, so divergences
hide.

**Detect:** near-identical Arrange blocks across tests; 16 tests named identically
("returns 403 for non-admin") across files.

**Fix:** one builder with defaults + per-test override. For cross-cutting rules duplicated in
every file (authz checks), one parameterized test over the route table beats N clones.

### 3.5 Rotting disabled tests

**Mechanism:** `.skip` / `@Disabled` / commented-out blocks signal "this matters" while
testing nothing — and each one quietly lowers the bar for the next. After months they're
archaeology, not intent.

**Fix:** fix it now, or delete it — git remembers. A disabled test may stay only with a
linked issue and a reason in the annotation.

### 3.6 One mechanism re-proved through many surfaces

**Mechanism:** N tests titled after unrelated features that all bottom out in the same code
path — seeded reproducibility asserted again for Fate dice, explosions, rerolls, and grouped
rolls when a single RNG forwarding call does the work in every case. Unlike 3.4 the *text*
differs, so it survives review; what repeats is the contract. The direct cost is small
(runtime, one edit per contract change); the real cost is misreading — a four-digit test
count taken as broad protection when the marginal test protects nothing new.

**Detect:** for each test ask what it would be the *only* one to catch. No unique answer →
redundant. Look for one fixture, seed, or helper threading through tests named after
different features.

**Fix:** keep the test that pins the mechanism directly, plus the feature tests that add a
contract of their own; drop the rest **opportunistically** when next touching that area.
Deterministic redundant tests are cheap — a dedicated cleanup pass to lower a test count
costs more review than it returns, and this is never an audit's headline finding. Say so
explicitly in the report so nobody reads "redundant" as "urgent".
