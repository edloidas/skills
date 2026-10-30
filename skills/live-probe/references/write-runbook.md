# Write-runbook mode

Writes the project's "Running and observing" section: the declared way to run the project and
observe it, which a later probe finds first. The output is a section in the instruction file the
project already uses, not a script and not a new skill.

Run it only on the user's request. It writes two things: the section in the instruction file, and
the evidence files of the proof run, kept where the Evidence step names and listed in the report.
It does not touch source, and it commits nothing.

Done means: the section is written and every step in it either ran once as written or is marked
unverified with its reason — or the report names the step that blocked writing anything.

## 1. Find the instruction file

Use the file the project's agents already read: `AGENTS.md` or `CLAUDE.md` at the repo root. When
one is a symlink to the other, edit the real file. When both are real files, edit the one that
already holds the build and test commands. When neither exists, write nothing and report that the
project has no instruction file to add the section to; creating one is the user's call.

When the file already has a "Running and observing" section, this run updates it: re-prove every
step and change only the lines that no longer hold.

End with one line: `Instruction file: <path> (<new section | updating section verified at <sha>>)`.

## 2. Discover each step from the repo

Read, in one batch, every source that declares how the project runs: the instruction layer and the
docs it points at, manifest scripts, `Makefile` or task runner, CI workflows, container and compose
files, the README's quick start, and the entry points they name. From those, fill in:

| Step | What it answers | Typical source |
| ---- | --------------- | -------------- |
| **Launch** | The command that starts the project for observation, from a clean checkout, with its ports, env vars, and seed data | Dev script, compose file, README quick start |
| **Ready** | How to tell it can be used, not only that a process answers: a log line, a health endpoint, a prompt | Health route, startup log, CI wait step |
| **Doctor** | One read-only check that says this instance is worth driving: the process is up, the port is owned by this run, the build is the current one | Health or version endpoint, `--version`, a status command |
| **Drive** | The main user paths, one to three of them, each with the exact command, request, or route a user would use | Routes, CLI commands, existing end-to-end specs |
| **Evidence** | What to capture for each path and where it goes: response body, exit code, log line, screenshot | Instruction layer's artifact directory, else the scratch location |
| **Cleanup** | How to stop what the launch started and remove scratch state, keeping the evidence | Stop script, compose down, the process the launch started |

A short-lived CLI has no server: Launch is the build, Ready is the built binary answering
`--version` or `--help`, and each Drive runs on its own.

Only commands the repo declares go into the section — the same rule as SKILL.md's "Finding the way to
run". Where the repo is silent on a step, the step is written as unverified with what is missing;
do not fill it with a command the ecosystem usually has.

End with one line: `Discovered: <n> drive paths; missing: <steps the repo is silent on, or none>`.

## 3. Prove each step once

Run the steps in order, exactly as they will be written: launch, wait for ready, doctor, each drive
path with its evidence captured, cleanup. Then confirm two things after cleanup — the evidence is
still at its named location, and nothing this run started is still running or listening.

The rules in SKILL.md's "Running things without breaking things" hold throughout: probe port
ownership before launch, clean up only what this run started, suppress anything that opens a window.

When a step fails, correct the recipe — a missing env var, a wrong port, a readiness signal that
fires too early — and run cleanup before retrying. Two attempts per step. A step that still fails is
written as unverified with the failure. When launch itself fails, write nothing: report the failing
command and its output, since a section built on a launch that does not work teaches wrong steps.
A failure that is the product being broken, not the recipe, is reported as a finding and not
worked around in the section.

End with one line: `Proved: <n> of <m> steps ran as written; unverified: <step — reason, or none>`.

## 4. Write the section

Add the section with a targeted edit — insert it after the build and test commands, or at the end
of the file — never by rewriting the file. Record `git rev-parse --short HEAD`; when the tree had
uncommitted changes in files the steps depend on, say so next to the sha.

The section, filled for a small web service:

````markdown
## Running and observing

Verified at `3f9c2ab` on 2026-10-30. Re-prove a step that fails before trusting the rest.

- **Launch**: `docker compose up -d db && pnpm dev --port 4310` — needs `.env` copied from
  `.env.example`; seeds demo data on first start.
- **Ready**: `curl -fsS localhost:4310/healthz` returns `{"status":"ok","db":"up"}`; the process
  answers on the port about two seconds before `db` reports `up`.
- **Doctor**: `lsof -ti :4310 -sTCP:LISTEN` returns the PID this run started, and
  `curl -fsS localhost:4310/version` returns the current `git rev-parse --short HEAD`.
- **Drive**:
  1. Sign in: `curl -fsS -c .tmp/cookies -d 'user=demo&pass=demo' localhost:4310/login` → 302 to
     `/projects`.
  2. List projects: `curl -fsS -b .tmp/cookies localhost:4310/api/projects` → JSON array of 3 demo
     projects.
  3. Export: unverified — the export route needs an S3 bucket the local setup does not provide.
- **Evidence**: response bodies and status lines into `.tmp/probe/`; keep them after cleanup.
- **Cleanup**: stop the `pnpm dev` process this run started, then `docker compose stop db`;
  remove `.tmp/cookies`. Leave `.tmp/probe/`.
````

End with one line: `Wrote "Running and observing" to <path>, verified at <sha>`.

## 5. Report

One block, then stop:

```text
- **Runbook**: <path> — <new section | updated section>, verified at <sha>
- **Proved**: <the steps that ran as written>
- **Unverified**: <step — reason, one per line, or "none">
- **Findings**: <product failures seen while proving, or "none">
- **Cleanup**: <what was stopped and removed; where the evidence from the proof run is>
```

Do not commit the edit, do not fix a product failure the proof run surfaced, and do not go on to
probe a claim — the user asked for the section, and the section is the deliverable.
