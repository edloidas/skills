#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { readLedger } = require('../src/ledger');
const { isWeekend } = require('../src/calendar');
const { formatCents } = require('../src/amount');

const file = process.argv[2];
if (!file) {
  console.error('usage: weekend.js <ledger-file>');
  process.exit(1);
}

for (const entry of readLedger(fs.readFileSync(file, 'utf8'))) {
  if (isWeekend(entry.date)) console.log(`${entry.date}  ${entry.merchant}  ${formatCents(entry.cents)}`);
}
