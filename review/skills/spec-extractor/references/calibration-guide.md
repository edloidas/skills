# Calibration Guide

Forward-looking guidance for a future calibration skill that will consume `spec-extractor` output and regression-test prompt changes. No calibration harness ships with this skill in v0.1 — the user has elected to build that as a separate skill later.

## Purpose of calibration

Calibration is a regression gate. A frozen reference bundle plus its expected audit summary defines "acceptable spec quality." Any change to the spec-extractor prompts must keep existing references passing.

Without calibration, prompt edits drift. With calibration, prompt evolution has a feedback signal.

## Bootstrapping a reference

1. Pick a cohesive reference bundle. Target characteristics:
   - 200–1500 lines across 2–6 files (Small tier), or
   - ~20–40 files (Medium tier), or
   - A well-scoped workspace subset (Large tier).
   Prefer a neutral open-source library. Avoid proprietary code. Avoid code containing product-specific naming conventions the team wants to drop.
2. Run `spec-extractor` on the bundle.
3. Read the audit report. Manually review each finding:
   - Confirm Critical/Warning/Note assignments are correct per the rubric.
   - Downgrade or dismiss false positives.
   - Note any findings that are structurally valid but practically insignificant for this bundle.
4. Freeze the bundle definition and expected audit summary into a reference file (e.g. `calibration/<bundle-name>/reference.md`):
   - Bundle file paths (relative to repo root).
   - Tier used.
   - Expected severity counts: `critical: N`, `warning: N`, `note: N`.
   - Any known-acceptable findings that should be tolerated (with rationale).

## Threshold policy (suggested)

A run is accepted if:
- `critical ≤ reference.critical`
- `warning ≤ reference.warning`
- Note delta within tolerance (e.g. ±3).

A bundle that previously passed must continue to pass. Regressions block merge.

New reference accepted if initial run produces ≤ 1 Critical, ≤ 4 Warnings, ≤ 10 Notes.

## Growing the suite

- Every major skill change should add one new reference bundle from a codebase with different idioms (different language, different architecture pattern).
- After 3 bundles across 3 distinct stacks pass without prompt tuning, the skill's quality floor is considered established.

## Avoiding drift

- Reference bundles should be pinned to a specific commit in their source repo. Don't calibrate against a moving HEAD — the source changes will invalidate expected results.
- If a reference becomes invalid (upstream deleted, licensing changed, source drift too large), retire it and add a replacement rather than editing it in place.
- Keep reference audit summaries focused on counts and categories, not verbatim finding text. Auditor wording can legitimately vary between runs.

## Interaction with the `spec-extractor` output

A calibration skill would:
1. Read a reference definition (bundle paths + expected severity counts).
2. Invoke `spec-extractor` on the bundle.
3. Parse the resulting `audit.md` (or `spec.md` for Small tier) for severity totals.
4. Compare against reference.
5. Produce a pass/fail verdict and a delta report.

No machine-readable schema is emitted by `spec-extractor` today — the parser would grep for `## Critical (N)`, `## Warning (N)`, `## Note (N)` headers and count by section. If a future version adds JSON frontmatter or a machine-readable summary file, the parser can switch to it.

## What NOT to calibrate

- Do not calibrate against spec *content* (exact wording, exact section ordering beyond the schema). Content varies legitimately between runs.
- Do not calibrate against deep-dive module selection. Scout can defensibly nominate different modules across runs.
- Do not calibrate against exact `file:line` values in audit findings. Lines shift as source evolves.

Calibration targets the *shape* of the output — tier selection, section completeness, severity totals — not the specific claims.
