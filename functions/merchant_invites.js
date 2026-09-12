const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getFirestore } = require('firebase-admin/firestore');

const db = getFirestore();
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function isStaff(request) {
  const token = request.auth?.token || {};
  return token.admin === true || token.owner === true || token.role === 'admin' || token.role === 'owner';
}

exports.createMerchantInvite = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول.');
  if (!isStaff(request)) throw new HttpsError('permission-denied', 'هذه العملية مخصصة للإدارة.');

  const rawLabel = request.data?.label;
  const label = typeof rawLabel === 'string' ? rawLabel.trim().slice(0, 120) : '';
  const token = crypto.randomBytes(32).toString('base64url');
  const tokenHash = hashToken(token);
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);

  await db.collection('merchantInvites').doc(tokenHash).set({
    tokenHash,
    label,
    status: 'active',
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    usedBy: null,
    usedAt: null,
  });

  const url = `https://alfaeq-yemen-fed37.web.app/?merchant_invite=${encodeURIComponent(token)}`;
  await db.collection('auditLogs').add({
    actorUid: request.auth.uid,
    action: 'merchant.invite.created',
    result: 'success',
    source: 'admin_merchant_invites',
    details: { label, expiresAt },
    createdAt: FieldValue.serverTimestamp(),
  });

  return { url, expiresAt: expiresAt.toMillis() };
});

exports.redeemMerchantInvite = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'يجب إنشاء الحساب وتسجيل الدخول أولاً.');
  const token = request.data?.token;
  if (typeof token !== 'string' || token.length < 20 || token.length > 200) {
    throw new HttpsError('invalid-argument', 'رابط دعوة التاجر غير صالح.');
  }

  const tokenHash = hashToken(token);
  const inviteRef = db.collection('merchantInvites').doc(tokenHash);

  const result = await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    if (!inviteSnap.exists) throw new HttpsError('not-found', 'رابط الدعوة غير موجود أو انتهت صلاحيته.');
    const invite = inviteSnap.data() || {};
    if (invite.status !== 'active') throw new HttpsError('failed-precondition', 'تم استخدام رابط الدعوة مسبقاً.');
    if (!invite.expiresAt || invite.expiresAt.toMillis() < Date.now()) {
      tx.update(inviteRef, { status: 'expired', updatedAt: FieldValue.serverTimestamp() });
      throw new HttpsError('deadline-exceeded', 'انتهت صلاحية رابط الدعوة.');
    }

    const userRef = db.collection('users').doc(request.auth.uid);
    const userSnap = await tx.get(userRef);
    const user = userSnap.data() || {};
    const currentRole = user.role || request.auth.token.role || 'customer';
    if (['admin', 'owner', 'developer'].includes(currentRole)) {
      throw new HttpsError('failed-precondition', 'هذا الحساب لديه صلاحية إدارية بالفعل.');
    }

    tx.set(userRef, {
      uid: request.auth.uid,
      email: request.auth.token.email || user.email || null,
      name: user.name || request.auth.token.name || '',
      role: 'merchant',
      merchantStatus: 'active',
      merchantInviteId: tokenHash,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.update(inviteRef, {
      status: 'redeemed',
      usedBy: request.auth.uid,
      usedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { label: invite.label || '' };
  });

  await getAuth().setCustomUserClaims(request.auth.uid, { role: 'merchant', merchant: true });
  await db.collection('auditLogs').add({
    actorUid: request.auth.uid,
    action: 'merchant.invite.redeemed',
    result: 'success',
    source: 'merchant_invite',
    details: { inviteId: tokenHash, label: result.label },
    createdAt: FieldValue.serverTimestamp(),
  });

  return { success: true, role: 'merchant' };
});
