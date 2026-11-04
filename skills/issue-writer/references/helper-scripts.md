## Bundled Helper Scripts Details

Both scripts are run, not read: call them from the skill directory, `<skill-dir>/scripts/`.
Both need `gh`, authenticated, inside a git repository, and accept an issue as `123`, `#123`,
`owner/repo#123`, or a full issue URL. A bare number means the current repository; the other
two forms act on the repository they name. Anything else is refused before `gh` runs.

### scripts/get-issue.sh

Prints the issue as JSON: `number`, `title`, `body`, `labels`, `state`, `url`.

```bash
bash "<skill-dir>/scripts/get-issue.sh" 123
bash "<skill-dir>/scripts/get-issue.sh" https://github.com/owner/repo/issues/123
```

### scripts/update-issue.sh

Edits title, body, and labels, and uploads attachments, in one `gh issue edit` call. At least
one change is required, and a flag given without a value is refused.

| Flag | Effect |
| ---- | ------ |
| `--title "<title>"` | Replaces the title |
| `--body-file <path>` | Replaces the body with the file's contents — the form `SKILL.md` uses |
| `--body "<text>"` | Same, from an argument; the shell expands backticks and `$` in it |
| `--add-label <label>` / `--remove-label <label>` | Repeatable |
| `--attach "<path>#<alt text>"` | Uploads a local file and rewrites the body's reference to it; repeatable; needs `gh` 2.99.0 or newer, not on GitHub Enterprise Server |

An `--attach` or `--body-file` path that is not on disk is refused before anything is edited. When some
uploads fail, the edit still lands with the ones that succeeded and the script exits with
`gh`'s non-zero status, printing which way a retry is safe.

```bash
bash "<skill-dir>/scripts/update-issue.sh" --issue 123 --title "fix: keep the tooltip inside the viewport edge"
bash "<skill-dir>/scripts/update-issue.sh" --issue 123 --body-file /tmp/tmp.AbCdEf/body.md --attach ".tmp/screenshots/clipped.png#the clipped tooltip"
bash "<skill-dir>/scripts/update-issue.sh" --issue 123 --add-label bug --remove-label feature
```
