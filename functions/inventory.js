const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

function unitScale(item, product) {
  const value = Number(item?.unitScale ?? product?.unitScale ?? 1);
  return Number.isFinite(value) && value > 0 ? value : 1;
}

function baseQuantity(item, product) {
  const explicit = Number(item?.quantityBase);
  if (Number.isFinite(explicit) && Number.isInteger(explicit)) return explicit;
  const quantity = Number(item?.quantity);
  const scale = unitScale(item, product);
  return Number.isFinite(quantity) ? Math.round(quantity * scale) : 0;
}

function productStockBase(product) {
  const explicit = Number(product?.stockBase);
  if (Number.isFinite(explicit) && Number.isInteger(explicit)) return explicit;
  const stock = Number(product?.stock);
  const scale = Number(product?.unitScale ?? 1);
  return Number.isFinite(stock) && Number.isFinite(scale) && scale > 0
    ? Math.round(stock * scale)
    : 0;
}

exports.reserveOrderStock = onDocumentCreated(
  { document: 'orders/{orderId}', region: 'us-central1', retry: true },
  async (event) => {
    const orderId = event.params.orderId;
    const orderRef = db.collection('orders').doc(orderId);

    try {
      await db.runTransaction(async (tx) => {
        const orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) return;
        const order = orderSnap.data() || {};
        if (order.inventoryStatus === 'reserved' || order.stockDeducted === true) return;
        if (order.inventoryStatus === 'insufficient_stock') return;

        const rawItems = Array.isArray(order.items) ? order.items : [];
        if (rawItems.length === 0) {
          tx.update(orderRef, { inventoryStatus: 'insufficient_stock', stockDeducted: false, rejectionCode: 'EMPTY_ORDER', status: 'rejected', updatedAt: FieldValue.serverTimestamp() });
          return;
        }

        const quantities = new Map();
        for (const item of rawItems) {
          const productId = String(item?.productId || '').trim();
          const requested = baseQuantity(item, item);
          if (!productId || !Number.isInteger(requested) || requested <= 0) {
            tx.update(orderRef, { inventoryStatus: 'insufficient_stock', stockDeducted: false, rejectionCode: 'INVALID_ORDER_ITEM', status: 'rejected', updatedAt: FieldValue.serverTimestamp() });
            return;
          }
          quantities.set(productId, (quantities.get(productId) || 0) + requested);
        }

        const productRefs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
        const productSnaps = [];
        for (const ref of productRefs) productSnaps.push(await tx.get(ref));

        for (let i = 0; i < productSnaps.length; i += 1) {
          const snap = productSnaps[i];
          const productId = productRefs[i].id;
          const requested = quantities.get(productId);
          if (!snap.exists) {
            tx.update(orderRef, { inventoryStatus: 'insufficient_stock', stockDeducted: false, rejectionCode: 'PRODUCT_NOT_FOUND', rejectionProductId: productId, status: 'rejected', updatedAt: FieldValue.serverTimestamp() });
            return;
          }
          const available = productStockBase(snap.data() || {});
          if (!Number.isInteger(available) || available < requested) {
            tx.update(orderRef, { inventoryStatus: 'insufficient_stock', stockDeducted: false, rejectionCode: 'INSUFFICIENT_STOCK', rejectionProductId: productId, requestedQuantityBase: requested, availableStockBase: Number.isFinite(available) ? available : 0, status: 'rejected', updatedAt: FieldValue.serverTimestamp() });
            return;
          }
        }

        const now = FieldValue.serverTimestamp();
        const deductedItems = [];
        for (let i = 0; i < productSnaps.length; i += 1) {
          const productRef = productRefs[i];
          const product = productSnaps[i].data() || {};
          const requestedBase = quantities.get(productRef.id);
          const oldStockBase = productStockBase(product);
          const scale = Number(product.unitScale ?? 1) > 0 ? Number(product.unitScale) : 1;
          const newStockBase = oldStockBase - requestedBase;
          tx.update(productRef, {
            stockBase: newStockBase,
            stock: newStockBase / scale,
            soldQuantityBase: Number(product.soldQuantityBase || 0) + requestedBase,
            soldQuantity: Number(product.soldQuantity || 0) + requestedBase / scale,
            updatedAt: now,
          });
          deductedItems.push({ productId: productRef.id, quantityBase: requestedBase, stockBeforeBase: oldStockBase, stockAfterBase: newStockBase });
        }
        tx.update(orderRef, { inventoryStatus: 'reserved', stockDeducted: true, stockDeductedAt: now, stockMovements: deductedItems, updatedAt: now });
      });

      await db.collection('auditLogs').add({ actorUid: event.data?.data()?.customerId || 'unknown', action: 'order.inventory.deducted', result: 'success', source: 'inventory_backend', orderId, createdAt: FieldValue.serverTimestamp() });
    } catch (error) {
      logger.error('Inventory reservation failed', { orderId, error: error?.message || String(error) });
      throw error;
    }
  },
);

/** Creates an auditable payment intent without falsely confirming external payment. */
exports.createOrderPaymentRecord = onDocumentCreated(
  { document: 'orders/{orderId}', region: 'us-central1', retry: true },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const orderId = event.params.orderId;
    const order = snapshot.data() || {};
    const method = String(order.paymentMethod || '');
    if (!['cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet'].includes(method)) return;

    const paymentRef = db.collection('payments').doc(orderId);
    if ((await paymentRef.get()).exists) return;
    const status = method === 'cash_on_delivery' ? 'payable_on_delivery' : 'awaiting_confirmation';
    await paymentRef.create({
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
    await db.collection('auditLogs').add({ actorUid: String(order.customerId || 'system'), action: 'payment.intent.created', result: status, source: 'payment_backend', orderId, paymentMethod: method, amount: Number(order.total || 0), createdAt: FieldValue.serverTimestamp() });
  },
);
