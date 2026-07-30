# Signal Classes

Patterns the retro skill scans for in the in-context conversation. These are
**guidance, not enforcement** — session analysis is partly vibes. The point of
the skill isn't rigorous within-session classification; it's producing
structured artifacts so cross-retro analysis can later spot recurring patterns.

When in doubt, save the finding with `low` confidence rather than dropping it —
unless it fails the value bar below.

## Classes

### Corrections

The user redirected your approach.

- "no, do X instead", "stop", "wait, actually"
- Reverted edits, redone commits, undone tool calls
- "that's wrong because…", "you misunderstood"
- User rewriting your output rather than accepting it

**Likely confidence:** `high` if explicit phrase, `medium` if inferred from a
revert.

### Tool friction

The environment fought you.

- Retried commands (same Bash call ≥2 times with tweaks)
- Permission denials, command-not-found, missing flags
- Repeated grep/find with different queries chasing the same target
- Bash hooks blocking commands

**Likely confidence:** `high` if recurred, `medium` if one-shot.

### Skill friction

A skill misbehaved or was missing something.

- Skill invoked, then output manually fixed up
- Skill produced a file the user immediately rewrote
- Skill missing an arg/flag the user expected
- Skill suggested a wrong target/path
- You had to reach outside the skill to finish what it started

**Likely confidence:** `high` if user explicitly complained, `medium` otherwise.
**Bucket:** affected skill's SKILL.md or scripts. Consider also running
`dev:skill-report` for permanent record outside this retro.

### Detours

You chased a wrong hypothesis before reaching the right one.

- ≥3 turns on a path that didn't pan out
- Several wrong hypotheses before the real cause emerged
- The eventual fix was small but obscured

**Likely confidence:** `medium`. The lesson is rarely "do X" — it's "check Y
first." Bucket as a rule or convention if there's a repeatable check.

### Wins

Things that went well and shouldn't drift.

- User explicitly praised an approach ("perfect, keep doing that")
- A non-obvious choice was accepted on first try and validated by the result
- A pattern you used worked first try and saved time

**Likely confidence:** `high` if explicit praise, `medium` if inferred from
clean acceptance. Wins matter — without them, only corrections accumulate and
you drift cautious.

### User mistakes / preferences

The user did something that caused rework, or revealed a preference worth
encoding.

- User asked you to redo work because their initial framing was off
- User stated a preference ("I always want X format")
- User asked for something the project's existing tooling could have prevented
  (a missing test, lint rule, type check)

**Likely confidence:** `high` if explicit, `medium` if inferred. Bucket as
CLAUDE.md, rule file, or tooling fix depending on shape.

## Value bar

Save a finding to the report only if **at least one** holds:

- The signal recurred ≥2 times in the session, OR
- The user stated the preference/rule explicitly, OR
- There is a concrete repeatable mitigation (a rule, a check, a skill edit, a
  config line) that the bucket router can target.

If none hold, drop the finding. One-off observations with no actionable
mitigation belong in a chat reply, not a retro file.

## When to mark `low` confidence vs drop

- **Save as `low`:** the signal is real but you're not sure it's a pattern
  (e.g., one frustrated turn, but the friction might be a one-off). Cross-retro
  analysis can later promote it if it recurs.
- **Drop:** the signal is too vague to even paraphrase a trigger, OR there's no
  imaginable mitigation, OR auto-memory already captured it.

## Things that are NOT signals

- The fact that the session happened.
- Generic praise like "thanks" with no content.
- Tool calls that succeeded normally.
- Routine clarifying questions answered cleanly.
- Anything you can't quote or paraphrase concretely.
