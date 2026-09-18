const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');

const db = getFirestore();

const WHATSAPP_VERIFY_TOKEN = defineSecret('WHATSAPP_VERIFY_TOKEN');
const WHATSAPP_ACCESS_TOKEN = defineSecret('WHATSAPP_ACCESS_TOKEN');
const WHATSAPP_APP_SECRET = defineSecret('WHATSAPP_APP_SECRET');
const WHATSAPP_PHONE_NUMBER_ID = defineSecret('WHATSAPP_PHONE_NUMBER_ID');
const WHATSAPP_API_VERSION = defineSecret('WHATSAPP_API_VERSION');

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9]/g, '');
}

function parseProductText(text) {
  const raw = String(text || '').trim();
  const lines = raw.split(/\\r?\\n/).map((v) => v.trim()).filter(Boolean);
  const find = (patterns) => {
    for (const line of lines) {
      for (const pattern of patterns) {
        const match = line.match(pattern);
        if (match) return match[1].trim();
      }
    }
    return '';
  };

  const name = find([/^(?:اسم|المنتج|name)\\s*[:：-]\\s*(.+)$/i]) || (lines[0] && !/^(?:سعر|price|stock|المخزون)/i.test(lines[0]) ? lines[0] : '');
  const priceText = find([/^(?:سعر|price)\\s*[:：-]\\s*([0-9]+(?:[.,][0-9]+)?)/i]);
  const stockText = find([/^(?:المخزون|مخزون|stock|qty|quantity)\\s*[:：-]\\s*([0-9]+(?:[.,][0-9]+)?)/i]);
  const unitText = find([/^(?:الوحدة|وحدة|unit)\\s*[:：-]\\s*(.+)$/i]);
  const stepText = find([/^(?:الخطوة|step)\\s*[:：-]\\s*([0-9]+(?:[.,][0-9]+)?)/i]);
  const minText = find([/^(?:الحد الأدنى|اقل كمية|أقل كمية|min)\\s*[:：-]\\s*([0-9]+(?:[.,][0-9]+)?)/i]);
  const price = priceText ? Number(priceText.replace(',', '.')) : null;
  const stock = stockText ? Number(stockText.replace(',', '.')) : null;
  const unitAliases = { 'كجم':'kg','كيلو':'kg','كيلوجرام':'kg','kg':'kg','جرام':'g','غرام':'g','g':'g','لتر':'l','ل':'l','liter':'l','l':'l','مل':'ml','ملي':'ml','ml':'ml','متر':'m','m':'m','قطعة':'piece','قطعه':'piece','حبة':'piece','قطعة/حبة':'piece','piece':'piece' };
  const normalizedUnit = unitText ? unitAliases[String(unitText).trim().toLowerCase()] || 'piece' : 'piece';
  const unitScale = { piece:1, kg:1000, g:1, l:1000, ml:1, m:1 }[normalizedUnit] || 1;
  const step = stepText ? Number(stepText.replace(',', '.')) : (normalizedUnit === 'kg' || normalizedUnit === 'l' ? 0.25 : (normalizedUnit === 'g' || normalizedUnit === 'ml' ? 50 : 1));
  const min = minText ? Number(minText.replace(',', '.')) : step;
  return { rawText: raw, name: name || null, price: Number.isFinite(price) ? price : null, stock: Number.isFinite(stock) ? stock : null, saleUnit: normalizedUnit, unitScale, step, minOrder: min };
}

