# #17 total.js drops the last entry when the file has no trailing newline

Labels: bug

`node bin/total.js examples/march.txt` prints `42.60`, but the entries add up to `43.50`.

`examples/march.txt` has no newline after its last line, and `readLedger` in `src/ledger.js` splits
on `\n`, so the last entry (`cinema, 3.5`) is lost. Files saved with a trailing newline total
correctly.

Fix: make `readLedger` keep a last line that has no trailing newline.
