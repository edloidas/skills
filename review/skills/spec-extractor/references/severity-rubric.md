# Severity Rubric

Used by `spec-auditor` and by any calibration or review process that consumes spec-extractor output. Mirrors the rubric embedded in the auditor agent.

## Critical

A finding is Critical when any of the following holds:

- A reimplementer following the spec would produce different observable behavior than the source.
- The source has a behavior the spec entirely omits, and the omission is not covered by a documented non-goal.
- A cited contract slot does not exist in source.
- A claim is factually wrong — an import that isn't there, a payload field that isn't produced, a lifecycle step out of order in a way that changes observable effect.
- A register without a matching unregister was not flagged, and the leak is observable.

## Warning

A finding is Warning when any of the following holds:

- The spec has a real gap a reimplementer would notice and need to fill by re-reading source.
- A branch, case, or empty handler was paraphrased instead of stated as observable behavior.
- A payload was paraphrased instead of transcribed literally.
- A params / payload / options object had fields unenumerated.
- An asymmetry in event fire/listen was missed.

## Note

A finding is Note when any of the following holds:

- Minor omission or imprecision.
- Missed cross-reference that does not change implementable behavior.
- Wording slip that a reimplementer would pattern-match through.
- Aesthetic placeholder language that did not violate the no-placeholder rule but could be sharper.

## Dismissal Criteria

- If a finding is structurally true but practically insignificant for reimplementation, downgrade to Note.
- If a finding is outright wrong — the reviewer misunderstood scope — dismiss with a brief rationale.
- Never downgrade because the finding is inconvenient. Severity is determined by reimplementation impact, not by how much work the fix would be.

## Applying the Rubric

- Per-module audit findings are scored against the module's deep spec.
- Global audit findings are scored against the architecture, modules catalog, and contracts documents.
- Consolidated audit.md groups findings by severity, with module attribution on each finding.

## Calibration Use

A future calibration skill will parse audit outputs and count findings by severity to gate regression tests. Keep the rubric stable — changing its definitions invalidates existing references.