function signatureIsValid(req) {
  const secret = WHATSAPP_APP_SECRET.value();
  if (!secret) return false;
  const signature = String(req.get('x-hub-signature-256') || '');
  if (!signature.startsWith('sha256=')) return false;
  const expected = 'sha256=' + crypto.createHmac('sha256', secret).update(req.rawBody || Buffer.from('')).digest('hex');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function sendWhatsAppText(to, body) {
  const token = WHATSAPP_ACCESS_TOKEN.value();
  const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
  const version = WHATSAPP_API_VERSION.value() || 'v26.0';
  if (!token || !phoneNumberId) throw new Error('WHATSAPP_CREDENTIALS_NOT_CONFIGURED');

  const response = await fetch(`https://graph.facebook.com/${version}/${phoneNumberId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to,
      type: 'text',
      text: { body },
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`WHATSAPP_SEND_FAILED:${response.status}:${detail.slice(0, 500)}`);
  }
}

async function resolveConnection(phone) {
  const normalized = normalizePhone(phone);
  if (!normalized) return null;
  const direct = await db.collection('whatsappConnections').doc(normalized).get();
  if (direct.exists) return { id: direct.id, ...direct.data() };
  const snap = await db.collection('whatsappConnections').where('phone', '==', normalized).limit(1).get();
  return snap.empty ? null : { id: snap.docs[0].id, ...snap.docs[0].data() };
}

async function audit(actorUid, action, result, details = {}) {
  await db.collection('auditLogs').add({
    actorUid: actorUid || 'whatsapp_webhook',
    action,
    result,
    source: 'whatsapp_automation',
    ...details,
    createdAt: FieldValue.serverTimestamp(),
  });
}

exports.whatsappWebhook = onRequest(
  {
    region: 'us-central1',
    secrets: [
      WHATSAPP_VERIFY_TOKEN,
      WHATSAPP_ACCESS_TOKEN,
      WHATSAPP_APP_SECRET,
      WHATSAPP_PHONE_NUMBER_ID,
      WHATSAPP_API_VERSION,
    ],
  },
  async (req, res) => {
    if (req.method === 'GET') {
      const mode = String(req.query['hub.mode'] || '');
      const token = String(req.query['hub.verify_token'] || '');
      const challenge = String(req.query['hub.challenge'] || '');
      if (mode === 'subscribe' && token && token === WHATSAPP_VERIFY_TOKEN.value()) {
        res.status(200).send(challenge);
        return;
      }
      res.status(403).send('Forbidden');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    if (!signatureIsValid(req)) {
      res.status(401).send('Invalid signature');
      return;
    }

    try {
      const body = req.body || {};
      if (body.object !== 'whatsapp_business_account') {
        res.status(200).send('IGNORED');
        return;
      }

      for (const entry of body.entry || []) {
        for (const change of entry.changes || []) {
          const value = change.value || {};
          const messages = Array.isArray(value.messages) ? value.messages : [];
          for (const message of messages) {
            const from = normalizePhone(message.from);
            if (!from || !message.id) continue;

            const messageRef = db.collection('whatsappMessages').doc(message.id);
            const existing = await messageRef.get();
            if (existing.exists) continue;

            const contactName = value.contacts?.find((c) => normalizePhone(c.wa_id) === from)?.profile?.name || '';
            const connection = await resolveConnection(from);
            const textBody = message.type === 'text' ? String(message.text?.body || '') : '';
            const parsed = parseProductText(textBody);

            const importRef = db.collection('whatsappProductImports').doc();
            await messageRef.set({
              messageId: message.id,
              from,
              contactName,
              type: message.type || 'unknown',
              text: textBody,
              connectionId: connection?.id || null,
              storeId: connection?.storeId || null,
              merchantUid: connection?.merchantUid || null,
              receivedAt: FieldValue.serverTimestamp(),
              importId: importRef.id,
            });

            await importRef.set({
              source: 'whatsapp',
              whatsappMessageId: message.id,
              phone: from,
              contactName,
              merchantUid: connection?.merchantUid || null,
              storeId: connection?.storeId || null,
              status: connection?.storeId && connection?.merchantUid ? 'pending_confirmation' : 'unassigned',
              autoPublish: connection?.autoPublish === true,
              messageType: message.type || 'unknown',
              text: textBody,
              parsed,
              unit: parsed.saleUnit || 'piece',
              unitScale: parsed.unitScale || 1,
              step: parsed.step || 1,
              minOrder: parsed.minOrder || parsed.step || 1,
              mediaId: message.image?.id || message.document?.id || null,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            });

            await audit(connection?.merchantUid || null, 'whatsapp.product_import.received', 'success', {
              whatsappMessageId: message.id,
              importId: importRef.id,
              storeId: connection?.storeId || null,
              phone: from,
              messageType: message.type || 'unknown',
            });

            if (connection?.merchantUid && connection?.storeId) {
              const summary = [
                'تم استلام بيانات المنتج عبر واتساب ✅',
                parsed.name ? `الاسم: ${parsed.name}` : 'الاسم: غير محدد',
                parsed.price != null ? `السعر: ${parsed.price} ر.ي / ${parsed.saleUnit || 'قطعة'}` : 'السعر: غير محدد',
                parsed.stock != null ? `المخزون: ${parsed.stock} ${parsed.saleUnit || 'قطعة'}` : 'المخزون: غير محدد',
                '',
                'تم إنشاء مسودة آمنة داخل مركز التاجر. لن يتم نشر المنتج تلقائيًا إلا إذا كان الإعداد autoPublish مفعّلًا.',
              ].join('\\n');
              try {
                await sendWhatsAppText(from, summary);
              } catch (sendError) {
                await audit(connection.merchantUid, 'whatsapp.reply.failed', 'error', { importId: importRef.id, error: String(sendError.message || sendError) });
              }
            } else {
              try {
                await sendWhatsAppText(from, 'تم استلام رسالتك. رقم واتساب هذا غير مرتبط بمتجر معتمد بعد؛ سيظهر الطلب في مركز الإدارة لربطه بالمتجر الصحيح.');
              } catch (_) {}
            }
          }
        }
      }

      res.status(200).send('EVENT_RECEIVED');
    } catch (error) {
      await audit(null, 'whatsapp.webhook.error', 'error', { error: String(error.message || error) });
      res.status(200).send('EVENT_RECEIVED');
    }
  },
);

function assertStaff(request) {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const claims = auth.token || {};
  if (!(claims.owner === true || claims.admin === true || claims.role === 'owner' || claims.role === 'admin')) {
    throw new HttpsError('permission-denied', 'Administrator permission required.');
  }
  return auth;
}

exports.confirmWhatsAppProductImport = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: true,
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) throw new HttpsError('unauthenticated', 'Authentication required.');

    const importId = String(request.data?.importId || '').trim();
    if (!importId) throw new HttpsError('invalid-argument', 'importId is required.');

    const importRef = db.collection('whatsappProductImports').doc(importId);
    const importSnap = await importRef.get();
    if (!importSnap.exists) throw new HttpsError('not-found', 'WhatsApp product import not found.');

    const data = importSnap.data() || {};
    const claims = auth.token || {};
    const isStaff = claims.owner === true || claims.admin === true || claims.role === 'owner' || claims.role === 'admin';
    const isMerchant = claims.role === 'merchant' && data.merchantUid === auth.uid;
    if (!isStaff && !isMerchant) throw new HttpsError('permission-denied', 'You are not allowed to confirm this import.');

    if (data.status === 'published' && data.productId) return { ok: true, productId: data.productId };

    const parsed = data.parsed || {};
    const name = String(request.data?.name || parsed.name || '').trim();
    const price = Number(request.data?.price ?? parsed.price);
    const stock = Number(String(request.data?.stock ?? parsed.stock ?? 0));
    const saleUnit = String(request.data?.saleUnit || parsed.saleUnit || 'piece');
    const unitScale = { piece:1, kg:1000, g:1, l:1000, ml:1, m:1 }[saleUnit] || 1;
    const step = Number(request.data?.step ?? parsed.step ?? 1);
    const minOrder = Number(request.data?.minOrder ?? parsed.minOrder ?? step);
    const storeId = String(request.data?.storeId || data.storeId || '').trim();

    if (!name) throw new HttpsError('invalid-argument', 'Product name is required.');
    if (!Number.isFinite(price) || price < 0 || price > 100000000) throw new HttpsError('invalid-argument', 'Valid product price is required.');
    if (!Number.isFinite(stock) || stock < 0 || stock > 100000000) throw new HttpsError('invalid-argument', 'Valid stock is required.');
    if (!['piece','kg','g','l','ml','m'].includes(saleUnit) || !Number.isFinite(step) || step <= 0 || !Number.isFinite(minOrder) || minOrder <= 0) throw new HttpsError('invalid-argument', 'Invalid product unit settings.');
    if (!storeId) throw new HttpsError('failed-precondition', 'This WhatsApp number is not linked to a store.');

    const storeSnap = await db.collection('stores').doc(storeId).get();
    if (!storeSnap.exists) throw new HttpsError('not-found', 'Store not found.');
    const store = storeSnap.data() || {};
    if (!isStaff && store.ownerId !== auth.uid) throw new HttpsError('permission-denied', 'Store ownership mismatch.');

    const productRef = db.collection('products').doc();
    const publish = request.data?.publish === true && (isStaff || data.autoPublish === true);

    await productRef.set({
      name,
      price,
      stock,
      stockBase: Math.round(stock * unitScale),
      saleUnit,
      unitScale,
      baseUnit: ['kg','g'].includes(saleUnit) ? 'g' : (['kg','g'].includes(saleUnit) ? 'g' : (['l','ml'].includes(saleUnit) ? 'ml' : saleUnit)),
      stepBase: Math.round(step * unitScale),
      minOrderBase: Math.round(minOrder * unitScale),
      storeId,
      ownerId: store.ownerId || data.merchantUid || auth.uid,
      status: publish ? 'active' : 'draft',
      source: 'whatsapp',
      whatsappImportId: importId,
      imageMediaId: data.mediaId || null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await importRef.update({
      status: publish ? 'published' : 'draft_created',
      productId: productRef.id,
      confirmedBy: auth.uid,
      confirmedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await audit(auth.uid, 'whatsapp.product_import.confirmed', 'success', {
      importId,
      productId: productRef.id,
      storeId,
      published: publish,
    });

    return { ok: true, productId: productRef.id, published: publish };
  },
);

exports.listWhatsAppProductImports = onCall(
  { region: 'us-central1', enforceAppCheck: true },
  async (request) => {
    const auth = assertStaff(request);
    const limit = Math.min(Math.max(Number(request.data?.limit || 50), 1), 100);
    const snap = await db.collection('whatsappProductImports').orderBy('createdAt', 'desc').limit(limit).get();
    return {
      imports: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      actorUid: auth.uid,
    };
  },
);


exports.setWhatsAppConnection = onCall(
  { region: 'us-central1', enforceAppCheck: true },
  async (request) => {
    const auth = assertStaff(request);
    const phone = normalizePhone(request.data?.phone);
    const storeId = String(request.data?.storeId || '').trim();
    const merchantUid = String(request.data?.merchantUid || '').trim();
    const autoPublish = request.data?.autoPublish === true;

    if (!/^([0-9]{8,15})$/.test(phone)) throw new HttpsError('invalid-argument', 'A valid WhatsApp phone number is required.');
    if (!storeId || !merchantUid) throw new HttpsError('invalid-argument', 'storeId and merchantUid are required.');

    const storeSnap = await db.collection('stores').doc(storeId).get();
    if (!storeSnap.exists) throw new HttpsError('not-found', 'Store not found.');
    const store = storeSnap.data() || {};
    if (store.ownerId !== merchantUid) throw new HttpsError('failed-precondition', 'merchantUid must own the selected store.');

    await db.collection('whatsappConnections').doc(phone).set({
      phone,
      storeId,
      merchantUid,
      autoPublish,
      enabled: true,
      updatedBy: auth.uid,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    await audit(auth.uid, 'whatsapp.connection.updated', 'success', { phone, storeId, merchantUid, autoPublish });
    return { ok: true, phone, storeId, merchantUid, autoPublish };
  },
);

exports.listWhatsAppConnections = onCall(
  { region: 'us-central1', enforceAppCheck: true },
  async (request) => {
    assertStaff(request);
    const snap = await db.collection('whatsappConnections').orderBy('updatedAt', 'desc').limit(100).get();
    return { connections: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
  },
);
