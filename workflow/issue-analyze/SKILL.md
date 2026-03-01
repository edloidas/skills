---
name: issue-analyze
description: >
  Fetches a GitHub issue by number or URL, analyzes its scope of work, cross-references
  local project docs in .claude/, checks blocking relationships, and produces a structured
  implementation analysis with a task list. Use before starting work on any issue to
  understand what needs to be built and plan implementation steps.
license: MIT
compatibility: Claude Code
model: claude-sonnet-4-6
allowed-tools: Bash(gh:*) Bash(git:*) Read Glob Grep
arguments: "issue-number"
argument-hint: "[issue-number or URL]"
metadata:
  author: edloidas
---

# Issue Analyze

Fetches a GitHub issue, analyzes its full scope, cross-references local project docs,
checks blocking relationships, and outputs a structured analysis with an implementation
task list. Standalone — no forced next step.
