# Evaluation Rubric

Detailed criteria and scoring anchors for skill audits. Each category lists specific checks and what score each level maps to.

## 1. Specification Compliance

Objective checks against the Agent Skills specification.

**Checks:**
- [ ] `name` field present in frontmatter
- [ ] `description` field present in frontmatter
- [ ] `name` matches directory name exactly
- [ ] `name` format: 1-64 chars, lowercase `a-z`, `0-9`, `-` only, no leading/trailing/consecutive hyphens
- [ ] `description` is 1-1024 characters
- [ ] Description includes at least one trigger phrase or use-case (e.g., "when user asks...", "use if...")
- [ ] Description avoids overly generic phrasing (e.g., "helps with X" without specifics)
- [ ] Optional fields (`license`, `compatibility`, `metadata`, `allowed-tools`) correctly formatted when present
- [ ] Body is under 500 lines
- [ ] Token estimate under ~5000 (heuristic: character count / 4)

**Claude Code extension fields:** The following frontmatter fields are valid Claude Code extensions and must NOT be flagged as non-standard or unknown: `model`, `user-invocable`, `context`, `agent`, `argument-hint`, `disable-model-invocation`, `hooks`, `arguments`. Note that `user-invocable` defaults to `true` — its absence is not a gap and should not be penalized.

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | All checks pass. Description is specific and actionable. |
| 4 | All required fields valid. One minor optional field issue (e.g., missing `license`). |
| 3 | Required fields present but description is vague or body slightly over 500 lines. |
| 2 | Name mismatch, or description missing trigger phrases entirely. |
| 1 | Missing required fields (`name` or `description`) or invalid `name` format. |

## 2. Instruction Quality

How clear, structured, and actionable the instructions are.

