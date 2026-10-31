# #17 Monthly total is wrong for amounts with one decimal digit

Labels: bug

`node bin/total.js examples/march.txt` prints `42.60`, but the four entries add up to `43.50`
(3.50 + 24.50 + 12.00 + 3.50).

The two entries written with a single decimal digit (`24.5`, `3.5`) seem to be read as 24.05 and
3.05. Amounts like `12.00` are fine.

Expected: one-digit amounts mean tenths, so `24.5` is 24.50.
