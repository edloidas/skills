---
name: markdown-writing
description: >
  Write Markdown that people actually read — READMEs, docs, PR bodies, issue
  bodies and comments, release notes, changelogs. Covers GitHub-flavored extras
  (alerts, collapsible sections, task lists, mermaid), prose that leads with the
  point instead of burying it, and a README skeleton. Use whenever you are
  drafting or editing a .md file, a PR description, or an issue comment.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
argument-hint: "[file or topic]"
metadata:
  author: edloidas
---

# Markdown Writing

Two things decide whether Markdown is good: **where it renders** (which syntax
you may use) and **how it reads** (whether anyone finishes it). Handle them in
that order.

## 1. Check the render target first

| Renders where | What you may use |
| --- | --- |
| GitHub only — issues, PRs, comments, discussions, wiki, repo file views | Everything, including alerts, `<details>`, task lists, footnotes, mermaid, theme-aware images |
| README that also ships to npm, PyPI, a docs site, or an editor preview | CommonMark + tables + `<details>`. Treat GitHub extras as degradable, not free |
| Terminal, `--help` output, plain-text logs | No Markdown. Write plain text |

The degradation that matters in practice: **a GitHub alert renders on npm as a
plain blockquote with a literal `[!IMPORTANT]` line above the text.** That is
acceptable — use alerts in a published README anyway — but only if the sentence
after it stands on its own without the label. An alert whose body reads "This
one." is meaningless the moment the label stops rendering.

Full syntax and per-host support: `references/github-features.md`.

## 2. GitHub alerts

Five types, exact spelling, uppercase, nothing on the label line:

```markdown
> [!NOTE]
> Highlights information that users should take into account, even when skimming.

> [!TIP]
> Optional information to help a user be more successful.

> [!IMPORTANT]
> Crucial information necessary for users to succeed.

> [!WARNING]
> Critical content demanding immediate user attention due to potential risks.

> [!CAUTION]
> Negative potential consequences of an action.
```

Picking one:

- **NOTE** — a true fact that a skimmer would otherwise miss. No stakes.
- **TIP** — an optional shortcut. Deleting it costs nothing.
- **IMPORTANT** — they will fail without this. Version floors, required config.
- **WARNING** — doing it wrong has consequences. Deprecations, data loss, footguns.
- **CAUTION** — the consequence of an action they are about to take.

Rules that keep them working:

- **Rare.** Two or three per document. When everything is highlighted, nothing is.
- **Not a section.** An alert is one to four lines. Longer means it is a section
  with a heading.
- **Not a wrapper for the obvious.** If the plain sentence would have been read
  anyway, leave it plain.
- **Never stacked.** Two alerts in a row read as noise.

Good uses: the version floor in an install section, a deprecated package banner,
"this operation is destructive", the one constraint in an epic issue that every
child issue depends on.

## 3. Write for someone with no time

Assume the reader is skimming, on a phone, or has ADHD. All three want the same
thing: the point, early, in short pieces.

- **Lead with the point.** The first sentence of a section answers "what is this
  / what do I do". Background comes after, or not at all.
- **Show, then explain.** Put the code block or the command first and the
  paragraph about it second. A working example answers more questions than three
  paragraphs.
- **One idea per paragraph.** Two to four sentences. A wall of text is skipped
  whole, so the point inside it is lost.
- **Short sections.** If a section runs past a screen, it is two sections — or
  it is a table pretending to be prose.
- **Talk to the reader.** Second person, active voice, present tense. "Pass a
  seed to reproduce the roll", not "A seed may be passed in order for the roll
  to be reproduced". You are explaining something to a person, not filing a
  report.
- **Concrete beats abstract.** Real values, real output, real filenames. Put the
  result in a trailing comment: `result.total; // 14`.
- **Numbers beat adjectives.** Not "blazingly fast" — `0.49 µs per roll`. Not
  "tiny" — `11.9 kB brotli`.

Delete on sight: "Note that", "It is important to note", "simply", "just",
"basically", "in order to", "As you can see", "Let's dive in", "In this section
we will", "feel free to", "powerful", "seamless", "robust".

**Match the register to the document.** A README talks to the reader. A
changelog is a list. An architecture doc can be denser. A PR body is a factual
summary of changes — no personality, no explanation of why the reader should
care. Do not make everything chatty; make everything clear.

## 4. Simple first, technical after

Never mix the plain explanation and the exhaustive detail in one block. Split
them:

1. Two or three sentences in plain words: what it is, why you would use it.
2. A minimal example.
3. Then the table, the edge cases, the full option list, the `<details>` block.

A reader who only needs step 1 can leave after step 1. A reader who needs the
table can find it without reading step 1 twice. Interleaving them costs both
readers.

This is also the rule for reference material: **prose explains, tables
enumerate.** Anything with a repeated shape — options, flags, error codes, exit
codes, fields, comparisons — is a table, not a bulleted list of sentences.

## 5. Structure defaults

- One `#` per document, or none when a centered HTML title block already names it.
  Everything else is `##` / `###`. Do not go past `###`.
- **Sentence case headings.** "Error handling", not "Error Handling".
- **Headings are navigation.** They should read as a list of answers to "how do
  I…" — a skimmer reads only these.
- **Always tag code fences** with a language (`bash`, `typescript`, `json`,
  `markdown`). Untagged fences lose highlighting everywhere.
- **`<details>` for the material only some readers need** — long output,
  benchmark protocol, a migration table. It keeps the page short without
  deleting the information.
- **Link text says where it goes.** `[MIGRATION.md](MIGRATION.md)`, never "click
  here" or a bare URL dropped mid-sentence.
- **Relative links for in-repo files** so they survive forks and tags.
- **Table of contents only past ~6 sections**, and only in a README. GitHub
  already renders an outline button for every Markdown file.
- **Match the file's existing wrap width.** If the file hard-wraps at 80, wrap
  at 80. If it does not, do not introduce it.

## 6. Don't

- Emoji headings, unless the repo already does it consistently.
- More than four or five badges. Version, CI, license, runtime — stop there.
- An "Introduction" or "Overview" heading holding one sentence.
- Restating the docs site in the README. Link to it.
- A "Features" list of adjectives. Each bullet gets a bolded claim and a fact
  that backs it.
- Bold or italics for emphasis inside every other sentence. Emphasis works only
  when it is rare.
- Trailing "hope this helps" / "let me know if you need anything" in a PR or
  issue body.

## README template

`references/readme-template.md` holds a general-purpose skeleton with every
optional block marked. Take the sections that apply and delete the rest — a
short README that covers install, usage, and one real example beats a long one
with empty headings.
