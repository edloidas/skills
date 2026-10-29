# Report Format

Two report types: initial (before resolution) and final (after resolution).

## Initial Report

Print before starting conflict resolution. Shows all groups with file lists.

```
## Conflict Analysis Report

PR: <title>
Branches: <base> ← <head_repo>:<head>
Link: <url>

### Summary

| Group | Type | Count | Resolution |
|-------|------|-------|------------|
| DU | deleted by ours, changed by theirs | N | `git rm` if trivial, else user decides |
| UD | changed by ours, deleted by theirs | N | `git rm` if trivial, else user decides |
| DD | both deleted | N | `git rm` |
| AA | both added | N | Classified with UU |
| AU / UA | added by one side | N | Accept the side that added it |
| UU | trivial | N | Resolve the conflict blocks toward the dominant side |
| UU | simple | N | Auto-resolve with context |
| UU | complex | N | Deep analysis |
| **Total** | | **N** | |
```

After the summary table, list each non-empty group:

```
### DU — deleted by ours, changed by theirs (N)

Our side deleted these files and their side changed them. Whitespace-only changes are removed with
the deletion; substantive ones wait for your decision.

- `path/to/file.ts` — trivial
- `path/to/other.ts` — substantive: <shortstat>; <git log --left-right one-liners>
```

```
### UD — changed by ours, deleted by theirs (N)

Our side changed these files and their side deleted them. Same rule as DU.

- `path/to/file.ts` — substantive: <shortstat>; <git log --left-right one-liners>
```

```
### DD — both deleted (N)

Both branches deleted this file. Safe to remove.

- `path/to/file.ts`
```

```
### AA — both added (N)

Both branches added this file. Classified with the UU files; a trivial one resolves its conflict blocks toward the side the classifier names.

- `path/to/file.ts`
```

```
### UU — trivial (N)

Every conflict block favors one side; only those blocks take it, and the cleanly merged hunks stay.

- `path/to/file.ts`
```

```
### UU — simple (N)

Both sides changed the file, but in different regions or with clear intent.

- `file.ts` — brief explanation of what each side changed
```

```
### UU — complex (N)

Overlapping changes requiring deeper analysis.

- `file.ts` — brief explanation of why this is complex
```

## Rules

- Omit empty groups entirely (don't show "DD — both deleted (0)")
- Groups with >10 files use `<details><summary>N files</summary>` collapsible sections
- Simple and complex UU files carry a one-line explanation each; DU and UD files carry their
  rating, and a substantive one its shortstat and commits
- PR context header (PR/Branches/Link) is only shown in PR mode. Omit in local/conditional mode.

## Final Report

### All resolved

```
Resolved N/N conflicts automatically.
```

### Some remaining

```
Resolved X/N conflicts automatically. Y remaining need review.
```

Followed by the initial report structure but showing ONLY unresolved files. The summary table shows only unresolved groups. Group descriptions remain the same.

Both end with one line naming the checks Verification ran and their result — `Checks: <command> — <pass | N errors in <files>>` — or `Checks: not run — <reason>`.
