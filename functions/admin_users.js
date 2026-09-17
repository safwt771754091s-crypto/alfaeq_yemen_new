const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

const db = getFirestore();
const ALLOWED_ROLES = new Set(['owner', 'admin', 'supervisor', 'developer', 'finance', 'merchant', 'driver', 'customer']);
const ALLOWED_PERMISSIONS = new Set([
  'manageMerchants',
  'approveMerchants',
  'manageProducts',
  'importProducts',
  'viewUsers',
  'developerCenter',
  'automation',
  'manageDispatch',
  'manageWallets',
]);
const PRIMARY_ADMIN_EMAIL = 'albyysks@gmail.com';

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
  await db.collection('auditLogs').add({ actorUid, action, result, targetUid: targetUid || null, source: 'admin_user_management', ...details, createdAt: FieldValue.serverTimestamp() });
}

function claimsForRole(role, permissions = []) {
  const claims = { role };
  if (role === 'owner') claims.owner = true;
  if (role === 'admin') claims.admin = true;
  if (role === 'supervisor') claims.supervisor = true;
  if (role === 'developer') claims.developer = true;
  if (permissions.length) claims.permissions = permissions;
  return claims;
}

exports.bootstrapPrimaryAdmin = onCall({ region: 'us-central1' }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const email = String(auth.token?.email || '').trim().toLowerCase();
  if (email !== PRIMARY_ADMIN_EMAIL) throw new HttpsError('permission-denied', 'This account is not the primary administrator account.');
  const user = await getAuth().getUser(auth.uid);
  if ((user.email || '').trim().toLowerCase() !== PRIMARY_ADMIN_EMAIL) throw new HttpsError('permission-denied', 'Authenticated account does not match the primary administrator.');
  const claims = { owner: true, admin: true, developer: true, role: 'owner', accessLevel: 10 };
  await getAuth().setCustomUserClaims(user.uid, claims);
  await db.collection('users').doc(user.uid).set({ uid: user.uid, email: PRIMARY_ADMIN_EMAIL, name: user.displayName || 'مدير منصة الفائق يمن', role: 'owner', admin: true, developer: true, accessLevel: 10, roleUpdatedAt: FieldValue.serverTimestamp(), roleUpdatedBy: 'primary_admin_bootstrap', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(user.uid, 'admin.primary_bootstrap', 'success', user.uid, { email: PRIMARY_ADMIN_EMAIL, role: 'owner', permissions: ['admin', 'developer'] });
  return { ok: true, uid: user.uid, role: 'owner', claims };
});

exports.listManagedUsers = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertStaff(request);
  const result = [];
  let pageToken;
  const presenceSnap = await db.collection('users').get();
  const presenceByUid = new Map();
  for (const doc of presenceSnap.docs) {
    const data = doc.data() || {};
    presenceByUid.set(doc.id, { isOnline: data.isOnline === true, lastSeen: data.lastSeen || null, profileName: data.name || data.displayName || '' });
  }
  const onlineCutoff = Date.now() - (2 * 60 * 1000);
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      const presence = presenceByUid.get(user.uid) || {};
      const lastSeen = presence.lastSeen;
      const lastSeenMillis = lastSeen instanceof Timestamp ? lastSeen.toMillis() : (lastSeen?.toMillis ? lastSeen.toMillis() : null);
      const isOnline = presence.isOnline === true && lastSeenMillis != null && lastSeenMillis >= onlineCutoff;
      result.push({ uid: user.uid, email: user.email || '', phoneNumber: user.phoneNumber || '', displayName: user.displayName || presence.profileName || '', disabled: user.disabled, emailVerified: user.emailVerified, createdAt: user.metadata.creationTime || null, lastSignInAt: user.metadata.lastSignInTime || null, lastSeen: lastSeenMillis != null ? new Date(lastSeenMillis).toISOString() : null, isOnline, role: user.customClaims?.role || (user.customClaims?.owner ? 'owner' : user.customClaims?.admin ? 'admin' : ''), claims: user.customClaims || {}, permissions: user.customClaims?.permissions || [] });
    }
    pageToken = page.pageToken;
  } while (pageToken);
  await audit(auth.uid, 'admin.users.list', 'success', null, { count: result.length });
  return {
    users: result,
    currentUser: {
      uid: auth.uid,
      role: auth.token?.role || (auth.token?.owner === true ? 'owner' : auth.token?.admin === true ? 'admin' : ''),
      owner: auth.token?.owner === true,
      admin: auth.token?.admin === true,
    },
  };
});

exports.setManagedUserRole = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  const role = request.data?.role;
  if (typeof uid !== 'string' || !uid || !ALLOWED_ROLES.has(role)) throw new HttpsError('invalid-argument', 'Valid uid and role are required.');
  if (uid === auth.uid && role !== 'owner') throw new HttpsError('failed-precondition', 'The owner cannot remove their own owner role.');
  const target = await getAuth().getUser(uid);
  const previousClaims = target.customClaims || {};
  const permissions = Array.isArray(previousClaims.permissions) ? previousClaims.permissions.filter((p) => ALLOWED_PERMISSIONS.has(p)) : [];
  const nextClaims = claimsForRole(role, role === 'supervisor' ? permissions : []);
  await getAuth().setCustomUserClaims(uid, nextClaims);
  await db.collection('users').doc(uid).set({ uid, role, permissions: nextClaims.permissions || [], roleUpdatedAt: FieldValue.serverTimestamp(), roleUpdatedBy: auth.uid, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(auth.uid, 'admin.users.role_changed', 'success', uid, { previousRole: previousClaims.role || null, newRole: role, permissions: nextClaims.permissions || [] });
  return { ok: true, uid, role, claims: nextClaims };
});

exports.setManagedUserPermissions = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  const rawPermissions = request.data?.permissions;
  if (typeof uid !== 'string' || !uid || !Array.isArray(rawPermissions)) throw new HttpsError('invalid-argument', 'uid and permissions are required.');
  if (uid === auth.uid) throw new HttpsError('failed-precondition', 'Owner permissions are managed by the owner role.');
  const permissions = [...new Set(rawPermissions.filter((p) => typeof p === 'string' && ALLOWED_PERMISSIONS.has(p)))];
  const target = await getAuth().getUser(uid);
  const role = target.customClaims?.role || 'customer';
  if (!['admin', 'supervisor'].includes(role)) throw new HttpsError('failed-precondition', 'Permissions can only be assigned to a manager or supervisor account.');
  const nextClaims = claimsForRole(role, permissions);
  await getAuth().setCustomUserClaims(uid, nextClaims);
  await db.collection('users').doc(uid).set({ permissions, permissionsUpdatedAt: FieldValue.serverTimestamp(), permissionsUpdatedBy: auth.uid, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(auth.uid, 'admin.users.permissions_changed', 'success', uid, { role, permissions });
  return { ok: true, uid, role, permissions };
});

exports.setManagedUserDisabled = onCall({ region: 'us-central1' }, async (request) => {
  const auth = assertOwner(request);
  const uid = request.data?.uid;
  const disabled = request.data?.disabled;
  if (typeof uid !== 'string' || typeof disabled !== 'boolean') throw new HttpsError('invalid-argument', 'uid and disabled are required.');
  if (uid === auth.uid && disabled === true) throw new HttpsError('failed-precondition', 'The owner cannot disable their own account.');
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
