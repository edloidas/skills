# Report Format

Two report types: initial (before resolution) and final (after resolution).

## Initial Report

Print before starting conflict resolution. Shows all groups with file lists.

```
## Conflict Analysis Report

PR: <title>
Branches: <base> ← <head>
Link: <url>

### Summary

| Group | Type | Count | Resolution |
|-------|------|-------|------------|
| DU | deleted by theirs | N | `git rm` |
| UD | deleted by ours | N | `git rm` |
| DD | both deleted | N | `git rm` |
| AA | both added | N | Accept theirs / analyze |
| UU | trivial | N | Accept theirs |
| UU | simple | N | Auto-resolve with context |
| UU | complex | N | Deep analysis |
| **Total** | | **N** | |
```

After the summary table, list each non-empty group:

```
### DU — deleted by theirs (N)

Files exist in our branch but were deleted on the target. Safe to remove.

- `path/to/file.ts`
```

```
### UD — deleted by ours (N)

Files were deleted in our branch but modified on the target. Our deletion stands.

- `path/to/file.ts`
```

```
### DD — both deleted (N)

Both branches deleted this file. Safe to remove.

- `path/to/file.ts`
```

```
### AA — both added (N)

Both branches added this file. Accept theirs or analyze if content differs.

- `path/to/file.ts`
```

```
### UU — trivial (N)

Conflicts are only in import statements, whitespace, or one side dominates.

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

- Omit empty groups entirely (don't show "DU — deleted by theirs (0)")
- Groups with >10 files use `<details><summary>N files</summary>` collapsible sections
- Simple and complex UU files always include one-line explanations
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
