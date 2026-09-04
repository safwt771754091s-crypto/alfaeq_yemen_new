const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret, defineString } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const crypto = require('crypto');

initializeApp();
const db = getFirestore();

const WHATSAPP_ACCESS_TOKEN = defineSecret('WHATSAPP_ACCESS_TOKEN');
const WHATSAPP_PHONE_NUMBER_ID = defineSecret('WHATSAPP_PHONE_NUMBER_ID');
const WHATSAPP_OTP_TEMPLATE = defineString('WHATSAPP_OTP_TEMPLATE', { default: 'alfaeq_otp' });
const WHATSAPP_OTP_LANGUAGE = defineString('WHATSAPP_OTP_LANGUAGE', { default: 'ar' });

const OTP_TTL_MS = 5 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const RESEND_DELAY_MS = 60 * 1000;

function cleanPhone(value) {
  return String(value || '').replace(/[^0-9+]/g, '');
}

async function verifyBearer(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) throw new Error('UNAUTHENTICATED');
  return getAuth().verifyIdToken(header.substring(7));
}

async function sendWhatsAppTemplate(phone, code) {
  const token = WHATSAPP_ACCESS_TOKEN.value();
  const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
  const templateName = WHATSAPP_OTP_TEMPLATE.value();
  const language = WHATSAPP_OTP_LANGUAGE.value();

  const response = await fetch(`https://graph.facebook.com/v23.0/${phoneNumberId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: phone.replace('+', ''),
      type: 'template',
      template: {
        name: templateName,
        language: { code: language },
        components: [
          {
            type: 'body',
            parameters: [{ type: 'text', text: code }],
          },
        ],
      },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    console.error('WhatsApp API error:', response.status, body);
    throw new Error('WHATSAPP_SEND_FAILED');
  }
}

exports.whatsappOtp = onRequest({
  region: 'me-central2',
  secrets: [WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID],
}, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });

  try {
    const decoded = await verifyBearer(req);
    const action = req.body?.action;
    const phone = cleanPhone(req.body?.phone);
    if (!phone || phone.length < 8) return res.status(400).json({ error: 'INVALID_PHONE' });

    const docRef = db.collection('whatsappOtp').doc(decoded.uid);
    const current = await docRef.get();

    if (action === 'request') {
      if (current.exists) {
        const data = current.data();
        const lastSent = data?.lastSentAt?.toMillis?.() || 0;
        if (Date.now() - lastSent < RESEND_DELAY_MS) {
          return res.status(429).json({ error: 'TOO_MANY_REQUESTS' });
        }
      }

      const code = String(crypto.randomInt(100000, 1000000));
      const codeHash = crypto.createHash('sha256').update(code).digest('hex');
      const expiresAt = Timestamp.fromMillis(Date.now() + OTP_TTL_MS);

      await sendWhatsAppTemplate(phone, code);
      await docRef.set({
        uid: decoded.uid,
        phone,
        codeHash,
        expiresAt,
        attempts: 0,
        lastSentAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });

      return res.status(200).json({ ok: true });
    }

    if (action === 'verify') {
      if (!current.exists) return res.status(400).json({ error: 'OTP_NOT_FOUND' });
      const data = current.data();
      if (data.phone !== phone) return res.status(400).json({ error: 'PHONE_MISMATCH' });
      if (data.attempts >= MAX_ATTEMPTS) return res.status(429).json({ error: 'TOO_MANY_ATTEMPTS' });
      if (!data.expiresAt || data.expiresAt.toMillis() < Date.now()) return res.status(400).json({ error: 'OTP_EXPIRED' });

      const code = String(req.body?.code || '');
      const hash = crypto.createHash('sha256').update(code).digest('hex');
      if (hash !== data.codeHash) {
        await docRef.update({ attempts: FieldValue.increment(1) });
        return res.status(400).json({ error: 'INVALID_OTP' });
      }

      await getAuth().setCustomUserClaims(decoded.uid, { whatsappVerified: true });
      await db.collection('users').doc(decoded.uid).set({
        phone,
        whatsappVerified: true,
        whatsappVerifiedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      await docRef.delete();
      return res.status(200).json({ ok: true });
    }

    return res.status(400).json({ error: 'INVALID_ACTION' });
  } catch (error) {
    console.error(error);
    const status = error.message === 'UNAUTHENTICATED' ? 401 : 500;
    return res.status(status).json({ error: status === 401 ? 'UNAUTHENTICATED' : error.message || 'INTERNAL_ERROR' });
  }
});
