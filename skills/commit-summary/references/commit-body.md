# Deriving a commit body

The procedure for answering the seven questions **against the code**, not against the
diff. `SKILL.md` has already weighed the change and decided to derive; it also owns the
repo-convention override, the skip rule, and the attribution ban.

## Evidence rules

These are hard. They are the difference between a derivation and a plausible
fiction.

- **A hash appears in a body only if a command returned it in this session.** No
  result means the paragraph is dropped — not softened into "has likely been
  broken for a while". "The fault is older than this branch" requires the blame or
  `git log -S` output that says so.
- **An enumerated call path is traced in the source or reproduced**, never reasoned
  about. If you did not open the file that contains the call, do not name the call.
- **Every claim is checkable**: a line, a call form, a hash, a changelog entry, a
  command. If it cannot be pointed at, cut it.

## Question 1 — What changed, and what does the running code do that forces it?

Open the code that *executes*, not the abstraction that describes it, and quote the
specific thing you found. This is the paragraph that makes the change look
inevitable instead of optional.

Lead with the semantics of the edit, not the file list:

> Treated a missing old value as a possible change instead of reading through it.
> When no key is reported, `listenKeys()` compares each watched key against the old
> value, and `notify()` may hand it nothing, so that comparison threw a
> `TypeError` before the caller's listener ever ran.

Use `X rather than Y` to carry the rejected alternative — it gets the minus side of
the diff into the prose for free, in one sentence:

> Selected the keyed `onSet()` and `onNotify()` payloads by the runtime's `setKey`
> capability rather than by structural assignability to `MapStore`.

**A change with several independent decisions gets one paragraph per decision**, not
one paragraph summarising all of them. Each opens on its own past-tense verb and is
followed by its own reason:

> Replaced `Get` with a distributive conditional that indexes each union member
> where the key exists, so per-member keys resolve to that member's value type.
>
> Relaxed `ValueWithUndefinedForIndexSignatures` to `Key extends KeyofBase`.
> `setKey` supplies `AllKeys<Value>`, which for a union is wider than `keyof Value`,
> so the previous constraint was violated on every per-member key and TypeScript
> resolved the reference to an error type. That error type was `any`, and it
> swallowed the correct type from the other arm of `setKey`'s value union, leaving
> those writes unchecked entirely.
>
> Dropped that now-redundant arm; a correct `Get` covers everything except the
> `undefined` an index signature needs for deletion, which the alias still supplies.

Two of those three are not the fix. One is a second, worse defect the fix uncovered
— silently unchecked writes, found while chasing a `never` — and one is a deletion
the fix made possible. **Both belong in the body.** What the change revealed and
what it let you remove are reasons a reader cannot reconstruct from the diff, and
the deletion in particular reads as unrelated scope creep unless the paragraph
before it explains why it is now dead.

Which code counts as authoritative depends on what the change touches:

| The change touches | Read this to find the "why" |
| --- | --- |
| A type, interface, or `.d.ts` | The implementation it describes — `.js`, the resolver, the wrapper that builds the payload |
| Docs, README, TSDoc, comments | The code the prose claims to describe. Prose is never evidence for prose |
| A config value or a removed default | The tool's resolved config (`tsc --showConfig`, `--print-config`, `--dry-run`) and its release notes for the version in `package.json` |
| A schema or migration | The queries that read the column, and what is already stored in it |
| A UI component | The rendered result — computed styles, DOM, a screenshot — not the class names |
| An API handler or contract | The client that calls it |
| CI or a build script | A real run's log |
| A dependency bump | The upstream changelog entry for the range crossed |

**Design rationale extracted from source comments is an input to this question.**
When a cleanup pass reports text under a heading like "Suggested for commit
message", that text is the answer to *why the code is built this way* — fold it
into this paragraph. It is not a block to append at the end of the body.

## Question 2 — Which concrete inputs or call paths reach it?

Enumerate them by name, and say which ones are *not* affected. Ruling paths out is
what proves the enumeration happened rather than being asserted:

> A bare `notify()` on a map or a deep map reached that line, and so did the same
> call through `subscribeKeys()`. A keyed `notify(undefined, key)` was already
> safe, because it takes the branch that matches the key instead.

## Question 3 — How did it fail observably?

Not "the type was wrong" — what a user saw. The strongest version names both the
call that broke and the call that kept working, because that asymmetry is the
actual bug:

> Ordinary code stopped compiling — `listenKeys($store, ['a'])` was rejected, and
> `changed === 'a'` was reported as a comparison with no overlap — while
> `setKey('a', 1)` kept working and kept delivering `a` at runtime.

