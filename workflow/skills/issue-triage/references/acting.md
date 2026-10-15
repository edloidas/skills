# Acting on the plan

The only home of the write mechanics. Decisions become a manifest through `prepare.sh manifest`;
the manifest becomes writes through `apply.sh`, run by this session and nothing else.

## Decisions

`decisions.json` is one array, merged from the workers' JSON and corrected by Phase 2 and the gate.
One object per issue; an absent field means no change, and an issue without an object is a `KEEP`
that takes only its lint type.

```json
[
  { "number": 958, "verdict": "KEEP", "type": "Bug", "labels": { "add": ["Bug"], "remove": ["Tech Debt"] },
    "title": "Reject messages on an expired WebSocket token", "note": true, "why": "expiry is checked on start only" },
  { "number": 1444, "verdict": "CLOSE-DUPLICATE", "duplicate_of": 2388, "type": "Task",
    "claims": ["#2388 covers every requirement of #1444, the i18n line included"] },
  { "number": 1583, "verdict": "STALE-ASK" },
  { "number": 1601, "verdict": "BACKLOG", "status": "Icebox", "skip": true }
]
```

`verdict` is one of `verdicts.md`. `claims` lists the load-bearing claims, each checkable against
the code or an issue, and is required on every close and on `"security": true` — a security, access
or data-loss subject. A duplicate or not-planned close of one needs `"confirmed": true`, set only
from the user's answer at the gate. `note: true` puts `texts/<n>.note.md` on top of the body. `status`
overrides the `--status` mapping for that row; `skip`, `milestone` and `"project": false` pass
through to the manifest. `why` is for the report only.

`prepare.sh manifest` names the texts it expects, and `apply.sh` refuses when one is missing:

| Verdict | Text |
| ------- | ---- |
| `CLOSE-*` | `texts/<n>.close.md` — the closing comment |
| `STALE-ASK`, `NEEDS-DISCUSSION` | `texts/<n>.ask.md` — the owner question |
| any, with `note` | `texts/<n>.note.md` — 1–3 lines above the original body |

New issues a decision implies go in `new_issues.json`, copied into the manifest as they are:
`[{ "key": "poller", "title": "...", "type": "Task", "labels": ["Tech Debt"], "body_file": "texts/new-poller.md", "parent": 2486 }]`.
A row's `duplicate_of` or a new issue's `parent` may name one as `"new:<key>"`.

## Texts

Written by this session before the gate, never by a worker.

- A closing comment says why, in the terms of the close-reason table in `verdicts.md`, with the
  commit, pull request or file that proves it, in 1–3 sentences.
- It never points at an issue that is itself closing in this run.
- Carried-over lines go to their target issue first, as that issue's own `note` or ask text.
- An owner question mentions the owner and asks one answerable question.
- No generated-by footer, no attribution line.

## Order and the board

`apply.sh` runs writes in a fixed order: new issues; then per issue title, type, labels, milestone,
board, parent, body note, comment, state change, and Status last. Closing before setting Status is
what keeps the reason right on a board that closes issues itself. `--closed-status` names the Status
a board workflow turns into a close; `apply.sh` refuses it on a row meant to stay open, and exits 6
if a workflow closes one anyway.

A wrong close reason is repaired without reopening (`completed` ↔ `not_planned`); to or from
`duplicate` needs a reopen and a close, which the plan lists separately.

`apply.sh` adds the run's `--marker` as one hidden line to every comment and note, which is how a
rerun recognises its own writes. The id `plan` prints covers the manifest and every text it names:
a changed row or text means a new plan and a new gate, and `apply --expect` refuses the old id.
`preflight` reports identity, scopes, whether `GH_TOKEN` overrides the stored login, and the board's
workflows; it never switches identity or changes a token.

| Exit | Means | Do |
| ---- | ----- | -- |
| 1 | `gh` or `jq` failed | Stop; report the command and message; rerun once fixed |
| 2 | Invalid manifest, or changed since approval | Fix the decisions, rebuild, re-plan, re-gate |
| 3 | Preflight failed | Report the lines; the user fixes scope, labels or names |
| 4 | Permission denied mid-run | Stop; report the op. Earlier writes are done; a rerun resumes |
| 5 | Rate limited | Stop; a later rerun resumes |
| 6 | A workflow closed an issue meant to stay open, or `audit` found differences | Report live vs manifest; nothing is fixed forward without a gate |

**A refusal is final for this run.** When GitHub or the host's permission check refuses a command,
do not retry it under another identity, wrap it in another script, split it into raw `gh` calls,
hand it to a worker, or edit permission settings. Report it and give the user the exact command.
