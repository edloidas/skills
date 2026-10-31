'use strict';

// Parses a decimal amount such as "12.50" into integer cents.
function parseAmount(text) {
  const [whole, fraction = ''] = text.trim().split('.');
  return Number(whole) * 100 + Number(fraction.padEnd(2, '0').slice(0, 2));
}

function formatCents(cents) {
  const whole = Math.floor(cents / 100);
  const rest = String(cents % 100).padStart(2, '0');
  return `${whole}.${rest}`;
}

module.exports = { parseAmount, formatCents };
