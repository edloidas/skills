# Playbook: Investigate

Find a fact about this system — a caller, a cause, a date, a dependency — and change nothing. This
playbook is read-only: it reads files, runs read-only commands, and creates nothing it does not
remove.

1. **Write the question** as one sentence with a checkable answer.
2. **List where the answer can live** — code, git history (`git log -S`, `git blame`), the pull
   request or issue that introduced it, CI logs, docs — and open every one you list in one
   response. Past about 5 files or 1000 lines, split the reading across subagents over disjoint
   slices, each returning the facts it found with `file:line`; with no subagent facility, read
   the slices yourself.
3. **Run what can be run.** A claim about runtime behaviour is settled by the `live-probe` skill,
   not by reading.
4. **Label each fact** `direct` (read or observed, with its source), `inferred` (follows from
   direct facts — say from which), or `unknown` (what would settle it). Code shows what it does,
   not why it was written that way: a reason needs a commit, an issue, or a doc behind it.

Answer the way the `explain` skill does: the answer first in one sentence, then the trace that
supports it, each step carrying its label.

End with one line: `Answer: <one sentence> (<N> direct, <N> inferred, <N> unknown).`

Then write the report (SKILL.md, Phase 4). Do not fix what you found; a fix is a new task the user
starts.
