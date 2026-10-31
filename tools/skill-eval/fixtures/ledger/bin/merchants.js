#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { readLedger } = require('../src/ledger');

const file = process.argv[2];
if (!file) {
  console.error('usage: merchants.js <ledger-file>');
  process.exit(1);
}

// Distinct merchants, in the order they first appear.
const merchants = [];
for (const entry of readLedger(fs.readFileSync(file, 'utf8'))) {
  if (!merchants.includes(entry.merchant)) merchants.push(entry.merchant);
}
console.log(merchants.join('\n'));
