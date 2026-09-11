const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'alfaeq-yemen-fed37';

admin.initializeApp({ projectId });
const db = admin.firestore();

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForOperation(operationId, expectedStatuses, timeoutMs = 30000) {
  const ref = db.collection('walletOperations').doc(operationId);
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snap = await ref.get();
    if (snap.exists && expectedStatuses.includes(snap.data().status)) {
      return snap.data();
    }
    await sleep(500);
  }
  const snap = await ref.get();
  throw new Error(`Timed out waiting for ${operationId}; last state=${JSON.stringify(snap.data() || null)}`);
}

async function resetCollections() {
  for (const collection of ['walletOperations', 'walletTransactions', 'auditLogs', 'wallets']) {
    const snapshot = await db.collection(collection).get();
    if (snapshot.empty) continue;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function seedWallet(uid, balance) {
  await db.collection('wallets').doc(uid).set({
    uid,
    currency: 'YER',
    availableBalance: balance,
    reservedBalance: 0,
    status: 'active',
    version: 1,
  });
}

async function createTransfer(operationId, uid, recipientUid, amount) {
  await db.collection('walletOperations').doc(operationId).set({
    type: 'transfer',
    recipientUid,
    amount,
    uid,
    status: 'pending',
    currency: 'YER',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function testSuccessfulAtomicTransfer() {
  await resetCollections();
  await seedWallet('sender', 1000);
  await seedWallet('receiver', 100);
  await createTransfer('integration-success', 'sender', 'receiver', 250);

  const operation = await waitForOperation('integration-success', ['completed', 'rejected']);
  assert.equal(operation.status, 'completed');

  const sender = (await db.collection('wallets').doc('sender').get()).data();
  const receiver = (await db.collection('wallets').doc('receiver').get()).data();
  assert.equal(sender.availableBalance, 750);
  assert.equal(receiver.availableBalance, 350);

  assert.ok((await db.collection('walletTransactions').doc('integration-success_debit').get()).exists);
  assert.ok((await db.collection('walletTransactions').doc('integration-success_credit').get()).exists);

  const audits = await db.collection('auditLogs').where('operationId', '==', 'integration-success').get();
  assert.ok(audits.docs.some((doc) => doc.data().action === 'wallet.transfer.completed'));
}

async function testInsufficientFundsIsAtomic() {
  await resetCollections();
  await seedWallet('sender', 100);
  await seedWallet('receiver', 100);
  await createTransfer('integration-insufficient', 'sender', 'receiver', 250);

  const operation = await waitForOperation('integration-insufficient', ['completed', 'rejected']);
  assert.equal(operation.status, 'rejected');
  assert.equal(operation.rejectionCode, 'INSUFFICIENT_FUNDS');

  const sender = (await db.collection('wallets').doc('sender').get()).data();
  const receiver = (await db.collection('wallets').doc('receiver').get()).data();
  assert.equal(sender.availableBalance, 100);
  assert.equal(receiver.availableBalance, 100);

  assert.equal((await db.collection('walletTransactions').doc('integration-insufficient_debit').get()).exists, false);
  assert.equal((await db.collection('walletTransactions').doc('integration-insufficient_credit').get()).exists, false);
}

async function main() {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'FIRESTORE_EMULATOR_HOST must be set by Firebase Emulator Suite');
  await testSuccessfulAtomicTransfer();
  await testInsufficientFundsIsAtomic();
  console.log('Wallet backend integration tests passed.');
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await resetCollections();
    await admin.app().delete();
  });
