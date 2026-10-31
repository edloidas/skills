# ledger

Plain Node.js, no dependencies. Node 20 or later.

## Checks

- `npm test` runs the unit tests (`node --test test/*.test.js`).

## Conventions

- CommonJS modules, `'use strict'` at the top of every file.
- Amounts are integer cents everywhere inside the code; only `formatCents` turns them into text.
