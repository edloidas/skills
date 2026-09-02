---
name: tsconfig-audit
description: >
  Audit tsconfig.json against TypeScript 7 and report which compilerOptions are hard errors,
  which are redundant and safe to drop, and which must now be added.
when_to_use: >
  When migrating a TypeScript 5.x or 6.x config to 7, cleaning up an overgrown tsconfig, or
  checking whether `baseUrl`, `outFile`, `downlevelIteration`, `esModuleInterop`,
  `moduleResolution`, or `rootDir` is still needed. Also on "audit tsconfig" or "which
  compilerOptions are deprecated".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(node:*) Read Glob Grep Edit
argument-hint: "[path-to-tsconfig]"
---

# tsconfig Audit

## Purpose

**This skill reports by default and writes only after the user approves it in Step 6.** Nothing
before that step touches a file: Steps 1-5 read, run the checker, and print. An approved apply
edits `tsconfig.json` files inside the project and nothing else — no commit, no push, no
`node_modules`.

Report what a `tsconfig.json` should look like on TypeScript 7:

- Options and values TS7 rejects outright, with a migration for each
- Options that are redundant — locked to one value, implied by another option, or equal to a default
- Options that became load-bearing because a default changed, and must now be written explicitly
- Options that look droppable but should be kept

## When to Use This Skill

Trigger phrases: "tsconfig audit", "tsconfig cleanup", "TypeScript 7 migration", "compilerOptions", "drop tsconfig options".

## Scope

This audits `compilerOptions` only. `include`/`exclude`/`files` are read to reason about
`rootDir`, not audited. It does not touch dependency hygiene, lint config, or build scripts.

The target is always TypeScript 7. Advice for staying on 5.x or 6.x is out of scope — those
configs are audited against what 7 will require of them.

## How It Works

The compiler is the authority wherever it can answer, so the audit stays correct as TypeScript
releases move:

| Source | Answers |
| ------ | ------- |
| `tsc --noEmit` diagnostics | Removals (`TS5102`/`TS5108`), unknown options (`TS5023`), invalid values (`TS6046`), illegal combinations (`TS5095`) |
| `tsc --showConfig` | Options *implied* by another option, and the fully resolved `extends` chain |
| `references/ts7-options.json` | Defaults, locked values, which unknown options are legacy removals rather than typos, keep-list |

Two things the compiler will not tell you, which the script handles itself:

- **`--showConfig` swallows config errors.** It prints a config containing a removed option and
  exits 0. It is never used as a diagnostics source.
- **Diagnostics anchor to the leaf config**, even when the option was inherited from a base inside
  `node_modules`. The script walks the `extends` chain itself to attribute each option to the file
  that really set it.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Workflow

### Step 1: Find the configs

Unless the user named one, list the candidates before auditing anything:

```bash
# Glob: **/tsconfig*.json, excluding node_modules
```

A repo commonly has several — a root config plus build, site, test and benchmark variants, each
extending the root. Audit the one the user meant, and say which others exist rather than silently
auditing only the root. A config reached through `extends` is covered automatically as part of the
chain; a sibling config is not.

Close the step with one line: `Configs: 4 found, auditing tsconfig.json (extends @tsconfig/node22), 3 siblings not audited.`

### Step 2: Run the checker

```bash
node <skill-dir>/scripts/tsconfig-check.mjs [path/to/tsconfig.json]
```

Add `--json` for structured findings when you need to post-process them. Use `--tsc <path>` to
point at a specific compiler.

The script needs a TypeScript compiler. It looks for `node_modules/.bin/tsc` upward from the
config, then `tsgo`, then `tsc` on `PATH`. If none is found it stops rather than guessing — do not
work around this by hand-reasoning about the config.

If the compiler found is older than 7.x, the script still runs and says so. Findings from the data
file stay TS7-accurate, but removal and unknown-option findings come from the older compiler and
will understate what TS7 rejects. Say this plainly in the report rather than presenting partial
results as complete.

### Step 3: Read the findings

Each finding carries `option`, `action`, `reason`, `severity`, `confidence`, `sourceFile` and
`editable`. With `--json` they arrive as a flat list — group them yourself; the grouping is a
presentation choice, not part of the data:

```json
{
  "option": "baseUrl",
  "value": "./src",
  "action": "remove",
  "reason": "removed-in-ts7",
  "severity": "error",
  "confidence": "high",
  "sourceFile": "tsconfig.json",
  "editable": true,
  "suggestion": "\"paths\": {\"*\": [\"./src/*\"]}"
}
```

Group them for the user by severity:

1. **Blocking** — `severity: error`. The build fails on TS7 until these are fixed.
2. **Must add** — `reason: conditional-add`. Nothing errors; the output silently moves or globals
   silently vanish. Explain the concrete consequence, not just the flag.
3. **Safe to drop** — `locked-value`, `implied-by`, `matches-default`.
4. **Keep** — `keep-list`, `external-consumer`.

Two flags change what you can offer:

- `editable: false` means the option lives outside the project (typically an `@tsconfig/*` base in
  `node_modules`). Never edit it. Offer a local override instead, and say which package owns it.
- `needsResearch: true` means TS7 reported an unknown option that is not a known legacy removal.
  Go to Step 4.

### Step 4: Research unknown options

An unrecognised option is one of three things, and they have opposite fixes:

- a **typo** — suggest the nearest real option from `knownOptions` in the data file
- a **third-party extension** (`ts-node`, `tsc-alias`, `@vue/tsconfig`) — a sibling key like
  `ts-node` is legal and must be left alone; only `compilerOptions` entries are audited
