# Application Code Security

**Frontend (React/TSX, Svelte)**

- HTML injection — `dangerouslySetInnerHTML` / `{@html}` (identify source, check
  sanitization), direct `innerHTML` / `outerHTML` assignment, template literals assigned to
  innerHTML-like properties
- Unsafe execution — `eval()`, `new Function()`, `Function()` with non-literal arguments;
  `document.write()` / `document.writeln()`
- URL injection — `href` / `src` / `action` set from variables without a `javascript:`
  protocol guard; `window.location.href = ` or `.assign()` from URL params or user input
- `postMessage` — `addEventListener('message', ...)` handlers that trust `event.data` without
  validating `event.origin`

**Backend (Bun/Node, Go)**

- Command injection — `exec()`, `execSync()`, `spawn()` with string interpolation reachable
  from user input; prefer `execFile()` / `spawn()` with argument arrays. Go: `exec.Command()`
  with interpolated user input.
- Path traversal — `fs.readFile`, `fs.writeFile`, `path.join` on user-controlled paths without
  `path.resolve` plus prefix validation
- Unsafe execution — `eval()`, `new Function()`, `vm.runInNewContext()` on non-literal input
- SQL — `fmt.Sprintf` or template literals building raw queries

For each finding, name the source variable and whether the guard is present, absent, or
unclear.
