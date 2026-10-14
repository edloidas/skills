# Report format

Every gate and the final report use one skeleton. The gate report shows what will happen; the final
report shows what did, with links. SKILL.md carries a filled-in gate report.

## Skeleton

```markdown
## Issue triage · <n> open issues in <owner/repo>

Run: <Phase 0–4 counts, one line each phase's end line already printed, joined with " · ">

### Close (<n>)
| Issue | Reason | Why | Comment |
| ----- | ------ | --- | ------- |
| [#<n>](<url>) <title> | completed · not planned · duplicate of #x | <one clause, with the proof> | `texts/<n>.close.md` |

### Keep, with fixes (<n>)
| Issue | Type | Labels | Title | Body | Status |
| ----- | ---- | ------ | ----- | ---- | ------ |

### Backlog (<n>) · Ask the owner (<n>) · Discuss (<n>)
- [#<n>](<url>) <title> — <one clause>; <owner and question, where there is one>

### New issues (<n>)
- <title> — <type>, <labels>, under #<parent> — <one clause on what recorded decision it tracks>

### Found along the way
- <a live bug, a stale closure, a decision without a follow-up — anything the user should know>

### Needs your call
- **Q1. <question>** Assumed: <default>. → if not: <what changes>

### Plan
**<one sentence: what will be written>** · manifest `<id>` · `<n>` writes · texts in `<run dir>/texts/`
```

Rules:

- A row cites its proof in the row; the reader never has to open the issue to see why.
- An issue appears in one section only.
- A section with no rows is left out, not printed empty.
- Links are full URLs. Counts in headings match the rows.
- *Found along the way* holds facts that change what someone should do next, at most six.

## Final report

The same skeleton, with each row's outcome — `CLOSED (not planned)`, `UPDATED`, `ASKED @owner`,
`FILED #n`, `SKIPPED`, `FAILED: <exit and message>` — and a last line pasted from `audit`. Filled in:

````markdown
## Issue triage · 63 open issues in acme/api · done

Run: 63 fetched · 212 refs, 9 unresolved · 19 clusters · breadth 41 routed · depth 9 overturned of 41 · 24 claims: 16 hold, 3 narrower, 4 fall, 1 unproven · you changed 5 rows

### Closed (27)
| Issue | Reason | Why |
| ----- | ------ | --- |
| [#1423](https://github.com/acme/api/issues/1423) Migrate to Vue 3 or React | `CLOSED (completed)` | Admin rebuilt on Preact in caeba2e4 (#2374) |
| [#1386](https://github.com/acme/api/issues/1386) Move Cloudflare integration to the API | `CLOSED (not planned)` | Cloudflare was removed from the operator, not moved (acme/operator#492) |
| [#1444](https://github.com/acme/api/issues/1444) Unify errors | `CLOSED (duplicate of #2388)` | #2388 owns the error model; the i18n requirement was carried over first |

### Updated (18)
| Issue | Changed |
| ----- | ------- |
| [#958](https://github.com/acme/api/issues/958) fix: reject messages on an expired WebSocket token | type Bug · +Bug −Tech Debt · title · note on top · Backlog |
| [#2364](https://github.com/acme/api/issues/2364) fix: react to k8s resource deletion | +Bug −Improvement · dated update |

### Asked the owner (2)
- [#1583](https://github.com/acme/api/issues/1583) CNAMEs for cloud clusters — `ASKED @rymsha`: still relevant, and which record name?

### Filed (2)
- [#2618](https://github.com/acme/api/issues/2618) refactor: replace the informers with a poller — `FILED`, under #2486

### Found along the way
- #2555 was closed as completed with no work done; its scope moved into #2483, now stated there.

Audit: live state matches manifest 16aec43
````

## Short form

With `short`: the run line, one line per section with its count and issue numbers, *Needs your
call* in full, and the plan line. No tables.