A defect that *hides* problems instead of reporting them is described as hiding
them:

> Inside `if (changed !== undefined)` the key narrowed to `never`, which accepts
> any assertion, so a handler branching on `b.nested.deep` type-checked while the
> type system treated the branch as unreachable.

## Question 4 — What breaks for someone who updates?

State it, then state why it is still correct. The pairing is what stops it reading
as an apology:

> This may expose new TypeScript errors in deep-map handlers that asserted a
> narrower key inside a `changed !== undefined` guard, but those assertions only
> passed because the guarded type was `never`.

Severity sets position. When the break is the headline, it goes first and gets
named:

> This is a type-level breaking correction: `map<Value>()` now exposes
> `Partial<Value>` through `get()`, `value`, and listeners. Existing code that
> assumed every property was present may stop compiling, but those properties were
> already missing at runtime; pass an initial object or handle the partial value
> instead.

## Question 5 — When did it break, and why was it written that way?

Date the defect:

```bash
git log -S '<the removed expression>' -- <path>
git log -L '<start>,<end>:<path>'
git blame -L '<line>,+1' -- <path>
```

This is what licenses "the fault is older than this branch", which changes how a
reviewer reads the whole commit — and it often finds that the bug was collateral
damage:

> `105be31` deleted the export from the runtime in 2023, so a named import of it
> has been failing during module linking ever since, while the declaration kept
> insisting it was there.

> Restored the contract introduced with the shared mount payload; `e56dac3` made it
> optional amid otherwise mechanical `{}` and `extends any` lint fixes without
> changing the runtime.

Adjacent sources count as provenance too — a changelog that promised something the
code never shipped is the same kind of fact:

> The 0.10.0 changelog lists `StoreValues` and `Task` as added to exports. `Task`
> was added to the root declaration, but `StoreValues` was only exported from the
> unreachable computed module.

This is the question that invites invention. Re-read **Evidence rules** before
writing it.

## Question 6 — What do the tests pin?

One or two lines naming the cases, never "added tests":

> Added tests for a bare notification, a keyed notification without an old value,
> and an empty key list.

If the *shape* of the test is non-obvious, defend it — a test that would have
passed before the fix is worth calling out as avoided:

> Asserted the union keys directly — `let key: typeof changed = 'a'` — rather than
> comparing `changed` against a branch key. On the old type, the comparison itself
> is an error, while inside the impossible branch `changed` narrows to `never`,
> which accepts any assertion. The direct assignment fails on the
> shared-keys-only type and passes on this one.

If existing tests changed, defuse it before it is asked — this is a reviewer's
first suspicion:

> Adjusted four reads in existing tests to optional chaining. Every store in those
> tests always holds a value, so no runtime assertion changed.

## Question 7 — What did you notice and deliberately not fix?

The one a diff summary can never produce. Name the thing, name the trade-off, say
where it belongs:

> Left the extension's own key mistyped. `setKey('ext', 1)` still compiles and
> still delivers `ext` at runtime, so that key is now missing from the type instead
> of replacing the real ones. Both directions are wrong, but this one leaves every
> ordinary call correct and fails visibly on the key the author declared themselves.

> Left `listenKeys()` itself unguarded. Its own listener still reads
> `oldValue[key]` when no key changed, so a bare `notify()` throws there before the
> caller's listener runs. Repairing that changes runtime behaviour rather than a
> declaration, and belongs in its own change.

Written this way a deferral is a commitment rather than a hedge, and a partial fix
becomes auditable. It is also usually where a second commit is hiding.

## Writing rules

- **Open on the change, not the files.** First words are a past-tense verb on the
  semantics: `Treated`, `Selected`, `Resolved`, `Changed`, `Dropped`. Never
  "Updated `map/index.d.ts`".
- **Tense split.** Present for how the code behaves (`eq` compares against the
  value the store currently holds). Past for the edit (`Changed`, `Added`, `Left`)
  and for the old bug (`was rejected`, `used to throw`).
- **No hedging.** No "should be safer", "improves types", "hopefully", "better
  handling". If the benefit cannot be stated as a behaviour, there is no benefit to
  state.
- **Plain words, short sentences.** Same register as the `explain` skill: trace the
  mechanism on real symbols rather than characterising it, and let one plain sentence
  do one job. No aphorisms, no "crucially", no "it is worth noting", no sentence whose
  point is that the writer noticed something. `The runtime stores it and calls it
  without checking on the next cold mount.` — that is the whole standard.
- **No footers.** The body ends on its last paragraph, per **No attribution** in `SKILL.md`.
- **Identifiers in backticks**, with the member form where the language has one:
  `ReadableAtom#eq`, `MapStore#setKey()`.
