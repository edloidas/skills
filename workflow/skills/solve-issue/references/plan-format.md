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
- 3–10 Changes for a normal issue. Over 10 trips the Phase 2 approval gate.
- Out of scope is mandatory. If nothing is out of scope, say so explicitly — it forces
  you to have thought about it.
- Risks names the alternative you rejected. `None` is valid when the choice was forced.
