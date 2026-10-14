# Final Report

Printed once, at Phase 7, from `run.json`, `notes.md`, and one `pr-state.sh` read per PR. A value
nobody observed in this run is written `not checked`, never guessed.

## Shape

````markdown
**Run complete** — <owner/repo>, <N> units, <branching>, endgame <pr|merge>
**Goal:** <the goal> — <holds | holds except: <what is missing>>

| Unit | PR | Base | State | Bot | CI | Notes |
| ---- | -- | ---- | ----- | --- | -- | ----- |
| #<N> <short title> | [#<M>](<url>) | `<base>` | open / merged `<sha7>` / blocked | reviewed / skipped / none | pass / fail | <one short note or blank> |

**Merge order:** <for a stack: bottom to top, and that closing keywords fire only once each PR
reaches the default branch. Otherwise "independent", or the order a conflict forces.>

**Decided unattended**
- <unit>: <choice> — <one-line reason> (<consilium | doubt>)

**Filed during the run:** #<N> <title> — <why>

**Needs you**
1. <the action, who can take it, and the command when there is one>

Working copy: on `<branch>`. <Removed: <N> worktrees and their local branches. | Nothing to clean up.>
Run state: <path> (closed)
````

A decision or review unit with no PR of its own takes one row with `—` in the PR columns and its
outcome in **Notes**. Drop **Decided unattended** and **Filed during the run** when empty.
**Needs you** is numbered so the user can answer by number; merge it from every summary in the
run, drop what a later unit resolved, and order it by what blocks the most. An item that is a
choice gets a briefing, not a line.

## Example

````markdown
**Run complete** — enonic-playground/grieg, 3 units, parallel, endgame merge
**Goal:** a basic working MCP server without the identity and OAuth work — holds except: #18 is not merged

| Unit | PR | Base | State | Bot | CI | Notes |
| ---- | -- | ---- | ----- | --- | -- | ----- |
| #12 restrict workflow nodes to admins | [#18](https://github.com/enonic-playground/grieg/pull/18) | `main` | open | reviewed | pass | merge refused by the permission policy |
| #5 content paging, schema and create | [#19](https://github.com/enonic-playground/grieg/pull/19) | `main` | merged `7356a60` | reviewed | pass | audit split out to #17 |
| Decision: cap on refusal paths | — | — | done | — | — | kept at ten plus a count |

**Merge order:** independent; #18 and #19 both edit `AGENTS.md`, so #18 rebases if GitHub reports a conflict.

**Decided unattended**
- #5: cap refusal paths at ten per response, plus a count — one long item set cannot blow up the reply (doubt)

**Filed during the run:** #17 write MCP audit log entries — split from #5 so the rest could ship without a live audit check.

**Needs you**
1. Merge #18: `gh pr merge 18 --repo enonic-playground/grieg --rebase --delete-branch`, or allow `gh pr merge` for this repo and I'll send a worker.
2. Live check on XP for both PRs: one pass on `main`, held until #18 lands.

Working copy: on `main`. Removed: 2 worktrees and their local branches.
Run state: ~/.local/state/orchestrate/enonic-playground-grieg/20261013-1602/ (closed)
````
