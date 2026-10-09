# Plan Output Format

Phase 2 prints exactly this structure, inline. Never write it to a file.

````markdown
## Plan for #<N>: <title>

**Goal**
<1–2 sentences stating what "done" looks like for this issue.>

**Changes**
1. `<relative/path/to/file>` — <concrete change: what is added, modified, or
   removed, and why>
2. `<relative/path/to/file>` — <concrete change>
3. ...

**Slices** (slice mode only)
1. `<conventional subject>` — Changes 1–2
2. `<conventional subject>` — Changes 3–5

**Related work** (only when the analysis has a Related Work section)
- Part of #<P> — next open: #<S>, #<S>
- Skip: <scope item> — #<M> owns it
- Prepare: <field, export, or shape> — Change <k>, for #<K>
- Correct: following #<P> | the comment by @<user> over the issue text on <point>

**Out of scope**
- <thing the issue might imply but you are not touching, with one-line reason>
  (or: `None — scope is contained to the files above.`)

**Risks / decisions**
- <any judgment call with tradeoff; name the alternative you considered>
  (or: `None — implementation is mechanical.`)
````

Rules for the body:

- Every Changes entry references a concrete file path. No "investigate X" or "figure out
  Y" items — investigation belongs to the pre-plan reading.
- 3–10 Changes for a normal issue, or per slice in slice mode.
- Out of scope is mandatory. If nothing is out of scope, say so explicitly — it forces
  you to have thought about it.
- Risks names the alternative you rejected. `None` is valid when the choice was forced.
- Related work carries every Skip, Prepare, and Correct the analysis derived, each with
  its source issue, so the user sees every way the plan departs from the issue text. A
  Skip also appears under Out of scope.
- A Prepare is a Changes entry in a file the plan already touches. One that needs a new
  file, or more than the interface the other issue consumes, is dropped and named under
  Out of scope instead: building the next issue's work here is scope creep on an issue
  judged simple.

## When to pause for approval

Phase 2 proceeds without asking by default. Pause and ask, per the skill's **Asking the
User** convention, only if **any** of these fire:

- Multiple valid implementation approaches exist where picking one is a real judgment call
  (new API shape, data model, public-facing contract change)
- The issue text is ambiguous about what "done" means
- Implementation would clearly touch files outside what the issue title implies
- The Changes list grew beyond ~10 items during planning — in slice mode, beyond ~10 in one
  slice, or the plan has more than 4 slices
- The analyzer surfaced a dependency that is unresolved
- A Skip drops something the issue explicitly asks for, or a Correct changes what "done"
  means — the plan no longer delivers the issue as written
- The analyzer surfaced an epic, a multi-file architecture decision, or a contract change —
  this skill is for issues the user already judged simple enough to delegate end-to-end.
  An issue that merely has a parent epic is not this condition

Then ask one focused question and wait for the reply:

- **Option 1** — header `<=12 chars>`, label `<proposed plan name>` `(Recommended)` — `<one-line reason>`
- **Option 2** — header `<=12 chars>`, label `<alternative>` — `<one-line reason>`
- **Option 3** — header `Stop`, label `Exit without implementing` — `Leave the branch unstarted.`
