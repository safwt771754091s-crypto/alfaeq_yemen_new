const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();
const SUPPORTED_METHODS = new Set(['cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet']);

exports.createOrderPaymentRecord = onDocumentCreated(
  { document: 'orders/{orderId}', region: 'us-central1', retry: true },
  async (event) => {
    const orderId = event.params.orderId;
    const snapshot = event.data;
    if (!snapshot) return;
    const order = snapshot.data() || {};
    const method = String(order.paymentMethod || '');
    if (!SUPPORTED_METHODS.has(method)) return;

    const ref = db.collection('payments').doc(orderId);
    if ((await ref.get()).exists) return;

    const status = method === 'cash_on_delivery' ? 'payable_on_delivery' : 'awaiting_confirmation';
    await ref.create({
      paymentId: orderId,
      orderId,
      customerId: String(order.customerId || ''),
      merchantIds: Array.isArray(order.merchantIds) ? order.merchantIds : [],
      provider: method,
      method,
      amount: Number(order.total || 0),
      currency: String(order.currency || 'YER'),
      status,
      verified: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await db.collection('auditLogs').add({
      actorUid: String(order.customerId || 'system'),
      action: 'payment.intent.created',
      result: status,
      source: 'payment_backend',
      orderId,
      paymentMethod: method,
      amount: Number(order.total || 0),
      createdAt: FieldValue.serverTimestamp(),
    });
  },
);
