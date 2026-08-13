# Writing Tests

How to write a test that passes the Five-Question Gate by construction. Reached from a
Tighten or Rewrite verdict: the audit says the existing test doesn't pin a contract, this is
the procedure for writing the one that does.

## 1. List the contract first

Before any test code, write the module's promises as one-sentence rules, gathered from its
public surface, types, docs, and call sites:

```
totalCents:
- sums price × qty across items
- applies a percentage coupon to the subtotal
- rounds a fractional discount to the nearest cent
- rejects an expired coupon instead of silently ignoring it
- a coupon expiring at this exact instant is already invalid
processCheckout:
- charges the gateway exactly the discounted total
- retries a transient gateway failure exactly once, after RETRY_DELAY_MS
- treats a declined card as final — never retried
- never moves money on invalid input
```

Each sentence becomes a test name, verbatim. Two payoffs: the suite reads as documentation
(a new dev learns the domain by reading names top to bottom), and a failure names the broken
rule. If you can't write the sentences, you don't understand the module yet — read more code
before touching the test.

A test name is a business rule, never a method name (`testHandleApi`), a ticket
(`fixes JIRA-4521`), or a counter (`test applyCoupon #2`).

## 2. Pick cases by equivalence class, not code path

Path enumeration is a non-goal. The tools:

- **Equivalence partitioning** — one test per behavior class (valid coupon, expired coupon,
  no coupon), not per branch.
- **Boundaries between classes** — `<` vs `<=` at the expiry instant, the rounding cent,
  empty input, the error path. Boundaries are where ambiguity survives code review and dies
  in production.
- **Table tests** for the same rule with several data points — `it.each` /
  `@ParameterizedTest`, never a `for` loop (a loop hides which case failed).
- **Property-based tests** for invariants on parsers, math, encoders — e.g. fast-check /
  jqwik: "result is always an integer, ≥ 0, ≤ subtotal". Properties catch the bug classes
  example tables only sample — *if the oracle is tight*. Before keeping one, name the dumbest
  implementation that satisfies it: `abs(x) >= 0` is satisfied by `() => 0`, `floor(x) <= x`
  by a large negative constant. Tighten to a two-sided bound
  (`floor(x) <= x && x < floor(x) + 1`) or a metamorphic relation — round-trip
  (`parse(print(x)) === x`), agreement with a slow reference implementation, invariance under
  reordering. A property nothing dumb survives is worth ten examples; a one-sided one is
  worth less than the example table next to it.
- **Exhaustiveness gates in the type system** for closed sets — error codes, discriminated
  unions, state enums. A `Record<ErrorCode, Case>` case table (or a Java `EnumMap` /
  exhaustive `switch`) turns "someone added a code without a test" into a compile error.
  This is the one kind of completeness worth engineering deliberately, and unlike a coverage
  threshold it cannot be satisfied by a test that asserts nothing.
- **Golden vectors** where an exact output is a documented *external* promise — a seeded
  RNG's sequence, a wire format, a hash, a payload other systems parse. They resemble
  snapshots and are their opposite (anti-patterns 1.4): the values are chosen and reviewed,
  and changing one is a breaking change. Pick vectors that hit the awkward paths (rejection
  sampling, wide ranges, non-ASCII input, safe-integer boundaries), and say in the name that
  the values are a compatibility contract so nobody "just regenerates" them.

Five sharp tests beat forty exhaustive ones.

## 3. Shape: Arrange–Act–Assert, one Act

- **Arrange** via builders with *valid defaults*; each test states only the deviation that
  matters. Builders live next to the suite (or a local test-util), not in a base class three
  files away.
- **Act** exactly once. Two Acts = two tests.
- **Assert** the outcome with precise matchers. Expected values are **hand-computed
  constants** — `expect(total).toBe(7500)` with a comment if the arithmetic isn't obvious
  (`// 10000 − 25%`). Never re-derive the expectation with the SUT's formula, and never let
  Arrange establish the very state Assert checks — then the SUT contributes nothing.
