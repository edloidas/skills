# Verdicts

The only home of the verdict set and the proof each one needs.

| Verdict | Means | Proof required — all of it | Without the proof it becomes |
| ------- | ----- | -------------------------- | ---------------------------- |
| `CLOSE-DONE` | What it asked for now exists | A merged pull request or commit on the default branch that is not a dependency bump, the file and line at HEAD showing the behaviour on a live path, and every requirement mapped to it | `KEEP`, with a note on what is left |
| `CLOSE-OBSOLETE` | What it is about no longer exists | The subject is gone at HEAD, named with the commit that removed or replaced it, and the close bar below | `KEEP` or `STALE-ASK` |
| `CLOSE-DUPLICATE` | Another open issue covers it | One sentence of the problem both satisfy, `duplicate_of` covers every requirement or the carry-over lines are named, and that issue is not closing in this run | `KEEP`, cross-linked |
| `CLOSE-NOT-PLANNED` | Someone with the authority decided against it | A recorded maintainer decision, cited by link, or the user's answer at the gate | `STALE-ASK`; never the agent's own product call |
| `KEEP` | Valid and current: assigned, in an open milestone or sprint, or active in the last 6 months | Its premise checked at HEAD | — |
| `BACKLOG` | Valid, but none of that | As `KEEP` | — |
| `STALE-ASK` | No proof it is dead, no recorded decision, not updated in 12 months | Its owner: `lint.json` names one — assignee, else a maintainer author, else the last maintainer who commented; with none, CODEOWNERS or the question goes to the user | — |
| `NEEDS-DISCUSSION` | Only people can settle it | The question and who answers it | — |

**The close bar.** An issue closes only when what it describes demonstrably no longer applies and
nothing worth keeping is lost — or the lines worth keeping are named with where they move first.

**Age is not evidence.** An old idea still valid is `BACKLOG`; an operations item with no code
footprint here is `STALE-ASK`. When unsure, keep: a wrong close costs a reopen and a lost idea, a
wrong keep costs one row next run.

**Security, access and data loss** are never `CLOSE-DUPLICATE` or `CLOSE-NOT-PLANNED` without the
user's answer at the gate.

## Close reason on GitHub

| Verdict | Close reason | The closing comment says |
| ------- | ------------ | ------------------------ |
| `CLOSE-DONE` | completed | The commit or pull request and the file that shows it |
| `CLOSE-OBSOLETE` | not planned | What replaced or removed the subject, and where carried lines went |
| `CLOSE-DUPLICATE` | duplicate | Which issue owns it now, and what was carried over |
| `CLOSE-NOT-PLANNED` | not planned | The decision and its link, and what would reopen it |

## Metadata

- **Type** follows the work, not the label: a defect is a Bug, new capability a Feature, anything
  else a Task, unless the repository's policy says otherwise. Only types the repository has.
- **Labels** come from the existing set; a missing label is one report line pointing to
  `labels-sync`. Where a label and the type name the same idea, they agree.
- **Title** changes only when it misleads or breaks the repository's title convention.
- **Body** changes only when it is wrong about the present, as a short note on top — never a rewrite.
