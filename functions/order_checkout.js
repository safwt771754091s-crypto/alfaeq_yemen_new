const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();
const CURRENCY = 'YER';
const UNIT_DEFS = { piece:{id:'piece',label:'قطعة',scale:1}, kg:{id:'kg',label:'كجم',scale:1000}, g:{id:'g',label:'جرام',scale:1}, l:{id:'l',label:'لتر',scale:1000}, ml:{id:'ml',label:'مل',scale:1}, m:{id:'m',label:'متر',scale:1} };
const unitFor = (p) => UNIT_DEFS[String(p.saleUnit || p.unit || 'piece')] || UNIT_DEFS.piece;
const stockBaseFor = (p,u) => Number.isFinite(Number(p.stockBase)) ? Math.round(Number(p.stockBase)) : Math.round(Number(p.stock || 0) * u.scale);
const stepBaseFor = (p,u) => Number(p.stepBase) > 0 ? Math.round(Number(p.stepBase)) : (u.id === 'kg' || u.id === 'l' ? 250 : (u.id === 'g' || u.id === 'ml' ? 50 : 1));

exports.createOrderFromCart = onCall({ region: 'us-central1', enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً.');
  const uid = request.auth.uid;
  const address = String(request.data?.address || '').trim();
  const paymentMethod = String(request.data?.paymentMethod || '');
  const location = request.data?.deliveryLocation;

  if (!address || address.length > 300) throw new HttpsError('invalid-argument', 'عنوان التوصيل غير صالح.');
  if (!['cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet'].includes(paymentMethod)) {
    throw new HttpsError('invalid-argument', 'طريقة الدفع غير مدعومة.');
  }

  let deliveryLocation = null;
  if (location && Number.isFinite(Number(location.latitude)) && Number.isFinite(Number(location.longitude))) {
    const latitude = Number(location.latitude);
    const longitude = Number(location.longitude);
    if (latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180) {
      deliveryLocation = { latitude, longitude };
    }
  }

  const cartRef = db.collection('carts').doc(uid);
  const orderRef = db.collection('orders').doc();

  try {
    const result = await db.runTransaction(async (tx) => {
      const cartSnap = await tx.get(cartRef);
      if (!cartSnap.exists) throw new HttpsError('failed-precondition', 'السلة فارغة.');
      const cart = cartSnap.data() || {};
      const rawItems = Array.isArray(cart.items) ? cart.items : [];
      if (!rawItems.length) throw new HttpsError('failed-precondition', 'السلة فارغة.');

      const quantities = new Map();
      for (const item of rawItems) {
        const productId = String(item?.productId || '').trim();
        const quantity = Number.isFinite(Number(item?.quantityBase)) ? Math.round(Number(item.quantityBase)) : Math.round(Number(item?.quantity || 0) * Number(item?.unitScale || 1));
        if (!productId || !Number.isInteger(quantity) || quantity < 1 || quantity > 100000000) {
          throw new HttpsError('invalid-argument', 'بيانات أحد أصناف السلة غير صالحة.');
        }
        quantities.set(productId, (quantities.get(productId) || 0) + quantity);
      }

      const productRefs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
      const productSnaps = [];
      for (const ref of productRefs) productSnaps.push(await tx.get(ref));

      const items = [];
      const merchantIds = new Set();
      const movements = [];
      let total = 0;

      for (let i = 0; i < productSnaps.length; i += 1) {
        const snap = productSnaps[i];
        const productId = productRefs[i].id;
        const requested = quantities.get(productId);
        if (!snap.exists) throw new HttpsError('failed-precondition', 'أحد المنتجات لم يعد موجوداً.');

        const product = snap.data() || {};
        const status = String(product.status || '').toLowerCase();
        const unit = unitFor(product);
        const price = Number(product.price ?? product.unitPrice);
        const stock = stockBaseFor(product, unit);
        const stepBase = stepBaseFor(product, unit);
        const minBase = Number(product.minOrderBase) > 0 ? Math.round(Number(product.minOrderBase)) : stepBase;
        if (status !== 'active') throw new HttpsError('failed-precondition', 'أحد المنتجات غير متاح حالياً.');
        if (!Number.isFinite(price) || price < 0) throw new HttpsError('failed-precondition', 'سعر أحد المنتجات غير صالح.');
        if (!Number.isInteger(stock) || stock < requested) {
          throw new HttpsError('failed-precondition', `المخزون غير كافٍ للمنتج: ${product.name || productId}.`);
        }

        const storeId = String(product.storeId || product.storeID || '');
        const ownerId = String(product.ownerId || product.merchantId || '');
        if (ownerId) merchantIds.add(ownerId);

        if (requested < minBase || requested % stepBase !== 0) throw new HttpsError('failed-precondition', `كمية ${product.name || productId} لا تطابق خطوة البيع.`);
        const saleQuantity = requested / unit.scale;
        const lineTotal = price * saleQuantity;
        total += lineTotal;
        items.push({
          productId,
          name: String(product.name || product.title || 'صنف'),
          quantity: saleQuantity,
          quantityBase: requested,
          unit: unit.id,
          unitLabel: unit.label,
          unitScale: unit.scale,
          price,
          unitPrice: price,
          lineTotal,
          currency: String(product.currency || CURRENCY),
          storeId,
          ownerId,
          imageUrl: String(product.imageUrl || product.image || ''),
        });

        tx.update(productRefs[i], {
          stockBase: stock - requested,
          stock: (stock - requested) / unit.scale,
          soldQuantity: Number(product.soldQuantity || 0) + saleQuantity,
          soldQuantityBase: Number(product.soldQuantityBase || 0) + requested,
          updatedAt: FieldValue.serverTimestamp(),
        });
        movements.push({ productId, quantity: saleQuantity, quantityBase: requested, unit: unit.id, stockBeforeBase: stock, stockAfterBase: stock - requested });
      }

      const invoiceRef = db.collection('invoices').doc(orderRef.id);
      const orderData = {
        customerId: uid,
        merchantIds: [...merchantIds],
        items,
        total,
        currency: CURRENCY,
        address,
        paymentMethod,
        status: 'pending',
        deliveryStatus: 'awaiting_assignment',
        inventoryStatus: 'reserved',
        stockDeducted: true,
        stockDeductedAt: FieldValue.serverTimestamp(),
        stockMovements: movements,
        source: 'cart_checkout',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (deliveryLocation) orderData.deliveryLocation = deliveryLocation;

      tx.create(orderRef, orderData);
      tx.create(invoiceRef, { invoiceId: orderRef.id, orderId: orderRef.id, customerId: uid, merchantIds: [...merchantIds], items, subtotal: total, total, currency: CURRENCY, paymentMethod, status: 'issued', source: 'order_checkout', createdAt: FieldValue.serverTimestamp() });
      tx.set(cartRef, {
        ownerId: uid,
        customerId: uid,
        items: [],
        currency: CURRENCY,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      return { orderId: orderRef.id, invoiceId: invoiceRef.id, total, itemCount: items.length, stockMovements: movements };
    });

    await db.collection('auditLogs').add({
      actorUid: uid,
      action: 'order.checkout.completed',
      result: 'success',
      source: 'checkout_backend',
      orderId: result.orderId,
      total: result.total,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { ok: true, ...result, currency: CURRENCY, inventoryStatus: 'reserved' };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', 'تعذر إتمام الطلب بشكل آمن. لم يتم خصم أي مخزون.');
  }
});
