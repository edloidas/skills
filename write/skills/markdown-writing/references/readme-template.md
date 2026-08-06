# README skeleton

A general-purpose shape. **Every section below is optional except Usage.** Take
what applies, delete the rest. A README covering install, one real example, and
a link to the docs beats a long one with hollow headings.

Order matters more than completeness: a reader decides in the first screen
whether to keep going, so the first screen is *what it is* and *what using it
looks like* — never a badge wall over an "Introduction" that restates the title.

---

## The first screen

Optional centered block. Skip the logo and badges entirely for an internal repo
or an app.

```markdown
<p align="center">
  <a href="https://example.com"><img src="https://raw.githubusercontent.com/OWNER/REPO/main/.github/logo.svg" width="92" alt="NAME logo"></a>
</p>

<h1 align="center">Name</h1>

<p align="center">
One sentence. What it is and who it is for, no adjectives.
</p>

<p align="center">
  <a href="..."><img src="https://img.shields.io/npm/v/PKG" alt="npm version"></a>
  <a href="..."><img src="https://img.shields.io/github/actions/workflow/status/OWNER/REPO/ci.yml?branch=main&label=CI" alt="CI status"></a>
  <a href="..."><img src="https://img.shields.io/npm/l/PKG" alt="MIT license"></a>
</p>

<p align="center">
  <a href="..."><strong>Docs</strong></a> ·
  <a href="..."><strong>Playground</strong></a>
</p>
```

Four badges maximum: version, CI, license, runtime floor. A plain `# Name`
followed by the one-sentence description is a perfectly good alternative.

## Usage — the only required section

Two or three examples, immediately, before any prose. Each one gets a
half-sentence lead-in and real values in trailing comments.

````markdown
Do the common thing:

```typescript
import { thing } from 'pkg';

const result = thing('input');
result.value; // 14
```

Do the second most common thing:

```typescript
const detailed = thing('input', { verbose: true });
detailed.parts.length; // 3
```
````

If the tool is a CLI, this is the command and its output. If it is a service,
this is the request and the response.

## Why <name>

Optional. Only worth writing when the reader has alternatives to choose from.
Each bullet is a **bolded claim** followed by the fact that backs it — a number,
a guarantee, a link to the comparison. Never a list of adjectives.

```markdown
- **Deterministic.** Every draw goes through an injectable RNG. Seed it to
  reproduce a run, or script the sequence and assert exact values.
- **Small.** 11.9 kB brotli for the whole library, zero runtime dependencies.
```

## Contents

Optional, and only past ~6 sections. GitHub renders an outline button already.

## Install

````markdown
## Install

```bash
npm install pkg
```

> [!IMPORTANT]
> Node.js ≥ 22.12 and ESM only.
````

Requirements go in an alert or a single sentence right here — not in a separate
"Requirements" section that the reader hits after already failing.

## Configuration / Options / API

One table. Option, default, effect. Prose only for the two or three options that
need a caveat, and that prose goes *after* the table.

```markdown
| Option | Default | Effect |
| ------ | ------- | ------ |
| `seed` | random | Reproducible output |
| `maxDepth` | `128` | Rejects deeper input with `MAX_DEPTH_EXCEEDED` |
```

## Error handling

Only when the reader has to branch on failures. Show the catch block, then the
code table.

## Known limitations

Optional, and disproportionately valuable. Each bullet is a **bolded statement
of the behavior** and one or two sentences on why it is that way and what to do
instead. This is the section that stops issues from being filed.

## Performance

Only with measured numbers. Table of cases, and the methodology inside a
`<details>` block so it does not interrupt anyone.

## Versioning

Only when the answer is not "plain semver" — open unions, stability of
generated output, supported runtime floors.

## Contributing

Two sentences and a link to `CONTRIBUTING.md`. Do not inline the whole
contributor workflow.

## License

```markdown
[MIT](LICENSE) © [Name](https://example.com)
```

---

## Sections that are usually a mistake

- **Introduction / Overview** holding one sentence — that sentence belongs under
  the title.
- **Features** as a list of adjectives with no facts.
- **Roadmap** — it goes stale. Use issues or a project board.
- **Screenshots** with no context — say what the reader is looking at.
- **FAQ** that duplicates sections already in the file.
- **Table of contents** for a five-section README.