- **newer than the data file** — a genuine option added after `tsVersion`

Grep the repo for the option name and for any tool that would own it — a `ts-node` or `tsc-alias`
dependency in `package.json` settles the second case without a web lookup. Otherwise check the
current TypeScript release notes and the option reference for the name before advising.
Then report it to the user as a gap: name the option, say which case it was, and propose the
concrete `references/ts7-options.json` change that would let the checker classify it next time.
Do not silently recommend deleting an option you could not identify.

### Step 5: Report

Lead with the blocking findings and the concrete failure each one causes. Then the must-add
findings, then the safe drops as a single grouped list, then anything to keep and why.

Close with a **Not checked** list, one line per item with its reason. Everything the run could not
cover goes there — sibling configs from Step 1, the configs behind project `references`, an option
Step 4 could not identify, and any finding class the compiler could not produce because the `tsc`
found was older than 7.x. State the compiler and data-file versions the audit ran against; if they
differ, that is a `Not checked` line too. A report without this section reads as a full solution
audit.

A filled report:

```markdown
## tsconfig audit — tsconfig.json (tsc 6.4.2, data file TS 7.0.2)

### Blocking (2)
- `baseUrl: "./src"` — removed in TS7 (`TS5102`); the build stops before typechecking.
  Fold the prefix into `paths`: `"paths": { "*": ["./src/*"] }`.
- `moduleResolution: "node"` — value removed in TS7 (`TS6046`). Use `"bundler"`; this project
  is built by Vite, so no `.js` extensions have to be added to relative imports.

### Must add (1)
- `target` is unset. In TS7 the default floats to the newest stable ECMAScript version, so the
  emitted syntax changes the day the compiler is upgraded. Pin `"target": "es2023"` — what the
  current compiler already emits.

### Safe to drop (4)
`esModuleInterop`, `allowSyntheticDefaultImports` (implied by it), `skipDefaultLibCheck`
(implied by `skipLibCheck`), `forceConsistentCasingInFileNames` (matches the TS7 default).
Cleanup, not required work — defaults can move between releases.

### Keep (2)
- `strict: true`, `module: "esnext"` — keep-list; both are load-bearing on the TS7 defaults.
- `declaration: true` — `external-consumer`: this package ships `types` in `package.json`.

### Not checked
- `tsconfig.build.json`, `tsconfig.test.json`, `site/tsconfig.json` — siblings, not reached
  through `extends`. Offer to audit each.
- Removal and unknown-option findings came from tsc 6.4.2, not 7.x, so they understate what TS7
  rejects. Re-run against a 7.x compiler to close this gap.
- `tsc-alias` sibling key — not a `compilerOptions` entry; out of scope, left alone.
```

### Step 6: Offer to apply

Ask before writing, per **Asking the User**:

1. **Apply blocking fixes and safe drops** — everything except the keep findings
2. **Apply blocking fixes only** — the minimum to build on TS7
3. **Report only** — change nothing

When applying:

- **Apply one targeted edit per option.** Remove or change the specific lines and nothing else.
  Never rewrite or reserialize the whole file: `tsconfig.json` is JSONC and routinely commented,
  and a reserialize strips every comment and reorders every key.
- **Only edit files inside the project.** For `editable: false` findings, add a local override.
- **Capture a baseline first**: `tsc -p <config> --noEmit --locale en` before any edit.
- **Verify after**: rerun it and compare the *set* of diagnostics, not the count — an equal count
  can hide a different failure.
- **When the config emits**, also compare emitted paths before and after
  (`tsc -p <config> --listFilesOnly` plus the resolved `outDir` layout). This is the only check
  that catches a `rootDir` regression, which `--noEmit` structurally cannot see.
- If verification regresses, revert your own edits and report what happened. Do not leave the
  config half-migrated.

Then stop. Report what was applied and what verification said; do not audit the sibling configs,
do not commit, and do not start a second apply round on findings the chosen option excluded.

## Cautions

- **`baseUrl` and `paths` are not tsc-only.** Bundlers, Vitest/Jest and IDEs resolve them
  independently. A clean typecheck after dropping them proves nothing about runtime resolution.
  When `baseUrl` is removed, every relative `paths` entry needs its prefix folded in — the checker
  computes the rewrite.
- **`target`, `module`, `lib` and `strict` are on the keep-list on purpose.** The TS7 `target`
  default floats to the newest stable ECMAScript version, so dropping it makes emit change on a
  compiler upgrade.
- **"Matches the default" is a weaker claim than "removed".** Defaults can move between releases;
  a removal will not come back. Present drops as cleanup, not as required work.
- Never recommend `ignoreDeprecations` as a fix. It did nothing in TS7 — removed is removed.

## Keeping the Data File Current

`references/ts7-options.json` is generated. Do not hand-edit it.

```bash
node <skill-dir>/scripts/refresh-options.mjs [--tag typescript/v7.0.2] [--tsc <path>]
```

It pulls the compiler's own option declarations from the pinned `microsoft/typescript-go` release
tag, then probes an installed `tsc` for removals, enums and implications. Probes win where the two
disagree — the declared defaults are help strings and are wrong in places. `rootDir` declares
"Computed from the list of input files" but is fixed at `.`, and the 7.0 release notes claim
`stableTypeOrdering` cannot be disabled while the compiler accepts `false`.

Regenerate when a new TypeScript release ships, or when Step 4 turns up an option the data file
does not know.

## Reference Files

- `references/migrations.md` — the fix for each removed option and value
- `references/ts7-options.json` — generated option data
