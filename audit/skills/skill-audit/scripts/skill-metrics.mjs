#!/usr/bin/env node
// Measures skills so the audit can spend its judgment on things a script cannot decide.
//
// Everything here is advisory. Hard structural rules live in the repo validators
// (.github/scripts/validate-skills.sh, scripts/validate-codex.sh) and fail CI; this
// script only reports numbers and suspicious patterns for a human or agent to weigh.
//
// Usage:
//   node skill-metrics.mjs [--root DIR] [--only PATH ...] [--exclude PATH ...] [--json]

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, relative, basename } from 'node:path';

const args = process.argv.slice(2);
let root = process.cwd();
const only = [];
const exclude = [];
let asJson = false;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === '--json') asJson = true;
  else if (arg === '--root') root = args[++i];
  else if (arg === '--only') while (args[i + 1] && !args[i + 1].startsWith('--')) only.push(strip(args[++i]));
  else if (arg === '--exclude') while (args[i + 1] && !args[i + 1].startsWith('--')) exclude.push(strip(args[++i]));
  else {
    process.stderr.write(`Unknown option: ${arg}\nUsage: skill-metrics.mjs [--root DIR] [--only PATH ...] [--exclude PATH ...] [--json]\n`);
    process.exit(1);
  }
}

function strip(p) {
  return p.replace(/^\.\//, '').replace(/\/+$/, '');
}

// ---------------------------------------------------------------- discovery

function walk(dir, depth = 0) {
  if (depth > 3) return [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  const found = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    if (!entry.isDirectory()) continue;
    const full = join(dir, entry.name);
    // Skip build output, but never a plugin group that happens to be named `build`.
    if (['node_modules', 'dist', 'build'].includes(entry.name) && !existsSync(join(full, 'skills'))) continue;
    if (existsSync(join(full, 'SKILL.md'))) found.push(full);
    else found.push(...walk(full, depth + 1));
  }
  return found;
}

let skillDirs = walk(root).map((d) => relative(root, d)).sort();
if (only.length) skillDirs = skillDirs.filter((d) => only.includes(d) || only.includes(basename(d)));
if (exclude.length) skillDirs = skillDirs.filter((d) => !exclude.includes(d) && !exclude.includes(basename(d)));

if (!skillDirs.length) {
  process.stderr.write('No skills matched. Looked for */SKILL.md under ' + root + '\n');
  process.exit(1);
}

// ---------------------------------------------------------------- parsing

// Top-level scalars only. Folded (`>`) and literal (`|`) blocks are joined into one
// line so length caps measure the value the host actually sees.
function parseFrontmatter(text) {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!match) return { fields: {}, body: text };
  const fields = {};
  let key = null;
  for (const raw of match[1].split(/\r?\n/)) {
    const top = raw.match(/^([A-Za-z0-9_-]+):[ \t]*(.*)$/);
    if (top) {
      key = top[1];
      const value = top[2].trim();
      fields[key] = /^[|>][-+]?$/.test(value) || value === '' ? '' : value.replace(/^["']|["']$/g, '');
      continue;
    }
    if (key && /^[ \t]+\S/.test(raw)) {
      const line = raw.trim().replace(/^- /, '');
      fields[key] = fields[key] ? `${fields[key]} ${line}` : line;
    }
  }
  return { fields, body: text.slice(match[0].length), bodyOffset: match[0].split(/\r?\n/).length - 1 };
}

function listFiles(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listFiles(full));
    else out.push(full);
  }
  return out;
}

const STOPWORDS = new Set(
  'a an and are as at be by for from has have in into is it its of on or that the this to use used uses user when with your you skill skills'.split(' '),
);

function tokenize(text) {
  return new Set(
    text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .split(' ')
      .filter((w) => w.length > 2 && !STOPWORDS.has(w)),
  );
}

