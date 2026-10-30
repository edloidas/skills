# TypeScript 7 migration recipes

Fixes for each blocking finding. The checker reports *what* broke; this file is *how* to fix it.

TypeScript 7 often prints the replacement itself on the line after the error
(`Use '"paths": {"*": ["./src/*"]}' instead.`). When it does, prefer the compiler's suggestion
over anything here — it is computed from the actual config.

## Removed options

### `baseUrl`

Removed. It was doing two jobs, and only one of them was wanted.

Most projects only used it as a prefix for `paths`. Fold the prefix into each entry and delete it:

```jsonc
// before
{ "baseUrl": "./src", "paths": { "@app/*": ["app/*"], "@lib/*": ["lib/*"] } }
// after
{ "paths": { "@app/*": ["./src/app/*"], "@lib/*": ["./src/lib/*"] } }
```

Projects that genuinely relied on it as a module lookup root need an explicit catch-all, which
also restores the behaviour where a bare `import "someModule"` resolved to `src/someModule`:

```jsonc
{ "paths": { "*": ["./src/*"], "@app/*": ["./src/app/*"] } }
```

Check every non-tsc consumer before shipping this. Bundler aliases, Vitest/Jest `moduleNameMapper`
and IDE resolution read `baseUrl`/`paths` themselves, and a clean `tsc` run does not prove they
still resolve.

### `outFile`

Removed with no replacement. Bundle with esbuild, Rollup, Vite or webpack and leave TypeScript to
type-checking and declaration emit.

### `downlevelIteration`

Removed. It only ever affected ES5 emit, and ES5 is gone. Delete it — including
`"downlevelIteration": false`, which is also an error.

## Removed values

### `target: "es5"` / `"es3"`

The floor is now ES2015. Pick a real target — `es2022` is a safe modern default. If you still
must ship ES5, run TypeScript's output through Babel, esbuild or swc.

### `moduleResolution: "node"` / `"node10"` / `"classic"`

Only `node16`, `nodenext` and `bundler` remain.

| Shipping to | Use |
| ----------- | --- |
| Node.js directly | `nodenext` |
| A bundler, or Bun | `bundler` |
| Pinned Node 16/18 semantics | `node16` |

`bundler` requires `module` to be `preserve`, `commonjs`, or `es2015`+ — a mismatch is `TS5095`.

### `module: "amd"` / `"umd"` / `"system"` / `"none"`

Removed. Emit ESM (`esnext`/`preserve`) or `commonjs` and let a bundler produce whatever format
the target environment needs. `amd-module` directives are inert.

### `esModuleInterop: false`, `allowSyntheticDefaultImports: false`, `alwaysStrict: false`

The safe behaviour is now unconditional. Delete the flag; if code depended on the old interop,
rewrite the imports:

```ts
import * as express from "express"  // before
import express from "express"       // after
```

`alwaysStrict: false` additionally means all code is strict-mode now. Reserved words used as
identifiers (`await`, `static`, `private`, `public`) must be renamed.

## Options dead since TypeScript 5.5

`charset`, `importsNotUsedAsValues`, `preserveValueImports`, `noImplicitUseStrict`,
`noStrictGenericChecks`, `keyofStringsOnly`, `suppressExcessPropertyErrors`,
`suppressImplicitAnyIndexErrors`, `out`, `prepend`.

Deprecated in 5.0, inert since 5.5, and reported by TS7 as `TS5023 Unknown compiler option` — the
same error a typo produces. Delete them; nothing has read them for several releases.

`importsNotUsedAsValues` and `preserveValueImports` were replaced by `verbatimModuleSyntax`, which
is the flag to add if you actually wanted that behaviour.

## Defaults that changed under you

These are the two that break builds silently, because nothing errors — the output just moves or
the globals just vanish.

### `rootDir` now defaults to `.`

Previously inferred from the common directory of the input files. Now fixed at the directory
containing `tsconfig.json`.

Sources in `src/` with `outDir: "./dist"` now emit to `dist/src/index.js` instead of
`dist/index.js`, which breaks every `main`, `exports` and import path pointing at the old layout.
Set it explicitly:

```jsonc
{ "compilerOptions": { "rootDir": "./src", "outDir": "./dist" }, "include": ["src"] }
```

Only matters when emitting. A `noEmit` type-check-only config is unaffected.

### `types` now defaults to `[]`

TypeScript no longer auto-includes every package in `node_modules/@types`. Ambient globals
disappear, producing errors like `Cannot find name 'process'` or `Cannot find name 'describe'`.

List what the code actually uses:

```jsonc
{ "compilerOptions": { "types": ["node", "vitest/globals"] } }
```

`"types": ["*"]` restores the old enumerate-everything behaviour, but it is the slow path — the
release notes attribute 20–50% build-time improvements to setting this properly.

## Options worth keeping explicit

Not everything that matches a default should be dropped.

- **`target`** — the TS7 default floats to the newest stable ECMAScript version, so it changes on
  a compiler upgrade. An explicit target pins emit semantics.
- **`module`** — emit format is a deployment contract.
- **`lib`** — derived from `target`, so it inherits the float.
- **`strict`** — an explicit `true` documents intent, and stricter checks are planned.

## `ignoreDeprecations`

`"ignoreDeprecations": "6.0"` suppressed these as warnings in TypeScript 6. It does **not** rescue
anything in 7 — removed is removed. TS7 accepts the field without validating it, so it is inert and
can be deleted.
