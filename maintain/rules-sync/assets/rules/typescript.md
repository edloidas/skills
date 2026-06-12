---
paths:
  - '**/*.{ts,tsx}'
---

# TypeScript Rules

## Project conventions

- Stores start with `$`: `export const $counter = atom(0)`.
- Use `T | null | undefined` directly for nullish; pair with `!= null` checks.
- If the project provides `Result<T, E>` / `Ok<T>` / `Err<E>` helpers (`ok`, `err`, `isOk`, `isErr`), prefer them over thrown exceptions for operations that can fail.
- If the project provides `Brand<T, Tag>`, use it for nominal IDs (e.g. `type AssetId = Brand<string, 'AssetId'>`); same for `LiteralUnion<U, Base>` on known-values-plus-arbitrary-string props.
- Use the project's path alias (e.g. `@/`) for imports outside the current directory when one is configured; otherwise relative paths. Relative paths always inside the same directory.
- One file per type. Colocate child types with their parent. Type definitions don't live in store files (except the store's own type).

## Always `type`, never `interface extends`

Compose with intersection, even when extending DOM or third-party types:

```ts
type RequestOptions = {
  retry: number;
} & RequestInit;
```

Single-level `Omit` is fine; nested `Omit` means the underlying types should be restructured.

## No nested ternaries

Extract to `if`/`switch`, a lookup table, or a named function. Includes JSX render-time chains:

```tsx
// wrong
{
  loading ? <Spinner /> : icon ? <span>{icon}</span> : null;
}

// right
const leading = loading ? <Spinner /> : icon ? <span>{icon}</span> : null;
```

## Single-line guard clauses

```ts
if (element == null) return;
if (!isSupported) return false;
```

Never wrap a single-statement guard in braces.

## `!= null` for nullish checks

When you mean "not null and not undefined":

```ts
if (response != null) {
  /* safe to use */
}
```

Truthy checks reject `0`, `''`, and `false`.

## Destructure tuples and arrays

```ts
const [body, headers = {}] = request;
```

Index access (`request[0]`, `request[1]`) is the wrong default.
