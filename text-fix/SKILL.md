---
name: text-fix
description: Fix grammar and polish text with minimal edits. Preserves author's voice, tone, and personality while correcting errors.
license: MIT
compatibility: Claude Code, Codex
---

# Text Grammar Fixer

## Purpose

Polish provided text by fixing grammar and improving clarity. Makes minimal edits to fix errors without changing the author's personality or tone.

## When to Use This Skill

Use when the user asks to:
- Fix grammar in text
- Polish or proofread text
- Correct spelling and typos
- Clean up writing

Trigger phrases: "fix grammar", "polish text", "proofread", "correct text", "fix writing", "grammar check"

## Workflow

1. Read the provided text
2. Identify grammar, spelling, and clarity issues
3. Fix ONLY errors (see Fix Only section)
4. Preserve everything in Preserve section
5. Return corrected text only

## Preserve

- Original voice and personality
- Casual/formal level (match input)
- Technical terms and jargon
- Intentional stylistic choices (fragments, ellipses)
- Cultural references and idioms
- Message length and structure

## Fix Only

- Grammar mistakes (tense, subject-verb agreement)
- Spelling errors and typos
- Wrong word choices (their/there, affect/effect)
- Missing or incorrect articles (a/an/the)
- Unclear pronoun references
- Awkward phrasing that obscures meaning

## Examples

| Input | Output |
|-------|--------|
| As I mention before, the API need updated | As I mentioned before, the API needs updating |
| Their's no way to recovered those files | There's no way to recover those files |
| The meeting went good, everyone where on board | The meeting went well, everyone was on board |

## Output

Return ONLY the corrected text. No explanations, no markup, no "Here's the corrected version:" - just the fixed text.

## Important

DO NOT:
- Add fancy vocabulary
- Restructure paragraphs
- Change informal to formal
- Remove personality

The goal is **correction**, not rewriting.

## Keywords

grammar, fix, polish, proofread, spelling, typo, correct, edit, writing
