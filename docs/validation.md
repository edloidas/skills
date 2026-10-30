# Validation

Read this when a validator fails, or when you change one. Which checker owns what, and when each
must pass, is in [AGENTS.md](../AGENTS.md#skill-changes-are-gated); the authoring rules the
checkers enforce are in [writing-skills.md](writing-skills.md). This doc holds the ceilings, the
exemptions, and the reasons recorded for each.

## What `validate-skills.sh` Rejects in the Layout

It rejects a symlinked skill directory and a leftover group directory from the pre-6.0
`<group>/skills/<name>` or pre-4.0 `<group>/<name>` layouts (why skill directories must be real:
[packaging.md](packaging.md#why-skills-are-real-directories)). It also enforces the per-skill
rules that must never regress — required frontmatter, `name` matching the directory and the
naming format, `description` within 1,024 chars, the combined discovery entry within 1,536,
and no `references/`, `scripts/`, or `assets/` path in `SKILL.md` that the skill does not
ship.

## Body Budgets

The 500-line body cap is mechanical, so it lives in `validate-skills.sh` rather than in
`skill-audit`'s rubric. Two skills carry a larger budgeted allowance in
`BODY_LINE_BUDGETS`:

| Skill | Allowance | Why |
| ----- | --------- | --- |
| `skills/issue-flow` | 697 | **Sanctioned.** It owns every git and `gh` write in the issue pipeline — base detection, the fork point, the squash rules, the force-push lease. That concentration is the seam that let `solve-issue` and `changes-review` become portable, and splitting it would put the same rules in two files, which this repo treats as the drift mechanism. Its size is the cost of being the single writer. Raised from 1000 when stacked pull requests arrived: a branch's named parent is recorded in Step 2, the one place branches are created, and the squash, rebase and PR base follow it through `stack-sync.sh`; the procedure lives in `references/stacking.md`, the body keeps one pointer per call site. Lowered from 1010 when the issue-creation path — Step 1, sub-issues, project inheritance, blocked-by, batch — moved to `references/creating-issues.md`, read only on the router's create rows; the conventions Step 5 also cites stayed in the body. |
| `skills/solve-issue` | 538 | At 537 after the prompting-standard pass added a stop sentence and a named end-of-phase line to every phase, paid for by cutting the 21-row Error Handling table and the trailing `## Scope` recap and moving the deferral block into `references/review-feedback.md`. Raised from 540 to 550 deliberately, because three lines of headroom made every subsequent edit a trim-or-nothing choice on an 11-phase orchestrator that is still growing. The 13 lines now free are for the phases the auditors named — Phase 0 has no counted closing line, and the Phase 6 summary has no worked fragment in the body — not for general expansion. Lowered from 550 when the compaction pass cut what `issue-flow`, `live-probe`, `changes-review` and `references/review-feedback.md` already own. |

The ~5000-token cap is enforced the same way, estimated as body bytes / 4, because the
line cap alone let a body grow sideways — `changes-review` sat at 499 lines and ~7.3k
tokens. `BODY_TOKEN_BUDGETS` carries `issue-flow` (9900) and `solve-issue` (7410) for the
reasons above, both lowered from 13600 and 7650 by the same compaction pass. Both had been raised from 13000 and 7500 when slice delivery arrived, and
`issue-flow` again from 13400 for the stacked-parent record: the
per-slice reset point belongs in `issue-flow`'s Consolidate, the one owner of the squash
rules, and `solve-issue` keeps only the switch and its call sites in the body, with the
loop itself in `references/slices.md`. It also carries two skills grandfathered at their
size when the cap arrived: `changes-review` 6490, `code-cleanup` 5590, both lowered from 7500 and
6500 when the review and assist compaction pass trimmed them, to their new size plus about 2%.
Those ceilings stop growth and sanction nothing; lower a row whenever its skill is trimmed, and
delete it once the skill fits the cap — `consilium` and `security-audit` left the table that way.

A budget is a per-skill ceiling, not an exemption — a budgeted skill that grows past its
allowance still fails, so a deliberate size cannot drift into an accidental one. Adding a
row is a decision that needs a reason in this doc.

`body_line_count` counts every line after the frontmatter, **horizontal rules included**.
It used to skip each `---` in the file rather than only the two delimiters, which made a
body measure smaller than what the agent actually loads: `issue-writer` reported 498 lines
against a real 507, because nine `---` rules sit inside its issue templates. Six other
skills were undercounted too, none of them across a ceiling — `changes-review` at 451 is now
the closest to the line cap. A checker that reads low is worse than no checker, so if the two
counts ever disagree again, trust neither until you know which one is wrong.

`skill-audit` does not re-score a budgeted skill for its size. The validator owns the
mechanical limit; the rubric still judges whether heavy material is deferred, whether the
length is proportionate, and whether anything is duplicated into `references/`.

## Claude-Only Pattern Detection

What a portable skill may not contain, and why, is in
[writing-skills.md](writing-skills.md#claude-only-mechanisms). Detection lives in
`CLAUDE_ONLY_PATTERNS` in `validate-skills.sh`. Note the comment there about
`(^|[[:space:]])`: BSD grep treats `^` inside a group as a literal, so the anchored
alternative matches nothing on macOS while passing on CI's GNU grep. Two `-e` patterns are
the portable form.

One skill is exempt from the *portability* patterns, via `CLAUDE_ONLY_EXEMPT`:

| Skill | Why |
| ----- | --- |
| `skills/skill-audit` | Its subject matter *is* these mechanisms — the rubric and the dispatched prompt have to name them to tell an auditor what to look for. The exemption is skill-wide, so a genuine violation inside it would go uncaught; acceptable because it dispatches as intent and has no workflow of its own a host could fail to run. |

Adding a row is a decision that needs a reason in this table. The exemption is not a way
past a finding — a skill that *uses* one of these mechanisms narrows its `compatibility`
or states the step as intent instead.