// Prose duplication needs a wider stop list than discovery overlap does. The question here
// is whether two sentences in one body say the same thing, and the words that carry no
// meaning in a paragraph are not the ones that carry no meaning in a description.
const PROSE_STOPWORDS = new Set(
  (
    'a an and are as at be by for from has have in into is it its of on or that the this to with you your not no do does did ' +
    'if then than when where which what who but so such also only just was were will would can could should must may might ' +
    'there here they them their been being had all any each every some most more less other same over under out up down ' +
    'one two per via etc'
  ).split(' '),
);

function proseTokens(text) {
  return text
    .toLowerCase()
    .replace(/`[^`]*`/g, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .split(' ')
    .filter((w) => w.length > 2 && !PROSE_STOPWORDS.has(w));
}

// Sentences outside fenced blocks and tables, each with the line it starts on. Table rows
// are skipped: a column of three-word cells manufactures pairs that mean nothing.
function sentencesOf(lines, offset) {
  const found = [];
  let fenced = false;
  lines.forEach((line, index) => {
    if (/^\s*(```|~~~)/.test(line)) {
      fenced = !fenced;
      return;
    }
    if (fenced || /^\s*\|/.test(line)) return;
    for (const part of line.split(/(?<=[.!?])\s+/)) {
      const tokens = proseTokens(part);
      if (tokens.length >= 6) found.push({ line: index + 1 + offset, tokens: new Set(tokens), text: part.trim() });
    }
  });
  return found;
}

// Two thresholds on purpose. Strict — 12 or more shared tokens — is the one worth acting
// on: it catches a rule pasted twice. Loose — 5 shared and Jaccard at least 0.28 — surfaces
// paraphrase, where the same rule was rewritten rather than copied. That is the form most
// repetition here actually takes, and it is also the noisier signal, so both are reported
// rather than one of them chosen quietly.
function duplicatePairs(items) {
  const strict = [];
  const loose = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      const shared = [...items[i].tokens].filter((t) => items[j].tokens.has(t));
      if (shared.length < 5) continue;
      const jaccard = shared.length / new Set([...items[i].tokens, ...items[j].tokens]).size;
      const pair = {
        a: items[i].line,
        b: items[j].line,
        shared: shared.length,
        jaccard: Number(jaccard.toFixed(2)),
        textA: items[i].text.slice(0, 100),
        textB: items[j].text.slice(0, 100),
      };
      if (shared.length >= 12) strict.push(pair);
      else if (jaccard >= 0.28) loose.push(pair);
    }
  }
  strict.sort((x, y) => y.shared - x.shared);
  loose.sort((x, y) => y.jaccard - x.jaccard);
  return { strict, loose };
}

// A fenced block counts as a worked example when the four lines above it introduce it as
// one. What makes a block an example is how it is announced, not its fence tag — the same
// ```markdown block is a template in one skill and a filled instance in another.
// Widened after two real examples went uncounted: `handoff`'s heading reads "A complete
// inline handoff" and `markdown-writing` introduces its block with "A section opening,
// before and after:" — neither carries a cue word, and both are filled instances. A
// counter that reads low is worse than no counter, since it invites adding an example
// that is already there.
const EXAMPLE_CUE = /\b(example|worked|sample|output|report|template|looks like|filled|verbatim|complete|instance|concrete|before and after)\b/i;

