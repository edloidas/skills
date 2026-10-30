---
name: markdown-writing
description: >
  Write Markdown people actually read: READMEs, docs, PR and issue bodies, release notes,
  changelogs, with GitHub-flavored extras and prose that leads with the point.
when_to_use: >
  "write a README", "draft the PR description", "write release notes", "update the changelog",
  "tighten this doc". Also whenever drafting or editing a .md file, a PR description, or an
  issue comment.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
argument-hint: "[file or topic]"
metadata:
  author: edloidas
  tier: auto
---

# Markdown Writing

Two things decide whether Markdown is good: **where it renders** (which syntax
you may use) and **how it reads** (whether anyone finishes it). Handle them in
that order.

This skill writes and edits Markdown files in the working tree, and nothing else — no
commits. Edit an existing document with targeted edits to the passages you are changing;
never rewrite the whole file. A whole-file rewrite restyles wrap width, emphasis, and
heading case that nobody asked to change, and buries the real edit in the diff.

## 1. Check the render target first

| Renders where | What you may use |
| --- | --- |
| GitHub only — issues, PRs, comments, discussions, wiki, repo file views | Everything, including alerts, `<details>`, task lists, footnotes, mermaid, theme-aware images |
| README that also ships to npm, PyPI, a docs site, or an editor preview | CommonMark + tables + `<details>`. GitHub extras are degradable, not free: every alert body must read correctly with its `[!IMPORTANT]` line showing as literal text |
| Terminal, `--help` output, plain-text logs | No Markdown. Write plain text |

Full syntax and per-host support: `references/github-features.md`.

## 2. GitHub alerts

Five types, exact spelling, uppercase, nothing on the label line — the syntax block is in
`references/github-features.md`.

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
- **One at a time.** Two alerts in a row read as noise.

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

Text that leaves the session — a PR body, a README, an issue — reads as generated
when it reaches for stock words. Write "use", "show", "stress" where the draft says
"delve", "showcase", "underscore"; write "is" where it says "serves as"; state the
claim plainly instead of framing it as "not just X but Y"; and call one thing by
one name throughout, because a reader takes a new word for a new thing.

A section opening, before and after:

````markdown
<!-- before -->
## Configuration
In this section we will look at how configuration works. The library is
designed to be flexible and provides a powerful configuration system that
can be adapted to a wide range of use cases.

<!-- after -->
## Configuration
Configuration is one file, `roll.config.json`, read from the working directory:

```json
{ "seed": 42, "sides": 20 }
```

Every field is optional. Without the file, rolls are unseeded and 6-sided.
````

**Match the register to the document.** A README talks to the reader. A
changelog is a list. An architecture doc can be denser. A PR body is a factual
summary of changes — no personality, no explanation of why the reader should
care. Do not make everything chatty; make everything clear.

## 4. One reading per sentence

A sentence that parses two ways gets parsed the wrong way by some reader. Each
habit below removes one second reading:

- **Put "only" next to the word it limits.** "The flag applies only to new
  users", not "The flag only applies to new users".
- **Say what a noun stack is.** "user session token refresh handler" is four
  guesses; "the handler that refreshes a user's session token" is one.
- **Give every "it", "this", and "that" one referent.** When two nouns came
  before it, repeat the noun.
- **Write "or" or "and" between alternatives.** "a file, a directory, or both",
  not "a file and/or directory".
- **Write full sentences.** "Parser rejects bad date → exit 2" becomes "When the
  parser rejects a date, the command exits with code 2."

````markdown
<!-- before -->
Only enable it for the cache/queue client → retries on timeout. This keeps the
request latency budget intact.

<!-- after -->
Enable `retryOnTimeout` only for the cache client and the queue client. When
either one times out, that client retries the call instead of failing the
request, so a slow dependency does not use up the request's latency budget.
````

## 5. Simple first, technical after

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

**One document, one mode.** A tutorial walks one path and links to the reference
for the option tables. A reference lists and looks up; it does not narrate. A
document that tries to be both makes each reader wade through the other's half.

## 6. Structure defaults

- One `#` per document, or none when a centered HTML title block already names it.
  Everything else is `##` / `###`. Do not go past `###`.
- **Sentence case headings.** "Error handling", not "Error Handling".
- **Headings are navigation.** They should read as a list of answers to "how do
  I…" — a skimmer reads only these.
- **Tag every code fence** with a language (`bash`, `typescript`, `json`,
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

## 7. Don't

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
