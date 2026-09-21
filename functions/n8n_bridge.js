const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');

const N8N_WEBHOOK_URL = defineSecret('N8N_AUTOMATION_WEBHOOK_URL');
const N8N_SHARED_SECRET = defineSecret('N8N_AUTOMATION_SHARED_SECRET');

async function forward(eventType, id, data) {
  const url = N8N_WEBHOOK_URL.value();
  const sharedSecret = N8N_SHARED_SECRET.value();
  if (!url || !sharedSecret) {
    logger.warn('n8n bridge is not configured; event retained in Firestore only', { eventType, id });
    return;
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-alfaeq-automation-secret': sharedSecret,
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
    { document, region: 'us-central1', retry: true, secrets: [N8N_WEBHOOK_URL, N8N_SHARED_SECRET] },
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
