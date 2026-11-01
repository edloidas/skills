# Audit Prompt

The orchestrator fills the placeholders and sends everything below the line as the auditor's
whole brief. Send it to a fresh worker that did not write the spec under audit.

---

You are auditing a behavioral spec against the source it describes. Someone will rebuild the
system from this spec without reading the source, so every gap you miss becomes a divergence.
Read the source yourself and take no claim on trust. Report findings only. Do not rewrite the
spec and do not propose patches.

Read `{RULES}` and `{RUBRIC}` in full first. The rules file is the standard the spec was written
to. The rubric is the only source of severity.

Inputs:
- Mode: `{MODE}`. Either `module`, which audits one module spec and its cases, or `global`,
  which audits the contracts and the architecture map against every module spec.
- Spec files under audit: `{SPEC_FILES}`
- Source and test files: `{FILE_LIST}`
- Problems a script already found mechanically in these spec files: `{PRECHECK}`

Open every spec file and every source file in the lists in one response before writing a
finding. Every precheck line is confirmed. Report each as a finding with the severity the rubric
gives it, grouping lines that share one cause into one finding with a count. Spend your own reading
on what a script cannot see: meaning, order, and omissions.

Check, in `module` mode:
1. **Coverage.** Every public entry, entity, state, error path, config key, and integration in
   source is in the spec, or is named as finish or a non-goal.
2. **Truth.** Every claim matches the cited lines. A citation that does not show its claim is a
   finding.
3. **States.** An `observed` obligation whose evidence is really inference. An `inferred` one
   with no `Basis:`. An `unknown` with no open question.
4. **Cases.** Every case kind an obligation lists has an acceptance case. Every `Then` is literal
   and matches source. Every `Source: test` points at a test that asserts it.
5. **Literals.** A payload, message, or default that is paraphrased, or a secret left
   unredacted.
6. **Absence.** A `not found` or `MISSING` that a search would contradict.
7. **Gaps.** Sections marked N/A or `Not traced at summary depth.` that hide behavior a
   reimplementer needs.

Check, in `global` mode: flow hops against source; whether each message counterpart is real or
missing; shared-data ownership; disagreements between module specs that the contracts file did
not catch; and whether every architecture entry point is reached by a flow or an obligation.

Apply the rubric's fail-closed rules.

Write the result to `{OUT}`. If you cannot write files, return it instead. Use exactly this
structure, with no preamble:

```markdown
## Verdict: <module name or global>
<1–2 sentences: can a reimplementer build this from the spec alone, or must they reopen the
source, and where?>

## Critical (N)
1. **<Check name>** — <the gap or error>
   - Spec: `<spec file>` <OB, AC, or section id>
   - Source: `path:line` — <short quote, secrets redacted>
   - Impact: <what the rewrite would do differently>

## Warning (N)
<same format>

## Note (N)
<same format>

## Unverified
<Checks or files you could not complete, and why. `None.` if every check ran.>
```

Return one line when done: `Audited <name>: <c> Critical, <w> Warning, <n> Note, <u> unverified.`
