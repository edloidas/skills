---
name: sharpen
description: >
  Rewrite a prompt or task statement so it asks for what a top practitioner would do, before any work starts.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep
argument-hint: "[the prompt or task to sharpen, or empty for the last request]"
metadata:
  author: edloidas
  tier: routed
---

# Sharpen

Make a task deeper, not bigger, and hand back the rewritten prompt. This skill writes text only: it
changes no file and does not start the task.

## Input

The prompt to sharpen is `$ARGUMENTS`; when that is empty, the user's last request in the
conversation. With neither, ask for the prompt in one line and stop. Read a file only when the
prompt names it and the answers below would otherwise have to guess at what it holds — a log's
format, a function's callers. Reading is to name the material, not to begin the work.

## The Four Answers

Answer each in one line, specific to this task. A line that would fit any task in the field is not
an answer yet — name the file, the metric, the tool, the dataset. Where an answer would add nothing
to this task, write `Nothing to add.`; when all four do, say the prompt is already sharp, return it
unchanged, and stop.

1. **Practitioner** — what a top practitioner in this field would add that the prompt does not ask for.
2. **Raw material** — what they would start from instead of a summary: the logs, the data, the code, the real artifact, and where it is.
3. **Methods** — the specific methods and tools they would use.
4. **External check** — what would show the result is right, other than the agent's or the user's say-so: a test, a measurement, a reproduction, a third party's data.

## The Rewrite

Rewrite the prompt so it asks for exactly what the four answers imply. The deliverable stays the
one the user asked for; every sentence added traces to one of the four answers, and nothing new is
delivered. Keep the user's names, constraints, and scope as written. Put it in a fenced block so it
can be copied as is.

## Left to You

List the choices the rewrite depends on that only the user can make: a target number, a trade-off,
what may be changed, what is out of scope. One line each, phrased as a question with the real
options named, at most four. Never pick one, and never write the rewrite as if one were picked —
leave a visible placeholder like `<target p95>` instead. With none, write `None.`

## Output

The three parts — **Before rewriting**, **Sharpened prompt**, **Left to you** — in this order, and
nothing after them:

````markdown
**Before rewriting**

1. **Practitioner:** would fix a latency budget and find where the time goes before touching code, not guess at a cache.
2. **Raw material:** a browser performance trace and the server timing logs for one real slow query, `q=wireless headphones` from the support ticket, not "the page feels slow".
3. **Methods:** a performance profile of the page load, `EXPLAIN ANALYZE` on the search query, comparing server time against render time.
4. **External check:** the same recorded query timed 20 times before and after, p95 compared against the budget.

**Sharpened prompt**

```text
The search page is slow. Before changing anything, reproduce it with the query
`wireless headphones` and record a browser performance trace and the server timing
logs for it. Split the time into server, network, and render, and run EXPLAIN ANALYZE
on the search query. Fix the largest share first. Done means the same query, timed 20
times, has a p95 under <target p95>, with the before and after numbers shown.
```

**Left to you**

- What p95 target counts as fast enough — 300 ms, 500 ms, or something else?
- May the fix change the database schema, such as adding an index, or only application code?
- Can results be cached and served slightly stale, or must every search hit live data?
````

Then stop. Do not run the task, and do not offer to run it.
