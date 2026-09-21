const DEFAULT_SAR_TO_YER = 650;

async function getSarToYerRate(db) {
  const refs = [
    db.collection('settings').doc('currency_rates'),
    db.collection('settings').doc('exchange_rates'),
  ];
  for (const ref of refs) {
    const snap = await ref.get();
    if (!snap.exists) continue;
    const data = snap.data() || {};
    const rate = Number(data.sarToYer ?? data.SAR_YER ?? data.sar_yer);
    if (Number.isFinite(rate) && rate > 0) return rate;
  }
  await db.collection('settings').doc('currency_rates').set({
    sarToYer: DEFAULT_SAR_TO_YER,
    baseCurrency: 'YER',
    sourceCurrency: 'SAR',
    updatedAt: new Date(),
  }, { merge: true });
  return DEFAULT_SAR_TO_YER;
}

function sarToYer(amountSar, rate) {
  const value = Number(amountSar);
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * rate * 100) / 100;
}

module.exports = { DEFAULT_SAR_TO_YER, getSarToYerRate, sarToYer };
