const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const WALLET_STATUS = 'active';
const CURRENCY = 'YER';

function positiveAmount(value) {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function serverAudit(ref, data) {
  return ref.set({
    ...data,
    source: 'wallet_backend',
    createdAt: FieldValue.serverTimestamp(),
  });
}

exports.processWalletOperation = onDocumentCreated(
  {
    document: 'walletOperations/{operationId}',
    region: 'us-central1',
    retry: true,
  },
  async (event) => {
    const operationId = event.params.operationId;
    const snapshot = event.data;
    if (!snapshot) return;

    const operation = snapshot.data() || {};
    const operationRef = snapshot.ref;
    const auditRef = db.collection('auditLogs').doc();

    if (operation.status !== 'pending') return;

    const type = operation.type;
    const uid = operation.uid;
    const amount = operation.amount;
    const recipientUid = operation.recipientUid;

    if (!uid || !['deposit', 'withdraw', 'transfer'].includes(type) || !positiveAmount(amount)) {
      await operationRef.update({
        status: 'rejected',
        rejectionCode: 'INVALID_OPERATION',
        processedAt: FieldValue.serverTimestamp(),
      });
      await serverAudit(auditRef, {
        actorUid: uid || 'unknown',
        action: 'wallet.operation.rejected',
        result: 'rejected',
        operationId,
        reason: 'INVALID_OPERATION',
      });
      return;
    }

    if (type === 'deposit' || type === 'withdraw') {
      // External cash/payment verification is intentionally not bypassed.
      // These requests remain pending until a trusted payment workflow approves them.
      await operationRef.update({
        status: 'awaiting_verification',
        processedAt: FieldValue.serverTimestamp(),
      });
      await serverAudit(auditRef, {
        actorUid: uid,
        action: `wallet.${type}.awaiting_verification`,
        result: 'pending',
        operationId,
        amount,
        currency: CURRENCY,
      });
      return;
    }

    if (!recipientUid || recipientUid === uid) {
      await operationRef.update({
        status: 'rejected',
        rejectionCode: 'INVALID_RECIPIENT',
        processedAt: FieldValue.serverTimestamp(),
      });
      await serverAudit(auditRef, {
        actorUid: uid,
        action: 'wallet.transfer.rejected',
        result: 'rejected',
        operationId,
        reason: 'INVALID_RECIPIENT',
      });
      return;
    }

    const sourceRef = db.collection('wallets').doc(uid);
    const destinationRef = db.collection('wallets').doc(recipientUid);
    const transactionRef = db.collection('walletTransactions').doc(operationId);

    try {
      await db.runTransaction(async (tx) => {
        const [sourceSnap, destinationSnap, operationSnap, existingTx] = await Promise.all([
          tx.get(sourceRef),
          tx.get(destinationRef),
          tx.get(operationRef),
          tx.get(transactionRef),
        ]);

        if (existingTx.exists) {
          return;
        }
        if (!operationSnap.exists || operationSnap.data().status !== 'pending') {
          return;
        }
        if (!sourceSnap.exists || !destinationSnap.exists) {
          throw new Error('WALLET_NOT_FOUND');
        }

        const source = sourceSnap.data();
        const destination = destinationSnap.data();
        const sourceBalance = Number(source.availableBalance || 0);
        const destinationBalance = Number(destination.availableBalance || 0);

        if (source.currency !== CURRENCY || destination.currency !== CURRENCY ||
            source.status !== WALLET_STATUS || destination.status !== WALLET_STATUS) {
          throw new Error('WALLET_NOT_ACTIVE');
        }
        if (sourceBalance < amount) {
          throw new Error('INSUFFICIENT_FUNDS');
        }

        const now = FieldValue.serverTimestamp();
        tx.update(sourceRef, {
          availableBalance: sourceBalance - amount,
          version: Number(source.version || 1) + 1,
          updatedAt: now,
        });
        tx.update(destinationRef, {
          availableBalance: destinationBalance + amount,
          version: Number(destination.version || 1) + 1,
          updatedAt: now,
        });
        tx.set(transactionRef, {
          operationId,
          uid,
          type: 'transfer_debit',
          amount,
          currency: CURRENCY,
          recipientUid,
          direction: 'debit',
          createdAt: now,
        });
        tx.update(operationRef, {
          status: 'completed',
          processedAt: now,
          currency: CURRENCY,
        });
      });

      await serverAudit(auditRef, {
        actorUid: uid,
        action: 'wallet.transfer.completed',
        result: 'success',
        operationId,
        amount,
        currency: CURRENCY,
        recipientUid,
      });
    } catch (error) {
      const code = error && error.message ? error.message : 'WALLET_OPERATION_FAILED';
      await operationRef.update({
        status: 'rejected',
        rejectionCode: code,
        processedAt: FieldValue.serverTimestamp(),
      });
      await serverAudit(auditRef, {
        actorUid: uid,
        action: 'wallet.transfer.rejected',
        result: 'rejected',
        operationId,
        amount,
        currency: CURRENCY,
        recipientUid,
        reason: code,
      });
      logger.error('Wallet operation rejected', { operationId, code });
    }
  },
);
