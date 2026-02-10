---
name: text-summary
description: Summarize text or URL content. Creates focused summaries that capture essential information without fluff. Fetches URL content automatically.
license: MIT
compatibility: Claude Code
allowed-tools: WebFetch
---

# Text Summarizer

## Purpose

Create focused summaries that capture essential information without fluff or over-explanation. Can fetch and summarize URL content automatically.

## When to Use This Skill

Use when the user asks to:
- Summarize text or article
- Get summary of URL/webpage
- Condense content
- Extract key points

Trigger phrases: "summarize", "summary of", "tl;dr", "key points", "condense", "what does this say"

## Workflow

### For URLs

1. Fetch content using WebFetch or lynx:
   ```bash
   lynx -dump https://example.com
   ```
2. Parse and extract main content
3. Generate summary

### For Text

1. Read provided text
2. Identify core topic and key points
3. Generate summary

## Style

- Direct, technical writing for competent audience
- Clear paragraphs with natural flow
- Technical terms used appropriately, no over-explaining
- **Bold** only for critical concepts
- Minimal formatting - only when it genuinely helps
- No unnecessary headers, bullets, or tables

## Structure

1. **Opening:** Core topic/issue in first paragraph
2. **Body:** Key details, mechanisms, findings
3. **Closing:** Impact or significance (if relevant)

Use headers ONLY for genuinely complex multi-topic content.
Use bullet points ONLY when listing truly distinct items.

## Tone

- Factual and straightforward
- Like explaining to a knowledgeable colleague
- No marketing speak or buzzwords
- No beginner-level explanations
- Focus on what actually matters

## Output

Start immediately with the main point. Write in prose paragraphs. Include only essential information.

Return ONLY the summary. No preamble, no "Here's a summary:" - just the content.

## Examples

**Input:** Long article about React 19 features

**Output:**
React 19 introduces a new compiler that automatically optimizes re-renders, eliminating the need for manual `useMemo` and `useCallback` in most cases. The **Actions** API simplifies form handling by integrating async operations directly into form submissions with built-in pending states.

Server Components are now stable, enabling components that render exclusively on the server with zero JavaScript shipped to the client. The `use` hook provides a unified way to read resources like promises and context during render.

## Keywords

summarize, summary, tl;dr, condense, key points, article, url, webpage, content