// The longest stretch the reader crosses without a heading to re-anchor on. Fenced content
// counts, and a shell comment inside a fence is not a heading.
function longestProseRun(lines, offset) {
  let best = 0;
  let bestAt = 1 + offset;
  let current = 0;
  let currentAt = 1 + offset;
  let fenced = false;
  lines.forEach((line, index) => {
    if (/^\s*(```|~~~)/.test(line)) {
      fenced = !fenced;
      current++;
      return;
    }
    if (!fenced && /^#{1,6}\s/.test(line)) {
      if (current > best) {
        best = current;
        bestAt = currentAt;
      }
      current = 0;
      currentAt = index + 2 + offset;
      return;
    }
    current++;
  });
  if (current > best) {
    best = current;
    bestAt = currentAt;
  }
  return { lines: best, line: bestAt };
}

// A dispatch instruction with neither a count nor a named condition is read differently by
// every host: one spawns, another does not. A digit on the line, or an if/when/unless clause
// within two lines, is enough to call it specified.
// The verb is matched in its imperative form only. `dispatches` and `dispatched` are how a
// body talks *about* dispatch — "a skill that dispatches workers should declare Task" is
// prose, not an instruction, and flagging it buries the real sites.
const DISPATCH = /\b(dispatch|spawn|delegate|launch)\b[^.]{0,80}\b(worker|workers|subagent|subagents|reviewer|reviewers|seat|seats|analyzer|analyzers)\b/i;
const DISPATCH_CONDITION = /\b(if|when|unless|whenever)\b/i;

// The inline substitute a skill offers when the host cannot chain to another skill. Long
// ones get taken every time, and they are a second copy of the skill they replace.
const FALLBACK_CUE = /\bif the host (cannot|has no|does not|lacks)\b|\bhost cannot chain\b|\bno facility for\b/i;

// S2: the line a phase prints when it ends. Counted per `##` section so a skill naming one
// line for the whole run is visible as such — that single line becomes the ceiling.
// Two shapes count: a printing verb, and the phrase "one line", which is how most of these
// are actually written ("Close the step with one line: `Scope: 6 skills`"). One of the two
// plus a backticked template is the signal; verb plus phrase counts without one.
const NAMED_OUTPUT_VERB = /\b(print|prints|announce|announces|emit|emits|echo)\b/i;
const NAMED_OUTPUT_SHAPE = /\bone line\b/i;

// Patterns that pin a skill to one host. Legitimate in a Claude-only skill; a smell in
// one that declares Codex, OpenCode, or Pi. Per-host *data* is a valid exception, so
// these are reported with their line for a human call, never auto-failed.
//
// The first four are also hard-failed by .github/scripts/validate-skills.sh, which owns
// the mechanical half: they are not judgement calls, they are steps a declared host
// cannot execute. They stay here so an audit report explains the same finding the
// validator rejects, rather than the two disagreeing.
const HOST_MECHANISM = [
  [/(^|\s)!`[^ `/!][^`]*`/, 'dynamic injection'],
  [/\$\{?CLAUDE_(SESSION_ID|SKILL_DIR|PLUGIN_ROOT)/, 'Claude-only substitution'],
  [/\bToolSearch\b/, 'Claude-only tool'],
  [/subagent_type/, 'subagent_type'],
  [/\bclaude-(opus|sonnet|haiku|fable)[a-z0-9.\-[\]]*/, 'model id'],
  [/\b(Task|Agent|AskUserQuestion|SlashCommand|TodoWrite)\s+tool\b/, 'named Claude tool'],
  [/~\/\.claude\//, 'Claude-only path'],
  [/\bplugin\b[^\n]*\bagents\//, 'plugin agents/ directory'],
];

const CATALOG = join(root, 'scripts/codex/catalog.json');
let catalogSkills = [];
if (existsSync(CATALOG)) {
  try {
    catalogSkills = JSON.parse(readFileSync(CATALOG, 'utf8')).plugins.flatMap((p) => p.skills);
  } catch {
    catalogSkills = [];
  }
}

// ---------------------------------------------------------------- measuring

const skills = skillDirs.map((dir) => {
  const abs = join(root, dir);
  const text = readFileSync(join(abs, 'SKILL.md'), 'utf8');
  const { fields, body, bodyOffset } = parseFrontmatter(text);
  const lines = body.split(/\r?\n/);
  // A body ending in a newline splits to a trailing empty element, which is not a line.
  // Counting it put every skill one line above what validate-skills.sh reports, and that
  // script owns the cap — a measurement that disagrees with the gate is worse than none.
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();

  const description = fields.description ?? '';
  const whenToUse = fields.when_to_use ?? '';
  const hosts = (fields.compatibility ?? '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean);
  const nonClaudeHosts = hosts.filter((h) => ['Codex', 'OpenCode', 'Pi'].includes(h));

  const bundled = ['references', 'scripts', 'assets']
    .flatMap((sub) => listFiles(join(abs, sub)))
    .map((f) => relative(abs, f));

  const referenceText = bundled
    .filter((f) => f.startsWith('references/') && /\.(md|txt)$/.test(f))
    .map((f) => readFileSync(join(abs, f), 'utf8'))
    .join('\n');

  // Reachability, not mention-in-SKILL.md: a reference consumed by a bundled script is
  // still reachable. Only a file nothing in the skill names is dead weight.
  const bundledText = bundled
    .filter((f) => !/\.(png|jpe?g|gif|webp|pdf|zip|woff2?|ttf|ico)$/i.test(f))
    .map((f) => `${f}\n${readFileSync(join(abs, f), 'utf8')}`)
    .join('\n');
  const orphans = bundled.filter((f) => {
    const mentions = (haystack) => haystack.includes(f) || haystack.includes(basename(f));
    if (mentions(text)) return false;
    return !mentions(bundledText.split(`${f}\n`).join('\n'));
  });

  const nestedRefs = bundled
    .filter((f) => f.startsWith('references/') && /\.(md|txt)$/.test(f))
    .filter((f) => /(^|[^A-Za-z0-9._/-])references\/[A-Za-z0-9._/-]+\.\w+/.test(readFileSync(join(abs, f), 'utf8')));

  // Fences and the widest inline block, so "reference material inlined in the body"
  // can be judged against a number instead of a feeling.
  const untaggedFences = [];
  const fenceSpans = [];
  const tableSpans = [];
  let fenceOpen = null;
  let tableStart = null;
  lines.forEach((line, index) => {
    const fence = line.match(/^\s*(```|~~~)(.*)$/);
    if (fence) {
      if (fenceOpen === null) {
        fenceOpen = index;
        if (!fence[2].trim()) untaggedFences.push(index + 1 + bodyOffset);
      } else {
        fenceSpans.push({ line: fenceOpen + 1 + bodyOffset, length: index - fenceOpen + 1 });
        fenceOpen = null;
      }
      return;
    }
    if (fenceOpen !== null) return;
    if (/^\s*\|.*\|\s*$/.test(line)) {
      if (tableStart === null) tableStart = index;
    } else if (tableStart !== null) {
      tableSpans.push({ line: tableStart + 1 + bodyOffset, length: index - tableStart });
      tableStart = null;
    }
  });
  if (tableStart !== null) tableSpans.push({ line: tableStart + 1 + bodyOffset, length: lines.length - tableStart });

  const largestBlock = [...fenceSpans.map((s) => ({ ...s, kind: 'code block' })), ...tableSpans.map((s) => ({ ...s, kind: 'table' }))].sort(
    (a, b) => b.length - a.length,
  )[0];

  const headingSkips = [];
  let previousLevel = 0;
  let headingFenceOpen = false;
  lines.forEach((line, index) => {
    // Shell comments inside a fenced block are not headings.
    if (/^\s*(```|~~~)/.test(line)) {
      headingFenceOpen = !headingFenceOpen;
      return;
    }
    if (headingFenceOpen) return;
    const heading = line.match(/^(#{1,6})\s/);
    if (!heading) return;
    const level = heading[1].length;
    if (previousLevel && level > previousLevel + 1) headingSkips.push(`h${previousLevel}->h${level} at L${index + 1 + bodyOffset}`);
    previousLevel = level;
  });

  const duplicates = duplicatePairs(sentencesOf(lines, bodyOffset));

  const workedExamples = [];
  {
    let fenced = false;
    lines.forEach((line, index) => {
      if (!/^\s*(```|~~~)/.test(line)) return;
      if (fenced) {
        fenced = false;
        return;
      }
      fenced = true;
      // The four non-blank lines above, stopping at the heading — whose own text ("Report
      // Format") is as good an introduction as a sentence.
      const lead = [];
      for (let i = index - 1; i >= 0 && lead.length < 4; i--) {
        if (!lines[i].trim()) continue;
        lead.push(lines[i]);
        if (/^#{1,6}\s/.test(lines[i])) break;
      }
      if (EXAMPLE_CUE.test(lead.join(' '))) workedExamples.push(index + 1 + bodyOffset);
    });
  }

  const proseRun = longestProseRun(lines, bodyOffset);

  // Dispatch is scanned in the reference files too: a dispatched prompt is where an
  // unspecified threshold does the most damage, because nothing downstream re-reads it.
  const proseFiles = [['SKILL.md', lines, bodyOffset], ...bundled.filter((f) => /\.(md|txt)$/.test(f)).map((f) => [f, readFileSync(join(abs, f), 'utf8').split(/\r?\n/), 0])];

  const unquantifiedDispatch = [];
  for (const [file, fileLines, offset] of proseFiles) {
    fileLines.forEach((line, index) => {
      if (!DISPATCH.test(line)) return;
      const window = fileLines.slice(index, index + 3).join(' ');
      if (/\d/.test(window) || DISPATCH_CONDITION.test(window)) return;
      unquantifiedDispatch.push({ file, line: index + 1 + offset, text: line.trim().slice(0, 110) });
    });
  }

  // The block runs to the next heading. A blank line ends it, unless what follows opens a
  // fence, a list item, or an indented continuation — those are still part of the fallback.
  const inlineFallbacks = [];
  lines.forEach((line, index) => {
    if (!FALLBACK_CUE.test(line)) return;
    let end = index;
    for (let i = index + 1; i < lines.length; i++) {
      if (/^#{1,6}\s/.test(lines[i])) break;
      if (!lines[i].trim()) {
        const next = lines[i + 1] ?? '';
        if (!/^\s*(```|~~~|[-*+]\s|\d+\.\s|\s)/.test(next) || !next.trim()) break;
        continue;
      }
      end = i;
    }
    inlineFallbacks.push({ line: index + 1 + bodyOffset, length: end - index + 1 });
  });

  const namedOutputs = [];
  {
    let section = '(preamble)';
    let count = 0;
    let fenced = false;
    const flush = () => namedOutputs.push({ section, count });
    lines.forEach((line) => {
      if (/^\s*(```|~~~)/.test(line)) {
        fenced = !fenced;
        return;
      }
      if (fenced) return;
      const heading = line.match(/^##\s+(.*)$/);
      if (heading) {
        flush();
        section = heading[1].trim();
        count = 0;
        return;
      }
      const templated = /`[^`]+`/.test(line);
      const verb = NAMED_OUTPUT_VERB.test(line);
      const shape = NAMED_OUTPUT_SHAPE.test(line);
      if ((verb && (templated || shape)) || (shape && templated)) count++;
    });
    flush();
  }

  const hostMechanismHits = [];
  if (nonClaudeHosts.length) {
    const scanned = [['SKILL.md', text], ...bundled.filter((f) => /\.(md|txt)$/.test(f)).map((f) => [f, readFileSync(join(abs, f), 'utf8')])];
    for (const [file, content] of scanned) {
      content.split(/\r?\n/).forEach((line, index) => {
        for (const [pattern, label] of HOST_MECHANISM) {
          if (pattern.test(line)) hostMechanismHits.push({ file, line: index + 1, label, text: line.trim().slice(0, 120) });
        }
      });
    }
  }

  const allText = text + referenceText;
  const askUserQuestion = allText.includes('AskUserQuestion');
  // The repo carries one canonical `Asking the User` section, worded identically in every
  // skill that asks. Detecting that exact shape is what makes the metric useful: the old
  // keyword sniff passed on fourteen different paraphrases of the same rule.
  const canonicalAsk =
    /^#{2,3} Asking the User$/m.test(text) &&
    /nearest structured-choice equivalent/.test(text) &&
    /numbered list of 2–5 options/.test(text);
  const fallback =
    canonicalAsk || /fallback|numbered list|plain chat|normal chat|if .{0,40}unavailable/i.test(allText);

  return {
    path: dir,
    name: fields.name ?? '',
    hosts,
    nonClaudeHosts,
    discovery: {
      descriptionChars: description.length,
      whenToUseChars: whenToUse.length,
      totalChars: whenToUse ? description.length + whenToUse.length + 1 : description.length,
      hasWhenToUse: Boolean(whenToUse),
    },
    body: {
      lines: lines.length,
      chars: body.length,
      tokenEstimate: Math.round(body.length / 4),
      largestBlock: largestBlock ?? null,
      longestProseRun: proseRun,
    },
    duplicates,
    workedExamples,
    unquantifiedDispatch,
    inlineFallbacks,
    namedOutputs,
    bundled,
    orphans,
    nestedRefs,
    untaggedFences,
    headingSkips,
    hostMechanismHits,
    askUserQuestion: {
      used: askUserQuestion,
      fallbackRequired: askUserQuestion && nonClaudeHosts.length > 0,
      fallbackMentioned: askUserQuestion && fallback,
      canonicalSection: askUserQuestion && canonicalAsk,
    },
    codex: {
      compatibilityIncludesCodex: hosts.includes('Codex'),
      hasOpenaiYaml: existsSync(join(abs, 'agents/openai.yaml')),
      inCatalog: catalogSkills.includes(dir),
    },
    tokens: tokenize(`${description} ${whenToUse}`),
  };
});

// Two skills whose discovery text reads the same will fight over the same trigger, and
// the loser is never invoked. Jaccard over the discovery entry is a cheap proxy.
const overlaps = [];
for (let i = 0; i < skills.length; i++) {
  for (let j = i + 1; j < skills.length; j++) {
    const a = skills[i].tokens;
    const b = skills[j].tokens;
    const shared = [...a].filter((t) => b.has(t));
    const union = new Set([...a, ...b]).size;
    if (!union) continue;
    const score = shared.length / union;
    overlaps.push({ a: skills[i].path, b: skills[j].path, score: Number(score.toFixed(2)), shared: shared.slice(0, 8) });
  }
}
overlaps.sort((x, y) => y.score - x.score);

for (const skill of skills) delete skill.tokens;

// ---------------------------------------------------------------- output

if (asJson) {
  process.stdout.write(`${JSON.stringify({ root, skills, overlaps }, null, 2)}\n`);
  process.exit(0);
}

const none = '(none)';

function describeAsk(ask) {
  if (!ask.used) return 'not mentioned';
  if (!ask.fallbackRequired) return 'mentioned (host set needs no plain-chat fallback)';
  if (ask.canonicalSection) return 'mentioned, canonical `Asking the User` section present';
  if (ask.fallbackMentioned) return 'mentioned, ad-hoc fallback wording (not the canonical section)';
  return 'mentioned, NO fallback wording found';
}
const out = [];
for (const s of skills) {
  const d = s.discovery;
  out.push(`## ${s.path}`);
  out.push(`name: ${s.name || '(missing)'} | hosts: ${s.hosts.length ? s.hosts.join(', ') : '(unset - universal)'}`);
  out.push(
    `discovery: description ${d.descriptionChars} chars, when_to_use ${d.hasWhenToUse ? `${d.whenToUseChars} chars` : 'absent'}, entry ${d.totalChars}/1536`,
  );
  out.push(
    `body: ${s.body.lines} lines, ~${s.body.tokenEstimate} tokens${s.body.largestBlock ? `, largest inline ${s.body.largestBlock.kind} ${s.body.largestBlock.length} lines at L${s.body.largestBlock.line}` : ''}`,
  );
  out.push(
    `duplicate sentence pairs: ${s.duplicates.strict.length} strict (>=12 shared tokens), ${s.duplicates.loose.length} loose (paraphrase)`,
  );
  for (const p of s.duplicates.strict.slice(0, 3)) out.push(`  L${p.a} <-> L${p.b} (${p.shared} tok, j=${p.jaccard})`);
  for (const p of s.duplicates.loose.slice(0, 3)) out.push(`  L${p.a} <-> L${p.b} (${p.shared} tok, j=${p.jaccard}) loose`);
  out.push(`worked-output example blocks: ${s.workedExamples.length ? s.workedExamples.map((l) => `L${l}`).join(', ') : none}`);
  out.push(`longest prose run without a heading: ${s.body.longestProseRun.lines} lines from L${s.body.longestProseRun.line}`);
  out.push(`dispatch lines with no count and no condition: ${s.unquantifiedDispatch.length ? '' : none}`);
  for (const d of s.unquantifiedDispatch) out.push(`  ${d.file}:${d.line} ${d.text}`);
  out.push(
    `inline chained-skill fallbacks: ${s.inlineFallbacks.length ? s.inlineFallbacks.map((f) => `L${f.line} ${f.length} lines`).join(', ') : none}`,
  );
  const namedTotal = s.namedOutputs.reduce((sum, n) => sum + n.count, 0);
  const silent = s.namedOutputs.filter((n) => !n.count).map((n) => n.section);
  out.push(
    `named-output lines: ${namedTotal} total${s.namedOutputs.filter((n) => n.count).length ? ` (${s.namedOutputs.filter((n) => n.count).map((n) => `${n.section} ${n.count}`).join('; ')})` : ''}` +
      `${silent.length ? ` | no named line in: ${silent.slice(0, 6).join(', ')}${silent.length > 6 ? ` +${silent.length - 6} more` : ''}` : ''}`,
  );
  out.push(`bundled: ${s.bundled.length ? s.bundled.join(', ') : none}`);
  out.push(`unreachable bundled files: ${s.orphans.length ? s.orphans.join(', ') : none}`);
  out.push(`references pointing at other references: ${s.nestedRefs.length ? s.nestedRefs.join(', ') : none}`);
  out.push(`untagged code fences: ${s.untaggedFences.length ? s.untaggedFences.map((l) => `L${l}`).join(', ') : none}`);
  out.push(`heading level skips: ${s.headingSkips.length ? s.headingSkips.join(', ') : none}`);
  out.push(`AskUserQuestion: ${describeAsk(s.askUserQuestion)}`);
  out.push(
    `codex surface: compatibility=${s.codex.compatibilityIncludesCodex ? 'yes' : 'no'} openai.yaml=${s.codex.hasOpenaiYaml ? 'yes' : 'no'} catalog=${s.codex.inCatalog ? 'yes' : 'no'}`,
  );
  if (s.nonClaudeHosts.length) {
    out.push(
      `host-mechanism hits (declares ${s.nonClaudeHosts.join(', ')}): ${
        s.hostMechanismHits.length ? '' : none
      }`,
    );
    for (const hit of s.hostMechanismHits) out.push(`  ${hit.file}:${hit.line} [${hit.label}] ${hit.text}`);
  }
  out.push('');
}

out.push('## closest discovery neighbours (Jaccard over description + when_to_use)');
if (!overlaps.length) out.push(none);
for (const o of overlaps.slice(0, 10)) {
  out.push(`${o.score}${o.score >= 0.2 ? ' *' : '  '}  ${o.a}  vs  ${o.b}  [${o.shared.join(' ')}]`);
}
if (overlaps.length) out.push('* = worth checking whether both descriptions can win their own triggers.');

process.stdout.write(`${out.join('\n')}\n`);
