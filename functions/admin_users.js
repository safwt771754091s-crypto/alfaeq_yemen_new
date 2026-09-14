const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();
const ALLOWED_ROLES = new Set(['owner', 'admin', 'developer', 'finance', 'merchant', 'driver', 'customer']);

function assertStaff(request) {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const claims = auth.token || {};
  if (!(claims.owner === true || claims.admin === true || claims.role === 'owner' || claims.role === 'admin')) {
    throw new HttpsError('permission-denied', 'Administrator permission required.');
  }
  return auth;
}

function assertOwner(request) {
  const auth = assertStaff(request);
  const claims = auth.token || {};
  if (!(claims.owner === true || claims.role === 'owner')) {
    throw new HttpsError('permission-denied', 'Owner permission required for this operation.');
  }
  return auth;
}

async function audit(actorUid, action, result, targetUid, details = {}) {
  await db.collection('auditLogs').add({
    actorUid,
    action,
    result,
    targetUid: targetUid || null,
    source: 'admin_user_management',
    ...details,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function claimsForRole(role) {
  const claims = { role };
  if (role === 'owner') claims.owner = true;
  if (role === 'admin') claims.admin = true;
  if (role === 'developer') claims.developer = true;
  return claims;
}

exports.listManagedUsers = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertStaff(request);
  const result = [];
  let pageToken;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      result.push({
        uid: user.uid,
        email: user.email || '',
        phoneNumber: user.phoneNumber || '',
        displayName: user.displayName || '',
        disabled: user.disabled,
        emailVerified: user.emailVerified,
        createdAt: user.metadata.creationTime || null,
        lastSignInAt: user.metadata.lastSignInTime || null,
        role: user.customClaims?.role || (user.customClaims?.owner ? 'owner' : user.customClaims?.admin ? 'admin' : ''),
        claims: user.customClaims || {},
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);

  await audit(auth.uid, 'admin.users.list', 'success', null, { count: result.length });
  return { users: result };
});

exports.setManagedUserRole = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  const role = request.data?.role;
  if (typeof uid !== 'string' || !uid || !ALLOWED_ROLES.has(role)) {
    throw new HttpsError('invalid-argument', 'Valid uid and role are required.');
  }
  if (uid === auth.uid && role !== 'owner') {
    throw new HttpsError('failed-precondition', 'The owner cannot remove their own owner role.');
  }

  const target = await getAuth().getUser(uid);
  const previousClaims = target.customClaims || {};
  const nextClaims = claimsForRole(role);
  await getAuth().setCustomUserClaims(uid, nextClaims);
  await db.collection('users').doc(uid).set({
    uid,
    role,
    roleUpdatedAt: FieldValue.serverTimestamp(),
    roleUpdatedBy: auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await audit(auth.uid, 'admin.users.role_changed', 'success', uid, {
    previousRole: previousClaims.role || null,
    newRole: role,
  });
  return { ok: true, uid, role, claims: nextClaims };
});

exports.setManagedUserDisabled = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  const disabled = request.data?.disabled;
  if (typeof uid !== 'string' || typeof disabled !== 'boolean') {
    throw new HttpsError('invalid-argument', 'uid and disabled are required.');
  }
  if (uid === auth.uid && disabled === true) {
    throw new HttpsError('failed-precondition', 'The owner cannot disable their own account.');
  }
  await getAuth().updateUser(uid, { disabled });
  await audit(auth.uid, 'admin.users.status_changed', 'success', uid, { disabled });
  return { ok: true, uid, disabled };
});

exports.revokeManagedUserSessions = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  if (typeof uid !== 'string' || !uid) throw new HttpsError('invalid-argument', 'uid is required.');
  await getAuth().revokeRefreshTokens(uid);
  await audit(auth.uid, 'admin.users.sessions_revoked', 'success', uid);
  return { ok: true, uid };
});

exports.refreshManagedUserClaims = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertStaff(request);
  const uid = request.data?.uid;
  if (typeof uid !== 'string' || !uid) throw new HttpsError('invalid-argument', 'uid is required.');
  const user = await getAuth().getUser(uid);
  const claims = user.customClaims || {};
  await getAuth().setCustomUserClaims(uid, claims);
  await audit(auth.uid, 'admin.users.claims_refreshed', 'success', uid);
  return { ok: true, uid, claims };
});
