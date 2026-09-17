const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

/**
 * Deduct inventory atomically when a customer completes checkout.
 * This runs on the server so customers cannot directly modify product stock.
 * It is idempotent and safe to retry.
 */
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
          tx.update(orderRef, {
            inventoryStatus: 'insufficient_stock',
            stockDeducted: false,
            rejectionCode: 'EMPTY_ORDER',
            status: 'rejected',
            updatedAt: FieldValue.serverTimestamp(),
          });
          return;
        }

        // Combine duplicate product lines so stock is deducted exactly once per product.
        const quantities = new Map();
        for (const item of rawItems) {
          const productId = String(item?.productId || '').trim();
          const quantity = Number(item?.quantity || 0);
          if (!productId || !Number.isInteger(quantity) || quantity <= 0) {
            tx.update(orderRef, {
              inventoryStatus: 'insufficient_stock',
              stockDeducted: false,
              rejectionCode: 'INVALID_ORDER_ITEM',
              status: 'rejected',
              updatedAt: FieldValue.serverTimestamp(),
            });
            return;
          }
          quantities.set(productId, (quantities.get(productId) || 0) + quantity);
        }

        const productRefs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
        const productSnaps = await Promise.all(productRefs.map((ref) => tx.get(ref)));

        for (let i = 0; i < productSnaps.length; i += 1) {
          const snap = productSnaps[i];
          const productId = productRefs[i].id;
          const requested = quantities.get(productId);
          if (!snap.exists) {
            tx.update(orderRef, {
              inventoryStatus: 'insufficient_stock',
              stockDeducted: false,
              rejectionCode: 'PRODUCT_NOT_FOUND',
              rejectionProductId: productId,
              status: 'rejected',
              updatedAt: FieldValue.serverTimestamp(),
            });
            return;
          }

          const product = snap.data() || {};
          const stock = Number(product.stock);
          if (!Number.isInteger(stock) || stock < 0 || stock < requested) {
            tx.update(orderRef, {
              inventoryStatus: 'insufficient_stock',
              stockDeducted: false,
              rejectionCode: 'INSUFFICIENT_STOCK',
              rejectionProductId: productId,
              requestedQuantity: requested,
              availableStock: Number.isFinite(stock) ? stock : 0,
              status: 'rejected',
              updatedAt: FieldValue.serverTimestamp(),
            });
            return;
          }
        }

        const now = FieldValue.serverTimestamp();
        const deductedItems = [];
        for (let i = 0; i < productSnaps.length; i += 1) {
          const snap = productSnaps[i];
          const productId = productRefs[i].id;
          const requested = quantities.get(productId);
          const product = snap.data() || {};
          const oldStock = Number(product.stock);
          const newStock = oldStock - requested;

          tx.update(productRefs[i], {
            stock: newStock,
            soldQuantity: Number(product.soldQuantity || 0) + requested,
            updatedAt: now,
          });

          deductedItems.push({
            productId,
            quantity: requested,
            stockBefore: oldStock,
            stockAfter: newStock,
          });
        }

        tx.update(orderRef, {
          inventoryStatus: 'reserved',
          stockDeducted: true,
          stockDeductedAt: now,
          stockMovements: deductedItems,
          updatedAt: now,
        });
      });

      await db.collection('auditLogs').add({
        actorUid: event.data?.data()?.customerId || 'unknown',
        action: 'order.inventory.deducted',
        result: 'success',
        source: 'inventory_backend',
        orderId,
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      logger.error('Inventory reservation failed', { orderId, error: error?.message || String(error) });
      throw error;
    }
  },
);
