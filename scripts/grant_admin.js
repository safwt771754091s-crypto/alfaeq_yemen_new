// منح صلاحية المالك/الأدمن لمستخدم في مشروع الفائق يمن.
// يُشغَّل من GitHub Actions عبر workflow: .github/workflows/grant_admin.yml
// يعتمد على المتغيرات: FIREBASE_SERVICE_ACCOUNT_JSON, TARGET_EMAIL, TARGET_ROLE

const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');

function fail(message) {
  console.error(message);
  process.exit(1);
}

const rawCreds = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!rawCreds) fail('FIREBASE_SERVICE_ACCOUNT_JSON secret is missing.');

let creds;
try {
  creds = JSON.parse(rawCreds);
} catch (err) {
  fail('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON.');
}

const email = String(process.env.TARGET_EMAIL || '').trim().toLowerCase();
const role = String(process.env.TARGET_ROLE || 'owner').trim();
const allowedRoles = ['owner', 'admin', 'developer', 'vendor', 'driver', 'customer'];

if (!email) fail('TARGET_EMAIL is required.');
if (!allowedRoles.includes(role)) fail(`TARGET_ROLE must be one of: ${allowedRoles.join(', ')}`);

admin.initializeApp({
  credential: admin.credential.cert(creds),
  projectId: creds.project_id,
});

function claimsFor(targetRole) {
  const claims = { role: targetRole };
  if (targetRole === 'owner') {
    claims.owner = true;
    claims.admin = true;
  } else if (targetRole === 'admin') {
    claims.admin = true;
  }
  return claims;
}

async function resolveUser() {
  try {
    return { user: await admin.auth().getUserByEmail(email), created: false };
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
    const password = crypto.randomBytes(24).toString('base64url');
    const user = await admin.auth().createUser({
      email,
      password,
      emailVerified: true,
      displayName: 'مالك المنصة',
    });
    return { user, created: true };
  }
}

(async () => {
  const { user, created } = await resolveUser();
  const claims = claimsFor(role);

  await admin.auth().setCustomUserClaims(user.uid, claims);
  await admin.auth().revokeRefreshTokens(user.uid);

  await admin.firestore().collection('users').doc(user.uid).set(
    {
      uid: user.uid,
      email,
      role,
      name: user.displayName || 'مالك المنصة',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(created ? { createdAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
    },
    { merge: true },
  );

  let resetLink = null;
  try {
    resetLink = await admin.auth().generatePasswordResetLink(email);
  } catch (err) {
    console.log('Could not generate a password reset link:', err.message);
  }

  const lines = [
    '## صلاحية الدخول',
    '',
    `- البريد: \`${email}\``,
    `- المعرّف (UID): \`${user.uid}\``,
    `- الدور: \`${role}\``,
    `- المطالبات (claims): \`${JSON.stringify(claims)}\``,
    `- الحساب: ${created ? 'أُنشئ الآن' : 'كان موجوداً وتمت ترقيته'}`,
    '',
    resetLink
      ? `### رابط تعيين كلمة المرور\n\n${resetLink}\n\nافتح الرابط، عيّن كلمة مرور، ثم سجّل الدخول بالبريد أعلاه.`
      : '> تعذّر توليد رابط تعيين كلمة المرور — استخدم "نسيت كلمة المرور" داخل التطبيق.',
    '',
    '> بعد تسجيل الدخول سجّل خروج ثم دخول مرة واحدة حتى يلتقط التطبيق المطالبات الجديدة.',
  ];

  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n');
  }

  console.log(`Granted "${role}" to ${email} (uid: ${user.uid}).`);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
