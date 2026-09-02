---
name: commit-summary
description: >
  Write a commit message body by deriving it from the code, not by summarizing the diff.
  Weighs the change, then either answers seven questions against the implementation — what
  forces it, which call paths reach it, how it failed, what breaks on update, what the tests
  pin — or produces a two-to-three-line body for mechanical and generated changes. Not for
  full commit creation.
when_to_use: >
  On "commit body", "commit summary", or "change description", and when another skill needs a
  body composed for a commit it is about to make.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Grep Bash(git status:*) Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git blame:*)
argument-hint: "['staged only', instructions, or empty]"
---

# Commit body writer

Produce the part of a commit message that is **not recoverable from the diff**.
Whoever reads the commit later already has the diff; what they do not have is what
the running code does that forced the change, which call reaches the broken path,
what breaks for someone who updates, when the defect was introduced, and what was
noticed and deliberately left alone.

Output the body text only — no subject line, no preamble, no commentary. The caller
owns the subject.

## Arguments

| Argument | Behavior |
| --- | --- |
| (empty) | Analyze staged + unstaged changes |
| `staged only` | Analyze the index only |
| a commit ref | Analyze that commit |
| anything else | Treat as additional instructions or context |

## Step 1: See the change

```bash
git status --short
git diff
git diff --cached
```

Read the actual hunks, not just the stat. You need the semantics of the edit to
weigh it.

## Step 2: Weigh the change

**Derive** (Step 3) when the change alters behaviour, a contract, a public type, or
a default, or when it fixes a defect.

**Report** (Step 4) when the change is mechanical (a rename, a mass import rewrite,
a formatting pass), generated (lockfiles, build output, snapshots, regenerated
trees), or purely additive scaffolding with no behaviour to describe.

Weight decides, not diff size. A one-line semantic fix derives. A rename across 30
files is one fact and reports.

A mixed change is weighed on its heaviest part: derive for the behaviour change,
and give the mechanical remainder one line.

## Step 3: Derive

Read `references/commit-body.md` and follow it. It carries the seven questions, the
table of which code is authoritative for each kind of change, the evidence rules,
the writing rules, and three worked bodies.

Four things from it that decide whether the output is worth its cost:

- **Answer against the code**, not the diff. Open the implementation behind the
  declaration, the client behind the handler, the changelog behind the bump.
- **Skip any question with no real answer.** Three honest paragraphs beat seven
  padded ones. Padding is the failure mode of this skill.
- **Never invent provenance.** A hash appears only if a command returned it in this
  session; an enumerated call path is traced in the source or reproduced. No result
  means the paragraph is dropped, not softened.
- **Plain words, short sentences**, in the register of the `explain` skill: trace the
  mechanism on real symbols instead of characterising it. Each paragraph opens on a
  past-tense verb, and the sentence after it is the reason, stated as behaviour.

When the caller hands over design rationale pulled out of source comments — a
cleanup pass reporting "Suggested for commit message" — that text answers *why the
code is built this way*. Fold it into the first paragraph. Do not append it as a
block at the end.

Output paragraphs, blank-line separated, wrapped at 80. A change with three facts gets
three, not seven:

```
`stableTypeOrdering` was added for TypeScript 6, where it defaulted to `false`.
TypeScript 7 enables it by default.

`moduleResolution: NodeNext` is implied by `module: NodeNext`, and `esModuleInterop`
defaults to `true` in TypeScript 7.

Kept `strict` explicit so the project adopts any stricter checks added under this
option in future TypeScript versions.
```

## Step 4: Report

For mechanical and generated changes, one sentence per line, two or three lines,
past tense, no blank lines, no bullets:

```
Renamed `useToggle` to `useToggleGroup` across 31 call sites.
Regenerated the Codex wrapper symlink trees.
```

Name what a reader cannot see from the file list — the count, the mechanism, the
tool that generated it. Do not invent a rationale paragraph for a change that has
none.

## Repo conventions win

Check the project's `CLAUDE.md`, `AGENTS.md`, or `CONTRIBUTING.md` for commit
conventions. A house style that caps body width, forbids paragraphs, prescribes a
template, or requires another language overrides both formats above. Answer as many
questions as it has room for, in order, and drop the rest.

## Footer

Add only when it applies, after a blank line:

- `Fixes #123` / `Resolves #456`
- `BREAKING CHANGE: <what changed>`
- `Co-authored-by: <a human's name> <email>`

## No attribution

The body ends on its last paragraph. Emit no "Drafted with AI" or "Generated with"
line, no session or transcript link, no `<sub>` line, no `---` rule, no badge, and no
`Co-Authored-By` trailer crediting an assistant. Never copy one forward from an
existing message — a trailer already in the log is not licence to repeat it.

This skill returns text and never runs `git commit`, so it cannot be the only guard.
The skill that assembles the final message strips these on the way to the commit —
see `build:commit` step 5 and `issue-flow` Step 3.

## Out of scope

- Subject lines, conventional-commit types, and issue-number suffixes.
- Running `git commit`. This skill returns text.
- Splitting a change into multiple commits. Question 7 makes the seam visible; the
  caller decides what to do about it.
- PR bodies and release notes. Different audience, different contract.
