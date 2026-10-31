'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { parseAmount, formatCents } = require('../src/amount');

test('parseAmount reads two-digit cents', () => {
  assert.strictEqual(parseAmount('12.50'), 1250);
  assert.strictEqual(parseAmount('0.05'), 5);
});

test('parseAmount reads whole amounts', () => {
  assert.strictEqual(parseAmount('40'), 4000);
});

test('formatCents pads cents', () => {
  assert.strictEqual(formatCents(1205), '12.05');
  assert.strictEqual(formatCents(4000), '40.00');
});
