const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
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
    source: data.source || 'wallet_backend',
    createdAt: FieldValue.serverTimestamp(),
  });
}

function automationRef(source, id) {
  return db.collection('platformAutomation').doc(`${source}_${id}`);
}

async function updateAutomation(source, id, payload) {
  await automationRef(source, id).set({
    source,
    sourceId: id,
    ...payload,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.syncSectionAutomation = onDocumentWritten(
  { document: 'sections/{sectionId}', region: 'us-central1', retry: true },
  async (event) => {
    const sectionId = event.params.sectionId;
    const after = event.data?.after;
    if (!after || !after.exists) {
      await updateAutomation('section', sectionId, { status: 'removed', ready: false, checklist: ['section_deleted'] });
      return;
    }
    const section = after.data() || {};
    const ready = typeof section.title === 'string' && section.title.trim() !== '' && section.enabled !== false;
    await updateAutomation('section', sectionId, {
      status: ready ? 'ready' : 'disabled_or_incomplete',
      ready,
      checklist: ready ? ['section_saved', 'public_catalog_source_ready', 'merchant_assignment_ready'] : ['complete_title', 'enable_section'],
    });
    await serverAudit({ actorUid: 'platform_automation', action: 'platform.section.automation_synced', result: ready ? 'ready' : 'needs_configuration', source: 'platform_automation', sectionId });
  },
);

exports.syncPaymentProviderAutomation = onDocumentWritten(
  { document: 'paymentProviders/{providerId}', region: 'us-central1', retry: true },
  async (event) => {
    const providerId = event.params.providerId;
    const after = event.data?.after;
    if (!after || !after.exists) {
      await updateAutomation('payment_provider', providerId, { status: 'removed', ready: false, checklist: ['provider_deleted'] });
      return;
    }
    const provider = after.data() || {};
    const hasIdentity = typeof provider.name === 'string' && provider.name.trim() !== '';
    const enabled = provider.enabled === true;
    const configured = provider.configurationStatus === 'configured';
    const ready = hasIdentity && enabled && configured;
    const checklist = [];
    if (!hasIdentity) checklist.push('provider_name');
    if (!enabled) checklist.push('enable_provider');
    if (!configured) checklist.push('official_credentials_and_api_configuration');
    if (configured) checklist.push('server_credentials_present');
    if (enabled) checklist.push('provider_enabled');
    await updateAutomation('payment_provider', providerId, {
      status: ready ? 'ready_for_transactions' : 'needs_configuration',
      ready,
      checklist,
      nextAction: ready ? 'none' : 'complete_official_provider_configuration',
    });
    await serverAudit({ actorUid: 'platform_automation', action: 'platform.payment_provider.automation_synced', result: ready ? 'ready' : 'needs_configuration', source: 'platform_automation', providerId });
  },
);

exports.syncStoreAutomation = onDocumentWritten(
  { document: 'stores/{storeId}', region: 'us-central1', retry: true },
  async (event) => {
    const storeId = event.params.storeId;
    const after = event.data?.after;
    if (!after || !after.exists) {
      await updateAutomation('store', storeId, { status: 'removed', ready: false, checklist: ['store_deleted'] });
      return;
    }
    const store = after.data() || {};
    const hasIdentity = typeof store.name === 'string' && store.name.trim() !== '';
    const hasOwner = typeof store.ownerId === 'string' && store.ownerId.trim() !== '' && store.ownerId !== 'admin-created';
    const hasSection = typeof store.sectionId === 'string' && store.sectionId.trim() !== '';
    const approved = store.status === 'approved' || store.status === 'active';
    const ready = hasIdentity && hasOwner && hasSection && approved;
    const checklist = [];
    if (!hasIdentity) checklist.push('store_name');
    if (!hasOwner) checklist.push('real_owner_account');
    if (!hasSection) checklist.push('section_assignment');
    if (!approved) checklist.push('store_approval');
    if (ready) checklist.push('catalog_entry_ready');
    await updateAutomation('store', storeId, {
      status: ready ? 'ready' : 'needs_configuration',
      ready,
      checklist,
      nextAction: ready ? 'none' : 'complete_store_setup_and_approval',
    });
    await serverAudit({ actorUid: store.ownerId || 'unknown', action: 'platform.store.automation_synced', result: ready ? 'ready' : 'needs_configuration', source: 'platform_automation', storeId });
  },
);

exports.syncProductAutomation = onDocumentWritten(
  { document: 'products/{productId}', region: 'us-central1', retry: true },
  async (event) => {
    const productId = event.params.productId;
    const after = event.data?.after;
    if (!after || !after.exists) {
      await updateAutomation('product', productId, { status: 'removed', ready: false, checklist: ['product_deleted'] });
      return;
    }
    const product = after.data() || {};
    const hasName = typeof product.name === 'string' && product.name.trim() !== '';
    const hasStore = typeof product.storeId === 'string' && product.storeId.trim() !== '';
    const hasOwner = typeof product.ownerId === 'string' && product.ownerId.trim() !== '' && product.ownerId !== 'admin-created';
    const validPrice = typeof product.price === 'number' && Number.isFinite(product.price) && product.price >= 0;
    const validStock = typeof product.stock === 'number' && Number.isInteger(product.stock) && product.stock >= 0;
    const active = product.status === 'active';
    const ready = hasName && hasStore && hasOwner && validPrice && validStock && active;
    const checklist = [];
    if (!hasName) checklist.push('product_name');
    if (!hasStore) checklist.push('store_assignment');
    if (!hasOwner) checklist.push('real_owner_account');
    if (!validPrice) checklist.push('valid_price');
    if (!validStock) checklist.push('valid_stock');
    if (!active) checklist.push('activate_product');
    if (ready) checklist.push('catalog_ready');
    await updateAutomation('product', productId, {
      status: ready ? 'ready' : 'needs_configuration',
      ready,
      checklist,
      nextAction: ready ? 'none' : 'complete_product_setup',
    });
    await serverAudit({ actorUid: product.ownerId || 'unknown', action: 'platform.product.automation_synced', result: ready ? 'ready' : 'needs_configuration', source: 'platform_automation', productId });
  },
);

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
      const transactionResult = await db.runTransaction(async (tx) => {
        const sourceSnap = await tx.get(sourceRef);
        const destinationSnap = await tx.get(destinationRef);
        const operationSnap = await tx.get(operationRef);
        const debitSnap = await tx.get(debitRef);
        const creditSnap = await tx.get(creditRef);

        if (debitSnap.exists || creditSnap.exists || operationSnap.data()?.status !== 'pending') return { processed: false };
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
        return { processed: true };
      });

      if (transactionResult?.processed) {
        await serverAudit({ actorUid: uid, action: 'wallet.transfer.completed', result: 'success', operationId, amount, currency: CURRENCY, recipientUid });
      }
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