**Checks:**
- [ ] Has clear sections with headings (##, ###)
- [ ] Uses numbered or bulleted lists for multi-step workflows
- [ ] Includes at least one example (input/output pair or code block)
- [ ] Documents at least 2 edge cases or failure modes (where applicable)
- [ ] Prefers positive instructions ("do X") over negative ("don't do Y")
- [ ] Output format explicitly specified when skill produces structured output
- [ ] No conflicting or contradictory instructions
- [ ] Has a "When to Use" section or trigger phrases
- [ ] Steps are ordered logically (gather context before analysis, analysis before report)

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | Well-structured with headings, examples, edge cases, and clear output format. Could serve as a template. |
| 4 | Good structure and examples. Minor gaps (e.g., one edge case could be documented). |
| 3 | Has structure but missing examples OR edge cases. Instructions are followable but could be clearer. |
| 2 | Flat wall of text, or steps are unclear/out of order. Missing both examples and edge cases. |
| 1 | Instructions are contradictory, incomprehensible, or effectively absent. |

## 3. Tool & Integration Design

How well the skill declares and uses tools, models, and integrations.

**Checks:**
- [ ] `allowed-tools` declarations match actual tool usage in instructions
- [ ] `allowed-tools` aren't overly permissive (e.g., bare `Bash` when `Bash(git:*)` would suffice)
- [ ] `model` override (if present) is justified — not using expensive model for simple tasks
- [ ] Task tool (subagents) used where parallel independent work would genuinely benefit
- [ ] Scripts (if any) are well-integrated into the workflow, not orphaned
- [ ] `user-invocable` field present when skill is meant to be invoked by user
- [ ] `arguments` field present when skill accepts user input
- [ ] No tools declared but unused, no tools used but undeclared

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | Tools precisely scoped, model justified, scripts integrated, invocation fields correct. |
| 4 | Tools mostly correct. One minor over-permission or missing `user-invocable`. |
| 3 | Some tool mismatch (declared but unused, or used but undeclared). Or overly permissive `Bash`. |
| 2 | Significant tool mismatches. Scripts exist but aren't referenced in workflow. |
| 1 | No `allowed-tools` despite using tools, or tools are dangerously over-permissive. |

## 4. Context Efficiency

How well the skill manages token budget and progressive disclosure.

**Checks:**
- [ ] Description is compact enough for discovery phase (~100 tokens, roughly 400 chars)
- [ ] SKILL.md body stays focused on instructions (not bloated with reference material)
- [ ] Heavy content (lookup tables, mappings, templates >50 lines) lives in `references/`
- [ ] Reference files (if any) are focused and single-purpose
- [ ] No deeply nested reference chains (reference pointing to another reference)
- [ ] Token budget well-managed (body estimated under ~5000 tokens)
- [ ] No duplicated content between SKILL.md and reference files

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | Lean body, heavy content in references, description under ~100 tokens. Exemplary progressive disclosure. |
| 4 | Good balance. Minor inefficiency (e.g., one table could move to references). |
| 3 | Body somewhat bloated but under token limit. Or no references when content could benefit from splitting. |
| 2 | Body significantly over recommended size. Large tables/templates inline that should be in references. |
| 1 | Body exceeds 5000 token estimate. Or massive inline content making the skill slow to load. |

## 5. Safety & Robustness

How well the skill handles mutations, errors, and dependencies.

**Checks:**
- [ ] User approval gates before mutations (file edits, git push, API calls, creating issues/PRs)
- [ ] Error handling documented in scripts (exit codes, error messages)
- [ ] External dependencies explicitly documented (tools: `gh`, `jq`, `fd`, `pdftotext`, etc.)
- [ ] No undeclared dependencies in scripts
- [ ] `allowed-tools` not overly permissive for the task scope
- [ ] Sensitive operations have safeguards (confirmation prompts, dry-run options)
- [ ] Scripts validate inputs before acting
- [ ] Destructive operations (delete, overwrite, force-push) are gated or warned about

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | All mutations gated, dependencies documented, scripts have error handling, tools minimally scoped. |
| 4 | Good safety practices. One minor gap (e.g., a script missing error handling for edge case). |
| 3 | Some mutations ungated, or dependencies partially documented. No critical safety issues. |
| 2 | Mutations proceed without user approval, or undeclared dependencies in scripts. |
| 1 | Destructive operations without safeguards. Could cause data loss or unintended side effects. |

**Note for read-only skills:** Skills that only read and analyze (no mutations) should score 4-5 here by default, as the risk surface is minimal. Deduct only for undeclared dependencies or overly permissive tools.

## 6. Formatting & Syntax

Correctness and consistency of YAML, Markdown, and code formatting.

**Checks:**
- [ ] Valid YAML frontmatter (parseable, no syntax errors)
- [ ] Consistent markdown formatting (heading hierarchy: h1 > h2 > h3, no skipped levels)
- [ ] Code blocks use language tags (` ```bash `, ` ```yaml `, ` ```json `, etc.)
- [ ] No improperly mixed HTML tags and markdown
- [ ] Tables properly formatted (aligned pipes, header separators)
- [ ] No broken references to non-existent files in the skill directory
- [ ] Consistent list style (all `-` or all `*`, not mixed)
- [ ] No trailing whitespace issues that affect rendering
- [ ] Frontmatter field values properly quoted when needed (strings with special chars)

**Scoring anchors:**
| Score | Criteria |
|-------|----------|
| 5 | Clean formatting throughout. Valid YAML, consistent markdown, all code blocks tagged. |
| 4 | Minor formatting issues (e.g., one code block missing language tag). |
| 3 | Several formatting inconsistencies but nothing that breaks rendering. |
| 2 | YAML issues that could cause parse failures, or broken file references. |
| 1 | Frontmatter is invalid YAML, or formatting severely impacts readability. |

## General Scoring Guidelines

- **Be specific**: Every score must cite line numbers, quotes, or file paths as evidence.
- **Be fair**: Read-only skills without scripts naturally have less to evaluate in Safety — don't penalize for absence of risk surface.
- **Be consistent**: Apply the same standards across all skills. A 4 for one skill should mean the same quality bar as a 4 for another.
- **Prioritize impact**: Issues that affect the user's experience or the skill's correctness matter more than cosmetic concerns.
- **Context matters**: A skill's complexity should be proportional to its task. A simple text-fixing skill doesn't need subagents.
