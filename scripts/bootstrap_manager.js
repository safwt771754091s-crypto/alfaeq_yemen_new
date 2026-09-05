const admin = require('firebase-admin');

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const name = process.env.ADMIN_NAME || 'المدير العام - الفائق يمن';

if (!email || !password) {
  console.error('ADMIN_EMAIL و ADMIN_PASSWORD مطلوبان. لا تضع كلمة المرور داخل Git.');
  process.exit(1);
}

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

(async () => {
  let user;
  try {
    user = await auth.getUserByEmail(email);
    user = await auth.updateUser(user.uid, { password, displayName: name, emailVerified: true, disabled: false });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    user = await auth.createUser({ email, password, displayName: name, emailVerified: true, disabled: false });
  }

  await auth.setCustomUserClaims(user.uid, { role: 'admin' });
  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    name,
    email,
    role: 'admin',
    active: true,
    approved: true,
    emailVerified: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log(`Manager ready: ${email}`);
  console.log('Role: admin');
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