- **Separate volatile detail from structure.** When a result carries both a stable shape and
  churn-prone detail (source spans, ids, timestamps, formatting), assert them in different
  tests. Otherwise a one-character shift produces a screen-sized structural diff and
  reviewers start rubber-stamping. Isolate the volatile part — don't drop it.
- **No logic** in test bodies: no `if`, no loops, no `try/catch` (use
  `expect(...).toThrow` / `assertThatThrownBy`). Tests should be embarrassingly linear. When
  the assertion needs the error's *payload* (code, position, fields), use a helper that fails
  if nothing threw and returns the typed error — a bare `try/catch` with the asserts inside
  `catch` reports green the day the SUT stops throwing.
- **DAMP over DRY**: a reader of a *failure* must understand the test without hopping files.
  Extract helpers for plumbing (firing events, building requests), keep the meaningful values
  visible in the test.

## 4. Test doubles

Policy (the SKILL.md version, applied):

- Mock **only unmanaged boundaries**: network, clock, fs, randomness, other processes.
- Real collaborators for owned code. If wiring real collaborators is painful, that's design
  feedback (see §6), not a license to mock.
- Prefer **fakes** (in-memory implementations verified by state) over interaction mocks.
- Interaction asserts only when the outgoing call **is** the contract; call counts only when
  the count is a documented rule.

## 5. Determinism by construction

- **Time**: clock as an argument (`totalCents(items, coupon, now)`) or injected `Clock` —
  then pure-logic tests never touch timers at all. Where the SUT schedules work, fake timers
  (`vi.useFakeTimers()` + `advanceTimersByTimeAsync`) — never `await sleep(150)`.
- **Randomness**: seed it or inject it.
- **State**: no module-level mutable fixtures; restore anything global in `afterEach`; every
  test runnable alone and in any order.
- **Network/fs**: only behind the injected boundary.

## 6. Hard to test = design feedback

When a test wants three mocks and a global, the code is telling you something:

| Pressure | Response |
| --- | --- |
| Hidden `new Date()` / `Date.now()` in the SUT | Make the clock a parameter |
| IO buried mid-function | Extract the pure core; test it mock-free; leave a thin shell |
| Needs 10 mocks to instantiate | The unit is a god object — split it, or test one level higher |
| Test must reach private internals | The behavior is either observable through the public API or not a behavior |

Superb tests come from yielding to this pressure, not from mocking framework gymnastics.

## 7. Two cases the audit sends here often

- **A test named after a bug or a ticket** (3.1). The rule is legitimate and worth pinning —
  rename it to the rule the bug violated. `it('rounds a fractional discount to the nearest
  cent')`, not `it('fixes JIRA-4521')`. Then re-check gate question 1: if no rule-sentence
  exists, the verdict was Delete, not Tighten.
- **A characterization test** that pins current legacy behavior, bugs included. It is a rescue
  scaffold, valid only while a refactor is in flight — kept permanently it ossifies accidents
  into contracts, and if it pins a known-wrong value that is 1.7, a bug report rather than a
  test. Never write a new one to satisfy a Rewrite verdict.

## 8. Worked example (Vitest/TS)

The pattern in miniature — builders, table test, boundary, one boundary mock with a
contract-level interaction assert, fake timers:

