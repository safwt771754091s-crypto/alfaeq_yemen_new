const { beforeUserCreated, beforeUserSignedIn } = require('firebase-functions/v2/identity');

/**
 * Supabase third-party Auth bridge.
 *
 * Supabase needs Firebase tokens to carry the standard Postgres
 * `authenticated` role. Application authorization remains in the
 * dedicated admin/owner/developer claims and the users profile.
 */
function supabaseAuthClaims(event) {
  const existing = event?.data?.customClaims || {};
  return {
    customClaims: {
      ...existing,
      role: 'authenticated',
    },
  };
}

exports.setSupabaseAuthenticatedRoleOnCreate = beforeUserCreated(
  { region: 'us-central1' },
  (event) => supabaseAuthClaims(event),
);

exports.setSupabaseAuthenticatedRoleOnSignIn = beforeUserSignedIn(
  { region: 'us-central1' },
  (event) => supabaseAuthClaims(event),
);
