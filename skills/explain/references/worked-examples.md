# Worked Examples

Four explanations that landed, condensed and renamed for compactness. Each one is followed by the
move that carried it. Read them for shape, not for content — the subjects are incidental. The last
one is a second pass over a subject already explained once.

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

---

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

---

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

---

**Asked:** "explain again" — second pass over an origin check on a WebSocket upgrade, already
explained once as a mechanism with a trap in it.

The setup, fixed for the whole walk: your app is served at `https://api.example.com`, your browser
UI at `https://console.example.com`, and the app's config has one line —
`cors.origin = https://console.example.com`.

```text
  browser           controller          handshake thread
     │                   │                      │
  1  │─── upgrade ──────▶│                      │
     │                   │ 2 controller runs    │
     │                   │ 3 validator built    │
     │                   │ 4 function kept      │
  5  │                   │─── test(origin) ────▶│
     │                   │                      │ 6 which check runs
     │                   │                      │ 7 your function answers
  8  │◀──────────── socket opens ───────────────│
```

**Step 1 — The browser opens the socket.** Your UI runs `new WebSocket('wss://api.example.com/ws')`.
The browser attaches a header you cannot remove or change: `Origin: https://console.example.com`.

**Step 2 — Your controller runs, normally.** Nothing about sockets has happened yet. You are just
building the object you return.

**Step 3 — Your controller returns, and the library is called.** `getWebSocketOriginValidator(req)`
runs now, while `req` still exists. It reads `cors.origin`, splits it into a list, works out your
app's own address from `req.scheme`, `req.host`, `req.port` — and then returns a function without
deciding anything. It packages those two values for later.

**Step 4 — The platform takes that function off your response** and keeps it. Your controller is
finished; `req` is gone.

**Step 5 — The handshake calls the function.** On a different thread, the server hands it one
string: the header from step 1, and nothing else. This is why step 3 had to work out your app's own
address up front — the request that could have told it no longer exists.

**Step 6 — The platform picks which check to use, and this is the surprising step.**

```java
if ( validator != null ) { return validator.test( originHeaderValue ); }   // returns here, always
return SameOriginCheck.check( originHeaderValue, expectedScheme, expectedHost, expectedPort );
```

Read the order. Once your function exists, its answer is returned and the platform's own check is
never reached. Yours does not run *in addition* — it replaces.

**Step 7 — Your function answers, in order.** No header at all → allow. Equal to your app's own
address → allow. Matches an entry in the configured list → allow. Anything else → refuse. Our
value is not empty, is not `api.example.com`, and matches the one configured entry, so: allow.

**Step 8 — The socket opens.** Without any of this, step 6 would have reached the platform's check,
which compares `console.example.com` against `api.example.com`, refuses, and answers `403` with an
HTML page your controller never sees.

**The move.** Second pass over an explanation that was already correct. One scenario fixed at the
top and carried through all eight steps. Steps numbered in execution order, each titled with what
happens in it. `predicate` became "the function", `captured by closure` became "worked out while
the request still exists", `falls through` became "reaches". The trap is called out in the step it
happens in, not warned about above. Longer than the first pass, not shorter. Three lanes and three
arrows for eight steps: the map puts steps 2–4 on the controller and 6–7 on the handshake thread,
and says nothing about what step 6 decides.
