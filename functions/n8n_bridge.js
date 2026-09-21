const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');

const db = getFirestore();
const CONFIG_DOC = 'platformIntegrations/n8n';

async function loadConfig() {
  const snap = await db.doc(CONFIG_DOC).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  const url = typeof data.webhookUrl === 'string' ? data.webhookUrl.trim() : '';
  const sharedSecret = typeof data.sharedSecret === 'string' ? data.sharedSecret : '';
  if (!url || !sharedSecret || data.enabled !== true) return null;
  return { url, sharedSecret };
}

async function forward(eventType, id, data) {
  const config = await loadConfig();
  if (!config) {
    logger.warn('n8n bridge is not configured; event remains in Firebase', { eventType, id });
    return;
  }

  const response = await fetch(config.url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-alfaeq-automation-secret': config.sharedSecret,
    },
    body: JSON.stringify({
      source: 'alfaeq_yemen',
      version: 1,
      eventId: id,
      eventType,
      occurredAt: new Date().toISOString(),
      data: data || {},
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`N8N_WEBHOOK_FAILED:${response.status}:${detail.slice(0, 500)}`);
  }
}

function trigger(document, eventType) {
  return onDocumentCreated(
    { document, region: 'us-central1', retry: true },
    async (event) => {
      const id = event.params[Object.keys(event.params)[0]];
      const data = event.data?.data() || {};
      try {
        await forward(eventType, id, data);
      } catch (error) {
        logger.error('n8n automation delivery failed', {
          eventType,
          id,
          error: error?.message || String(error),
        });
        throw error;
      }
    },
  );
}

exports.n8nOrderCreated = trigger('orders/{orderId}', 'order.created');
exports.n8nProductCreated = trigger('products/{productId}', 'product.created');
exports.n8nStoreCreated = trigger('stores/{storeId}', 'store.created');
exports.n8nWhatsAppImportCreated = trigger('whatsappProductImports/{importId}', 'whatsapp.product_import.created');
exports.n8nMerchantInviteCreated = trigger('merchantInvites/{inviteId}', 'merchant.invite.created');
