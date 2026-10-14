# Acting on the plan

The only home of this skill's write mechanics. Every write goes through `scripts/apply.sh`, run by
this session; no worker writes, and nothing is written outside a manifest the user approved.

## The manifest

`<run dir>/manifest.json` states the end state of each issue, not the steps to get there, so a rerun
does only what is still missing. `null` or an absent field means leave it as it is.

```json
{
  "version": 1,
  "repo": "acme/api",
  "marker": "2026-10-14",
  "project": { "owner": "acme", "number": 7, "status_field": "Status", "closed_status": "Done" },
  "issues": [
    { "number": 958, "type": "Bug", "labels": { "add": ["Bug"], "remove": ["Tech Debt"] },
      "title": "fix: reject messages on an expired WebSocket token", "status": "Backlog",
      "body": { "mode": "prepend", "file": "texts/958.note.md" } },
    { "number": 1444, "type": "Task", "status": "Done", "state": "closed", "reason": "duplicate",
      "duplicate_of": 2388, "comment_file": "texts/1444.close.md" },
    { "number": 1583, "type": "Task", "status": "Backlog", "comment_file": "texts/1583.ask.md" }
  ],
  "new_issues": [
    { "key": "poller", "title": "refactor: replace the informers with a poller", "type": "Task",
      "labels": ["Tech Debt"], "body_file": "texts/new-poller.md", "parent": 2486, "status": "Backlog" }
  ],
  "milestones_close": ["User invites"]
}
```

- `state`: `open` or `closed`. A closed row has `reason` `completed`, `not_planned` or `duplicate`;
  `duplicate` needs `duplicate_of`.
- `project`: when present, every row is put on that board unless the row says `"project": false`.
  `closed_status` names the Status a board workflow turns into a close; set it from the Phase 0
  workflow list, and `apply.sh` refuses to set it on an issue meant to stay open.
- `body.mode`: `prepend` puts a 1–3 line note above the untouched original, so a reader meets the
  correction first; `append` adds a dated section at the end for anything longer. There is no
  rewrite mode.
- `parent` and `duplicate_of` may name a new issue as `"new:<key>"`.
- A row with `"skip": true` is left alone. That is how a gate answer of "run some rows" is recorded.
- `marker` is the run's id. `apply.sh` adds it as one hidden line to every comment and note it posts,
  which is how a rerun recognises them.

## Texts

Every comment, note and new-issue body is a file under `<run dir>/texts/`, written by this session
before the gate — never by a worker. Rules:

- A closing comment says why, in the terms of `verdicts.md`'s close-reason table, with the commit,
  pull request or file that proves it, in 1–3 sentences.
- A closing comment never points at an issue that is itself closing in this run.
- Carried-over lines go to their target issue first, as that issue's own comment row.
- An owner question mentions the owner and asks one answerable question.
- No generated-by footer, no attribution line.

## Order

`apply.sh` runs writes in a fixed order, which callers do not change: new issues first; then per
issue title, type, labels, milestone, board, parent, body note, comment, state change, and Status
last. Closing before setting Status is what keeps the close reason right on a board that closes
issues itself: the reason is set by the close, and the board's own "item closed" rule then has
nothing to change.

A close reason that is already wrong is repaired without reopening (`completed` ↔ `not_planned`).
Changing to or from `duplicate` needs a reopen and a close, which shows in the issue's timeline, so
the plan lists those rows separately.

## Running it

```bash
bash <skill-dir>/scripts/apply.sh preflight <run dir>/manifest.json
bash <skill-dir>/scripts/apply.sh plan <run dir>/manifest.json            # last line: manifest <id> ops <n>
bash <skill-dir>/scripts/apply.sh apply <run dir>/manifest.json --expect <id from the approved plan>
bash <skill-dir>/scripts/apply.sh audit <run dir>/manifest.json           # exit 0: live matches
```

- `preflight` prints the identity, the token scopes, whether `GH_TOKEN` in the environment is
  overriding the stored login, and the board's enabled workflows; it refuses on a missing scope,
  label, type, Status option or milestone. It never switches identity or changes a token: those are
  the user's commands to run.
- `apply` refuses a manifest whose id differs from the approved plan's. The id covers the manifest
  and every text it names, so a changed row or a changed text means a new plan and a new gate.
- Done is claimed only after `audit` exits 0; the final report pastes its last line.

| Exit | Means | Do |
| ---- | ----- | -- |
| 1 | `gh` or `jq` failed for another reason | Stop. Report the command and its message; rerun once the cause is fixed |
| 2 | Invalid manifest, or it changed since approval | Fix the manifest, re-plan, re-gate |
| 3 | Preflight failed | Report the lines; the user fixes scope, labels or names |
| 4 | Permission denied mid-run | Stop. Report the op and the message. Writes before it are done; a rerun after the user fixes access resumes |
| 5 | Rate limited | Stop; rerun later resumes |
| 6 | A board workflow closed an issue meant to stay open, or `audit` found differences | Report live vs manifest; nothing is fixed forward without a gate |

**A refusal is final for this run.** When GitHub or the host's permission check refuses a command,
do not retry it under another identity, wrap it in another script, split it into raw `gh` calls,
hand it to a worker, or edit permission settings. Report it and give the user the exact command to
run themselves.
