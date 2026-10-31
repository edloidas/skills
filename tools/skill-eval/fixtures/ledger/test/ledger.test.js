'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { readLedger, total } = require('../src/ledger');

test('readLedger skips comments and blank lines', () => {
  const entries = readLedger('# head\n\n2026-02-01, market, 18.20\n');
  assert.deepStrictEqual(entries, [{ date: '2026-02-01', merchant: 'market', cents: 1820 }]);
});

test('total sums cents', () => {
  const entries = readLedger('2026-02-01, a, 1.25\n2026-02-02, b, 2.75\n');
  assert.strictEqual(total(entries), 400);
});
