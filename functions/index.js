const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const WALLET_STATUS = 'active';
const CURRENCY = 'YER';
const MAX_OPERATION_AMOUNT = 100000000;

function positiveAmount(value) {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= MAX_OPERATION_AMOUNT;
}

function validOperationEnvelope(operation) {
  return operation
    && typeof operation.uid === 'string'
    && ['deposit', 'withdraw', 'transfer'].includes(operation.type)
    && operation.status === 'pending'
    && operation.currency === CURRENCY
    && positiveAmount(operation.amount)
    && operation.createdAt != null;
}

async function serverAudit(data) {
  await db.collection('auditLogs').add({
    ...data,
    source: 'wallet_backend',
    createdAt: FieldValue.serverTimestamp(),
  });
}

exports.processWalletOperation = onDocumentCreated(
  { document: 'walletOperations/{operationId}', region: 'us-central1', retry: true },
  async (event) => {
    const operationId = event.params.operationId;
    const snapshot = event.data;
    if (!snapshot) return;

    const operation = snapshot.data() || {};
    const operationRef = snapshot.ref;
    if (operation.status !== 'pending') return;

    const type = operation.type;
    const uid = operation.uid;
    const amount = operation.amount;
    const recipientUid = operation.recipientUid;

    if (!validOperationEnvelope(operation)) {
      await operationRef.update({ status: 'rejected', rejectionCode: 'INVALID_OPERATION', processedAt: FieldValue.serverTimestamp() });
      await serverAudit({ actorUid: uid || 'unknown', action: 'wallet.operation.rejected', result: 'rejected', operationId, reason: 'INVALID_OPERATION' });
      return;
    }

    if (type === 'deposit' || type === 'withdraw') {
      await operationRef.update({ status: 'awaiting_verification', processedAt: FieldValue.serverTimestamp() });
      await serverAudit({ actorUid: uid, action: `wallet.${type}.awaiting_verification`, result: 'pending', operationId, amount, currency: CURRENCY });
      return;
    }

    if (typeof recipientUid !== 'string' || recipientUid.trim() === '' || recipientUid === uid) {
      await operationRef.update({ status: 'rejected', rejectionCode: 'INVALID_RECIPIENT', processedAt: FieldValue.serverTimestamp() });
      await serverAudit({ actorUid: uid, action: 'wallet.transfer.rejected', result: 'rejected', operationId, reason: 'INVALID_RECIPIENT' });
      return;
    }

    const sourceRef = db.collection('wallets').doc(uid);
    const destinationRef = db.collection('wallets').doc(recipientUid);
    const debitRef = db.collection('walletTransactions').doc(`${operationId}_debit`);
    const creditRef = db.collection('walletTransactions').doc(`${operationId}_credit`);

    try {
      await db.runTransaction(async (tx) => {
        const sourceSnap = await tx.get(sourceRef);
        const destinationSnap = await tx.get(destinationRef);
        const operationSnap = await tx.get(operationRef);
        const debitSnap = await tx.get(debitRef);
        const creditSnap = await tx.get(creditRef);

        if (debitSnap.exists || creditSnap.exists || operationSnap.data()?.status !== 'pending') return;
        if (!sourceSnap.exists || !destinationSnap.exists) throw new Error('WALLET_NOT_FOUND');

        const source = sourceSnap.data();
        const destination = destinationSnap.data();
        const sourceBalance = Number(source.availableBalance || 0);
        const destinationBalance = Number(destination.availableBalance || 0);

        if (source.currency !== CURRENCY || destination.currency !== CURRENCY || source.status !== WALLET_STATUS || destination.status !== WALLET_STATUS) throw new Error('WALLET_NOT_ACTIVE');
        if (!Number.isFinite(sourceBalance) || !Number.isFinite(destinationBalance) || sourceBalance < 0 || destinationBalance < 0) throw new Error('INVALID_WALLET_BALANCE');
        if (sourceBalance < amount) throw new Error('INSUFFICIENT_FUNDS');

        const now = FieldValue.serverTimestamp();
        tx.update(sourceRef, { availableBalance: sourceBalance - amount, version: Number(source.version || 1) + 1, updatedAt: now });
        tx.update(destinationRef, { availableBalance: destinationBalance + amount, version: Number(destination.version || 1) + 1, updatedAt: now });
        tx.create(debitRef, { operationId, uid, type: 'transfer_debit', amount, currency: CURRENCY, counterpartyUid: recipientUid, direction: 'debit', createdAt: now });
        tx.create(creditRef, { operationId, uid: recipientUid, type: 'transfer_credit', amount, currency: CURRENCY, counterpartyUid: uid, direction: 'credit', createdAt: now });
        tx.update(operationRef, { status: 'completed', processedAt: now, currency: CURRENCY });
      });

      await serverAudit({ actorUid: uid, action: 'wallet.transfer.completed', result: 'success', operationId, amount, currency: CURRENCY, recipientUid });
    } catch (error) {
      const code = error && error.message ? error.message : 'WALLET_OPERATION_FAILED';
      if (!['WALLET_NOT_FOUND', 'WALLET_NOT_ACTIVE', 'INSUFFICIENT_FUNDS', 'INVALID_WALLET_BALANCE'].includes(code)) {
        logger.error('Transient wallet operation failure', { operationId, code });
        throw error;
      }
      await operationRef.update({ status: 'rejected', rejectionCode: code, processedAt: FieldValue.serverTimestamp() });
      await serverAudit({ actorUid: uid, action: 'wallet.transfer.rejected', result: 'rejected', operationId, amount, currency: CURRENCY, recipientUid, reason: code });
    }
  },
);
