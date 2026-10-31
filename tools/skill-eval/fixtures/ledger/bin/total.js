#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { readLedger, total } = require('../src/ledger');
const { formatCents } = require('../src/amount');

const file = process.argv[2];
if (!file) {
  console.error('usage: total.js <ledger-file>');
  process.exit(1);
}

const entries = readLedger(fs.readFileSync(file, 'utf8'));
console.log(formatCents(total(entries)));
