# Recommending a Permanent react-doctor Setup

Track A always uses the ephemeral runner — fetched for the run, cached outside the project, gone
afterwards. That holds even when you are about to recommend a permanent setup, and it holds if the
user says yes: they run the install, not you.

A permanent setup is worth recommending anyway, because the ephemeral run is a snapshot. Installed,
react-doctor runs from a `doctor` script, scans each PR in CI, and is available to the agent between
audits.

Recommend it when **all** of these hold:

- **The repo is large enough to keep paying off.** 20+ React files, or an established component
  tree. A handful of components does not need a CI gate
- **Nothing already sets it up.** No `doctor.config.{ts,mts,cts,js,mjs,cjs,json,jsonc}`, no
  `reactDoctor` key in `package.json`, no react-doctor dependency, no react-doctor CI workflow
- **The scan actually found something.** Recommend on any `error`-severity entry in
  `diagnostics.json`, or on a real volume of `warning`-severity ones. A clean scan is an argument
  against the recommendation, not for it

```bash
jq -r 'group_by(.severity)[] | "\(.[0].severity): \(length)"' "$DIAG/diagnostics.json"
```

**Put it at the very end** — the last lines of the output, after the summary table and after every
finding. It is a suggestion about tooling, and it must never sit between the reader and the findings
they came for:

> react-doctor found N issues here (E errors, W warnings) and is not set up in this repo.
> `bunx react-doctor@latest install` adds it as a dev dependency, a `doctor` package script, a skill
> for your agents, and a CI workflow that scans each pull request.

**Recommend it, never run it — including with `--dry-run`.** Observed behavior of `install` in
0.9.12: it adds a `doctor` script and a `react-doctor` devDependency to `package.json`, writes a
lockfile, populates `node_modules`, adds `.github/workflows/react-doctor.yml`, and drops a skill
directory into the config directory of every agent it detects. `--dry-run` printed a "would install"
list and the same writes still landed, so treat it as an install, not a preview.

Say it once, and drop it if the user has declined before.