```ts
const NOW = new Date('2026-06-10T12:00:00Z');
const item = (priceCents: number, qty = 1): CartItem => ({ priceCents, qty });
const coupon = (percentOff: number, o: Partial<Coupon> = {}): Coupon =>
  ({ code: 'SAVE', percentOff, expiresAt: new Date('2027-01-01T00:00:00Z'), ...o });

describe('totalCents — pricing rules', () => {
  it.each([
    { name: 'an empty cart costs nothing', items: [], expected: 0 },
    { name: 'sums price × qty across items', items: [item(1000, 2), item(550)], expected: 2550 },
  ])('$name', ({ items, expected }) => {
    expect(totalCents(items, null, NOW)).toBe(expected);
  });

  it('rounds a fractional discount to the nearest cent', () => {
    expect(totalCents([item(999)], coupon(10), NOW)).toBe(899); // 999 − 10% = 899.1
  });

  it('a coupon expiring at this exact instant is already invalid', () => {
    expect(() => totalCents([item(1000)], coupon(50, { expiresAt: NOW }), NOW))
      .toThrow(ExpiredCouponError);
  });
});

describe('processCheckout — talking to the payment gateway', () => {
  it('charges the gateway exactly the discounted total', async () => {
    const gateway = { charge: vi.fn(async () => ({ receiptId: 'r-1' })) };

    const result = await processCheckout(gateway, [item(10_000)], coupon(25), NOW);

    expect(result).toEqual({ ok: true, receiptId: 'r-1' });
    expect(gateway.charge).toHaveBeenCalledWith(7500); // the amount we SEND is the contract
  });

  it('recovers from a single transient gateway failure by retrying', async () => {
    vi.useFakeTimers();
    const gateway = { charge: vi.fn()
      .mockRejectedValueOnce(new TransientGatewayError('blip'))
      .mockResolvedValueOnce({ receiptId: 'r-2' }) };

    const pending = processCheckout(gateway, [item(1000)], null, NOW);
    await vi.advanceTimersByTimeAsync(RETRY_DELAY_MS);

    await expect(pending).resolves.toEqual({ ok: true, receiptId: 'r-2' });
    vi.useRealTimers();
  });
});
```

Note what's absent: no mocks in the pure half (the clock is an argument), no
`toHaveBeenCalledTimes` except where a retry count would be documented behavior, no setup
block — builders carry the defaults.

## 9. Per-stack idioms

### Vitest / TypeScript

- `it.each` for tables; `vi.hoisted()` + a single mock bucket when module mocks are
  unavoidable; `vi.useFakeTimers()` paired with `vi.useRealTimers()` in `afterEach`.
- `toEqual` for whole-shape contracts; `toMatchObject` only when extra properties are
  explicitly not part of the contract.
- Component tests: query by role/test-id and assert visible behavior; asserting CSS class
  names couples to styling internals — prefer computed effects when the visual rule is the
  contract.
- Don't mock your own UI library to test a component built from it — that tests prop
  plumbing. Render the real thing; mock the data boundary.
- Errors: `expect(...).toThrow(Type)` / `await expect(p).rejects.toThrow(Type)`. For payload
  assertions write a typed helper (`expectAppError(fn)`) that throws when nothing threw; if a
  raw `try` is unavoidable, put `expect.unreachable()` immediately after the call.
- Run `--shuffle --repeat=5` after any rewrite — order dependence is cheap to find now and
  expensive to inherit.

### JUnit 5 / Mockito / AssertJ (Java)

- `@ParameterizedTest` + `@MethodSource`/`@CsvSource` for tables.
- AssertJ over bare JUnit asserts:
  `assertThatThrownBy(...).isInstanceOf(...).extracting(...).isEqualTo(...)` pins type and
  payload in one chain; `assertNotNull` alone is theater.
- Build value objects with their real builders — never mock value objects.
- A `@BeforeEach` with 15 `when()` chains is the setup-labyrinth smell: move per-test
  stubbing into the tests, share only neutral infrastructure. Prefer composition (fixture
  objects, `@RegisterExtension`) over deep `Abstract*Test` inheritance.
- Injected `java.time.Clock` over `System.currentTimeMillis()`; no `Thread.sleep` — use
  Awaitility-style condition polling when a real async boundary exists.

### WebdriverIO / e2e

- Every terminal `waitFor*` is followed by an explicit assertion of the outcome.
- Tests independent: shared state built in `before` hooks or via API fixtures, never in
  "test #1".
- Page objects encapsulate selectors and waits; specs read as user intent.
- e2e tests cover user journeys — don't replicate unit-level rule coverage through the
  browser; test each contract at the level where it lives (pricing math → unit; "form
  submits and renders the error" → component/integration; "user can publish" → e2e).
