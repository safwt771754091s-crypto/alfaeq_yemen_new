const DEFAULT_SAR_TO_YER = 413;

async function getSarToYerRate(db) {
  // The platform's approved catalog conversion is fixed at 413 YER per 1 SAR.
  // Always synchronize Firestore so an older stored rate cannot silently override it.
  const rate = DEFAULT_SAR_TO_YER;
  await db.collection('settings').doc('currency_rates').set({
    sarToYer: rate,
    baseCurrency: 'YER',
    sourceCurrency: 'SAR',
    updatedAt: new Date(),
  }, { merge: true });
  return rate;
}

function sarToYer(amountSar, rate) {
  const value = Number(amountSar);
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * rate * 100) / 100;
}

module.exports = { DEFAULT_SAR_TO_YER, getSarToYerRate, sarToYer };
