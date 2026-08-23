# Worked Examples

Three explanations that landed, condensed and renamed for compactness. Each one is followed by the
move that carried it. Read them for shape, not for content — the subjects are incidental.

<examples>

<example>
**Asked:** "Why does adding my own `setKey` to a map store break `listenKeys`?"

Your `Ext` is not adding a key — its `setKey` is the only signature `KeyOf` ever reads, so it
replaces the key set.

```
KeyOf<Base & Ext>  ->  "ext"        <- your store
KeyOf<Ext & Base>  ->  "a" | "b"
```

Same two members, opposite order, different answer. `infer` against a type with more than one call
signature resolves the last one only, and `map()` returns `Base<Value> & Ext`, so your extension
always lands last. The first row is the one that moved.

That one resolution feeds both the `keys` argument and the `changed` payload field, so a single bad
inference breaks two APIs:

```
listenKeys($s, ['a'], () => {})
  error TS2345: Type '"a"' is not assignable to type '"ext"'.
```

Nothing is wrong with the store itself. `$s.setKey('a', 42)` still delivers `changed = "a"` at
runtime; the shadowing is type-level only.

**The move.** Two rows side by side isolate the change, and one clause names which row moved. Real
compiler output pasted rather than described. No headers — the answer has one part.
</example>

<example>
**Asked:** "Why did two tenants see each other's profile, and what did the fix change?"

The cache key was the URL, and the URL is identical for every tenant.

```
GET /profile  (tenant A)  ->  miss, stores A's body under "/profile"
GET /profile  (tenant B)  ->  hit,  returns A's body
```

`req.tenant` is set by middleware that runs after the cache lookup, so at the moment the key is
built there is no tenant to put in it:

```js
// before — server.js
app.use(cache)          // key is req.url
app.use(resolveTenant)  // sets req.tenant

// after
app.use(resolveTenant)
app.use(cache)          // key is `${req.tenant}:${req.url}`
```

Read it as: resolve who is asking before deciding what to remember for them.

Still true after the fix — entries written before the deploy have no tenant in their key, so they
are unreachable rather than wrong. They expire on their own TTL and nothing reads them first.

**The move.** The failing sequence first, as the two captured requests. The fix is two lines of
before and after and nothing else from the diff. One plain sentence restates it. The close names
what the fix does not cover.
</example>

<example>
**Asked:** "Correct me if I'm wrong. 1. `Get` was broken but we did not notice, because the other
candidate covered for it — so `Get` can be removed. 2. `Get` still needed the fix. 3. The other
candidate has its own problem, because `Value[Key]` needs the key present on every branch of the
union."

All three hold. Two corrections, one of them substantive.

**1 — substantive error.** "Covered for it" is right for plain objects and backwards for unions. On
a union the other candidate resolved to `any` and swallowed `Get`'s correct answer, so the masking
went both ways. And `Get` came out of that one parameter, not out of the file: `eqKey` still uses it
directly at lines 80–81.

**2 — right.** Worth adding the reason. `eqKey` uses `Get` with no second candidate to hide behind,
which is why it had to be fixed rather than deleted.

**3 — right conclusion, wrong cause.** `Value[Key]` is the second problem in that helper. The `any`
came from the first one, the `Key extends keyof Value` constraint: `setKey` passes
`AllKeys<Value>`, the constraint demands `keyof Value`, and the violation resolved the whole
reference to an error type before the body was ever considered.

**The move.** A verdict per point, in the user's own numbering. Each correction labelled by kind.
What is right is confirmed in two words rather than re-explained.
</example>

</examples>
