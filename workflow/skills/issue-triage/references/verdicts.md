# Verdicts

The only home of the verdict set, the proof each one needs, and what routes an issue to the depth
pass. The breadth and depth prompts point here; neither restates it.

## The set

| Verdict | Means | Proof required — all of it | Without the proof it becomes |
| ------- | ----- | -------------------------- | ---------------------------- |
| `CLOSE-DONE` | The issue asked for something that now exists | A merged pull request or commit on the default branch that is not a dependency bump, the file and line at HEAD that shows the behaviour on a live path, and every requirement in the issue mapped to it | `KEEP`, with an update listing what is left |
| `CLOSE-OBSOLETE` | What the issue is about no longer exists | The subject is gone at HEAD, named with the commit that removed or replaced it, and the close bar below | `KEEP` or `STALE-ASK` |
| `CLOSE-DUPLICATE #x` | Another open issue covers the same problem | One sentence of the problem that both issues satisfy, `#x` covers every requirement of this one or the carry-over lines are named, and `#x` is not itself closing in this run | `KEEP`, cross-linked |
| `CLOSE-NOT-PLANNED` | Someone with the authority decided not to do it | A recorded decision by a maintainer — a comment, a decision issue, a roadmap — cited by link, or the user's answer at the gate | `STALE-ASK`; never the agent's own product call |
| `KEEP` | Still valid, still wanted | Its premise checked at HEAD: references resolved, the gap or bug still present | — |
| `BACKLOG` | Valid but not current work | As `KEEP` | — |
| `STALE-ASK` | No proof it is dead, no recorded decision, no activity in 12 months | The owner it goes to, first match: assignee, the author if still a maintainer, the last maintainer who commented, CODEOWNERS for the paths it names | — |
| `NEEDS-DISCUSSION` | A question only people can settle, with the question written out | The question and who answers it | — |

**The close bar.** An issue closes only when what it describes demonstrably no longer applies, and
nothing worth keeping is lost — or the lines worth keeping are named with where they move first: a
requirement into the duplicate target, a note into the issue that now owns the area.

**Age is not evidence.** An old idea that is still valid is `BACKLOG`. An infrastructure or
operations item without a code footprint in this repository is `STALE-ASK` to its owner, never a
close. Where the call is unclear, the default is `KEEP` or `BACKLOG`: a wrong close costs a reopen
and a lost idea, a wrong keep costs one row in the next run.

**"Exists in code"** always means reachable: a definition and a caller on a live path. A function
that is defined and never called does not make an issue done.

**Security, access and data loss** are never `CLOSE-DUPLICATE` or `CLOSE-NOT-PLANNED` without the
user's answer at the gate, and never closed on a breadth verdict.

## Close reason on GitHub

| Verdict | Close reason | Closing comment says |
| ------- | ------------ | -------------------- |
| `CLOSE-DONE` | completed | What did it: the commit or pull request and the file that shows it |
| `CLOSE-OBSOLETE` | not planned | What replaced or removed the subject, and where carried-over lines went |
| `CLOSE-DUPLICATE #x` | duplicate of `#x` | Which issue owns it now, and what was carried over |
| `CLOSE-NOT-PLANNED` | not planned | The decision and its link, and what would reopen it |

## Metadata

- **Type** follows the work, not the label: a defect is a Bug, new capability a Feature, everything
  else — refactors, docs, tests, ops, epics — a Task, unless the repository's instruction file says
  otherwise. Use only the types the repository has.
- **Labels** come from the existing set only. Where a label and the type both exist for the same
  idea, they agree. A missing label is one line in the report pointing to `labels-sync`.
- **Title** changes only when the title misleads or the repository has a title convention it breaks;
  the new title states what the issue now asks for.
- **Body** changes only when the body is wrong about the present — a stale fact, a narrowed scope —
  and then as a short note at the top or a dated section at the end, never a rewrite.

## Routing to depth

The breadth pass proposes; it finalises only `KEEP` and `BACKLOG` rows with metadata fixes. Read top
to bottom; any matching row sends the issue to depth.

| Breadth result | Why it cannot stand alone |
| -------------- | ------------------------- |
| Any `CLOSE-*` proposal | Every close needs the proof above, and a shallow pass misses live code and other issues |
| Type Bug, or a security, auth, token, permission, leak or data-loss subject | A shallow pass downgrades severity it cannot see |
| Claims the issue is covered by, depends on, or conflicts with another issue | Only a pass that reads both can say so |
| Claims code exists, moved, was removed, or is done | Needs the caller and the commit, not the name |
| A reference `refs.json` marks missing, or a citation that does not match it | The claim rests on a fact that is not there |
| Its cluster has another issue routed to depth | A cluster is judged together or not at all |
| `STALE-ASK` or `NEEDS-DISCUSSION` | Depth writes the owner question; breadth only proposes it |
