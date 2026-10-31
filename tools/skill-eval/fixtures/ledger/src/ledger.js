'use strict';

const { parseAmount } = require('./amount');

// A ledger line is "<YYYY-MM-DD>, <merchant>, <amount>".
function parseLine(line) {
  const [date, merchant, amount] = line.split(',');
  return { date: date.trim(), merchant: merchant.trim(), cents: parseAmount(amount) };
}

function readLedger(text) {
  return text
    .split('\n')
    .filter((line) => line.trim() !== '' && !line.startsWith('#'))
    .map(parseLine);
}

function total(entries) {
  return entries.reduce((sum, entry) => sum + entry.cents, 0);
}

module.exports = { parseLine, readLedger, total };
