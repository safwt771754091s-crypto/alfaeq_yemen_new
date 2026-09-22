const { beforeUserCreated, beforeUserSignedIn } = require('firebase-functions/v2/identity');

/**
 * Supabase third-party Auth bridge.
 *
 * Supabase needs Firebase tokens to carry the standard Postgres
 * `authenticated` role. Application authorization remains in the
 * dedicated admin/owner/developer claims and the users profile.
 */
function supabaseSessionClaims(event) {
  const existing = event?.data?.customClaims || {};
  const appRole = existing.app_role || existing.role || 'customer';
  return {
    sessionClaims: {
      role: 'authenticated',
      app_role: appRole,
      admin: existing.admin === true,
      owner: existing.owner === true,
      developer: existing.developer === true,
    },
  };
}

// Do not rewrite persistent Firebase custom claims at account creation.
// The bridge only adds the Supabase-compatible session claims at sign-in.
exports.setSupabaseAuthenticatedRoleOnCreate = beforeUserCreated(
  { region: 'us-central1' },
  () => undefined,
);

exports.setSupabaseAuthenticatedRoleOnSignIn = beforeUserSignedIn(
  { region: 'us-central1' },
  (event) => supabaseSessionClaims(event),
);
