# Intent Sources

Recipes for when the plain history lookup in **Dig Up The Why** dead-ends. Each row is a situation,
the command that gets past it, and what to read in the result. Commands are read-only.

## Finding the commit that introduced the line

| Situation | Command | Read |
| --- | --- | --- |
| The exact text is known | `git log -S '<text>' --oneline -- <file>` | The oldest hit added it; a later hit removed or moved it |
| Only a pattern is known, or the text changed shape | `git log -G '<regex>' --oneline -- <file>` | Every commit whose diff touches a matching line |
| The file was renamed or moved | `git log --follow --oneline -- <file>` | History before the rename, which plain `git log` cuts off |
| A whole function is the subject | `git log -L :<function>:<file>` | Every change to that function, with its diff |
| Blame lands on a reformat or a mass rename | `git blame -w -C -C -L <a>,<b> <file>`, or `git blame <sha>^ -L <a>,<b> -- <file>` to step past that commit | `-w` ignores whitespace, `-C -C` follows lines copied from other files |
| The repo lists reformat commits | `git blame --ignore-revs-file .git-blame-ignore-revs -L <a>,<b> <file>` | Blame with those commits skipped |
| What else changed with it | `git show --stat <sha>` | Tests and config added in the same commit often name the case that forced it |

## Getting from a commit to its discussion

| Situation | Command | Read |
| --- | --- | --- |
| Squash merge, `(#123)` in the subject | `gh pr view 123 --comments` | The description, then review threads — the reason is often in a reply, not the description |
| No PR number in the message | `gh pr list --state merged --search <sha>` or `gh api repos/{owner}/{repo}/commits/<sha>/pulls` | The PR that carried the commit |
| The PR closes or links issues | `gh pr view <n> --json closingIssuesReferences,body` then `gh issue view <m> --comments` | The issue states the problem; the PR states the chosen fix |
| The commit was reverted or followed by a fix | `git log --oneline <sha>..HEAD -- <file>` | A revert or a follow-up changes what the original reason is worth |

## Docs in the repo

- ADRs and design docs: look under `docs/adr/`, `docs/decisions/`, `adr/`, `doc/architecture/`, or
  search the Markdown for "decision", "rationale", "we chose".
- Comments next to the line, and `TODO`, `FIXME`, `HACK` notes in the same file.
- `CHANGELOG.md` and release notes for the version that introduced the commit
  (`git tag --contains <sha> | head -1`).

## Reading what comes back

- A commit subject saying "fix" or "improve" names what the author meant to do, not that it worked.
  It supports an inferred claim about the goal, not a direct claim about the result.
- The author's framing and the reporter's framing can both be true: the issue gives the trigger, the
  PR the approach. Cite each for what it says.
- A pattern repeated across the codebase may be copy-paste rather than a decision. Consistency alone
  is not a reason.
- When every source is silent, the person who wrote the commit is the remaining source. Name them
  from `git log --format='%an %ad' -1 <sha>` so the user knows whom to ask.