- **Paragraphs, blank-line separated, wrapped at 80.** One idea per paragraph, in
  the question order above. No bullet lists.
- **Length tracks reasoning.** Three lines for a config deletion, twenty for a
  variance subtlety.
- **Findings survive the write-up.** An inconvenient result earns its own paragraph
  rather than being dropped — including a discovery that one of the change's own
  fixes does not do what it was meant to.

## Example B — same one-line diff, both contracts

The diff is `+ oldValue === undefined ||` inside `keys.some()` in
`listen-keys/index.js`, plus three tests.

A diff summary produces:

```
Added an `undefined` guard for `oldValue` in `listenKeys()`.
Added tests for missing old values.
```

The derivation produces — same edit, every extra paragraph an answer to one of the
seven questions:

```
Handle a missing old value in listenKeys

Treated a missing old value as a possible change instead of reading through
it. When no key is reported, `listenKeys()` compares each watched key against
the old value, and `notify()` may hand it nothing, so that comparison threw a
`TypeError` before the caller's listener ever ran.

A bare `notify()` on a map or a deep map reached that line, and so did the
same call through `subscribeKeys()`. A keyed `notify(undefined, key)` was
already safe, because it takes the branch that matches the key instead.

Put the check ahead of both comparisons, so neither the plain lookup nor the
deep-path lookup added for whole-store sets runs without an old value. Kept it
inside `keys.some()` as well: watching no keys still means no notifications,
where hoisting it out of the loop would have fired those listeners for a bare
`notify()` while a whole-store `set()` correctly left them alone.

Inside `batch()` the changed key is dropped, so a store that also omits its
old value says nothing about what happened and every watched-key listener now
runs. That call used to throw.

Added tests for a bare notification, a keyed notification without an old
value, and an empty key list.
```

The first version is not wrong. It is unreviewable: it does not say which call
broke, that the failure was a thrown `TypeError` rather than a wrong value, why the
guard sits inside `keys.some()` instead of above it (hoisting it changes which
listeners fire), or that `batch()` behaviour changed.

## Example C — plain prose carrying four judgment calls

`mapCreator`'s return types. No failure mode paragraph and no provenance; the whole
body is question 1 four times over, then question 7. Note the sentence length and
the absence of any word doing decoration:

```
Fix mapCreator return types

Added `id` to the store type returned by the creator and by `build()`.
`Creator.build()` creates `map({ id })`, so `id` exists eagerly on every path,
as the cache type already said. Because `MapStore` is invariant in its value
type, this may expose TypeScript errors in annotations that expected
`MapStore<Value>`.

Constrained `StoreExt` to `object` and changed its default from an
arbitrary-property record to `object`. Without a declared extension, a typo
inside `init` previously resolved to `any` and could propagate unchecked.

Kept extensions on the `init` parameter but left them out of returned stores.
`init` runs only when a store mounts, and an entry rebuilt after cache eviction
starts without those properties again, so the type cannot distinguish an
initialized store from a fresh one. Installing extensions eagerly would
defeat the creator's lazy initialization, while `Partial<StoreExt>` would
encourage optional calls that silently do nothing before initialization.

Avoided asserting fields populated by `init`: the initializer is optional and
does not guarantee a complete `Value`. That pre-existing return contract is a
separate compatibility issue and is not changed here.

Added a fixture covering eager `id` through the creator, `build()`, and
`cache`, rejected extension access on returned stores, and the narrowed
default extension type.
```

Every paragraph opens on a past-tense verb — `Added`, `Constrained`, `Kept`,
`Avoided` — and the sentence after it is the reason, stated as behaviour. The
rejected alternatives (`Partial<StoreExt>`, installing eagerly) get one clause each,
not a discussion.

## Example D — the questions are not declaration-specific

A one-word `staleTime` change in a data hook:

```
Stop refetching the account panel on every focus

Changed `useAccount()` to a 30s `staleTime`. The query had none, so
React Query treats every cached entry as immediately stale and refetches
on window focus and on remount, and the panel remounts on each route
change inside the settings tabs.

Reached from any settings tab switch and from returning to the tab, which
is how it showed up as a spinner on data the user had just seen. The
dashboard copy of the panel was unaffected — it mounts once.

Left the profile and billing queries untouched. They share the same hook
factory but their write paths invalidate on mutation, so a stale window
there would show a value the user just changed. Giving the factory a
default belongs with that invalidation audit, not here.

Added a test that a focus event inside the window issues no request, and
one that a refetch resumes after it.
```
