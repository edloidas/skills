# Maintaining the Canonical Configs

Read from `editor-config` when the bundled configs themselves change, not on an ordinary run.

The bundled files in `assets/` are the source of truth. Edit them in place and
commit; the next run in any other repo picks up the new content. Apply targeted edits per
key, never a whole-file rewrite, so the diff carries the key you changed and nothing else.

When adding a brand-new target file:

1. Drop the file into `assets/<editor>/`.
2. Add a row to the **Canonical Set** table in `SKILL.md`.
3. Extend the editor block in `scripts/editor-config.sh` (the `apply_<editor>`
   function and the `TARGETS_<EDITOR>` array).

When adding a brand-new editor:

1. Create `assets/<editor>/` with the relevant files.
2. Add the editor to the script's `KNOWN_EDITORS` list and add an
   `apply_<editor>` function.
3. Add it to the **Canonical Set** table in `SKILL.md` and the `AskUserQuestion` options.
