# A Filled Frame

The frame Phase 1 announces and every seat receives, for the same decision as the filled-in report in
`synthesis-guide.md`. Candidate A is recorded in Phase 1 but is not part of it.

```
Decision: where tower's runtime binaries (GLB, textures, audio) live and how they reach `dist/` with
hashed URLs, as assets grow past today's 7 KB model.
Hard constraints: startup assets are mandatory (issue #7) · catalog keys are a save-file contract
(issue #7, `docs/direction.md`)
Preferences: binaries stay out of git (the user wrote "probably")
Non-goals: source art (`.blend`, layered textures) and its pipeline; runtime streaming or CDN delivery
Current state (C0): `src/assets/tower.glb` is committed, imported with `?url`, typed in
`src/assets/catalog.ts`. Works; nothing checks size or naming.
Severity scale: Blocking — a clean checkout cannot build a playable game · Material — every
contributor or CI run pays a new setup step or credential · Minor — one extra line per new asset
Do not modify files; probes go in a fresh temp directory outside the repository, deleted before you report.
```
