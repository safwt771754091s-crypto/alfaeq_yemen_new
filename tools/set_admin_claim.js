const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'alfaeq-yemen-fed37';
if (!getApps().length) initializeApp({ projectId });

const auth = getAuth();
const db = getFirestore();

async function main() {
  const email = (process.argv[2] || '').trim().toLowerCase();
  const confirmation = (process.argv[3] || '').trim();

  if (!email || confirmation !== 'CONFIRM_ADMIN') {
    console.error('Usage: node tools/set_admin_claim.js <ADMIN_EMAIL> CONFIRM_ADMIN');
    process.exit(2);
  }

  const user = await auth.getUserByEmail(email);
  const existing = user.customClaims || {};
  const claims = {
    ...existing,
    admin: true,
    role: 'admin',
  };

  await auth.setCustomUserClaims(user.uid, claims);
  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    email: user.email,
    role: 'admin',
    admin: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.collection('auditLogs').add({
    actorUid: user.uid,
    actorEmail: user.email,
    role: 'admin',
    action: 'admin.claims.activated',
    result: 'success',
    source: 'secure_admin_bootstrap_script',
    details: { projectId },
    createdAt: FieldValue.serverTimestamp(),
  });

  console.log(`Admin role activated for ${user.email} (${user.uid}).`);
  console.log('The user must sign out/in again or refresh the ID token before the new claims are visible in the app.');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
