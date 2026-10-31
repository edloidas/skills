# ledger

Command-line tools for plain-text expense ledgers. One entry per line:

```text
2026-03-02, coffee, 3.50
```

## Commands

- `node bin/total.js <file>` prints the total of a ledger, e.g. `43.50`.
- `node bin/weekend.js <file>` lists the entries dated on a Saturday or Sunday.
- `node bin/merchants.js <file>` lists each merchant once, in the order they first appear.
- `npm start` serves `GET /health` and `GET /total?ledger=<name>` for the ledgers in `examples/`.
