'use strict';

function isWeekend(dateText) {
  const day = new Date(`${dateText}T00:00:00Z`).getUTCDay();
  return day === 0 || day === 7;
}

module.exports = { isWeekend };
