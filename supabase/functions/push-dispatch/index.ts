// push-dispatch — fans a notification out to a user's registered devices.
//
// Called by a database trigger (pg_net) with an HMAC signature, never by
// clients. Delivers via FCM HTTP v1 when configured; otherwise it is a no-op
// that still returns 200 so the database trigger never retries/blocks.
//
// Secrets:
//   PUSH_DISPATCH_SECRET      shared secret matching private.push_dispatch_config.secret
//   FCM_SERVICE_ACCOUNT_JSON  Firebase service-account JSON (HTTP v1)
//   FCM_PROJECT_ID            optional override (else read from the JSON)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PUSH_DISPATCH_SECRET = Deno.env.get("PUSH_DISPATCH_SECRET") ?? "";
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
const FCM_PROJECT_ID_ENV = Deno.env.get("FCM_PROJECT_ID") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-alfaeq-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

let cachedToken: { value: string; expiresAt: number } | null = null;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  const raw = await req.text();
  const signature = req.headers.get("x-alfaeq-signature") ?? "";
  if (!PUSH_DISPATCH_SECRET) return json({ ok: true, skipped: "push_not_configured" });
  if (!(await verifySignature(raw, signature, PUSH_DISPATCH_SECRET))) {
    return json({ ok: false, error: "invalid_signature" }, 401);
  }

  const body = safeJson(raw);
  if (!body) return json({ ok: false, error: "invalid_json" }, 400);
  const userId = String(body.userId ?? "").trim();
  if (!userId) return json({ ok: false, error: "user_id_required" }, 400);

  if (!FCM_SERVICE_ACCOUNT_JSON) return json({ ok: true, skipped: "fcm_not_configured" });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ ok: false, error: "server_configuration_missing" }, 500);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", userId);
  if (!tokens || tokens.length === 0) return json({ ok: true, sent: 0 });

  const accessToken = await fcmAccessToken();
  const data = body.data && typeof body.data === "object" ? body.data : {};
  let sent = 0;
  const stale: string[] = [];

  for (const row of tokens) {
    const token = String(row.token ?? "");
    if (!token) continue;
    const result = await sendFcm(accessToken, token, {
      title: String(body.title ?? "الفائق يمن"),
      body: String(body.body ?? ""),
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    });
    if (result.ok) sent++;
    else if (result.unregistered) stale.push(token);
  }

  if (stale.length) await admin.from("device_tokens").delete().in("token", stale);
  return json({ ok: true, sent, removed: stale.length });
});

async function fcmAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const sa = JSON.parse(FCM_SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${b64urlBytes(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`fcm_auth_failed: ${data?.error_description ?? res.status}`);
  cachedToken = { value: data.access_token, expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000 };
  return cachedToken.value;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
}

async function sendFcm(accessToken: string, token: string, msg: { title: string; body: string; data: Record<string, string> }) {
  const projectId = FCM_PROJECT_ID_ENV || (JSON.parse(FCM_SERVICE_ACCOUNT_JSON).project_id ?? "");
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: msg.title, body: msg.body },
        data: msg.data,
        android: { priority: "HIGH" },
        apns: { payload: { aps: { sound: "default" } } },
      },
    }),
  });
  if (res.ok) return { ok: true, unregistered: false };
  const detail = await res.json().catch(() => ({}));
  const status = detail?.error?.status ?? "";
  return { ok: false, unregistered: status === "NOT_FOUND" || status === "UNREGISTERED" };
}

async function verifySignature(payload: string, signature: string, secret: string): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const digest = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (digest.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < digest.length; i++) diff |= digest.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

function b64url(text: string): string {
  return b64urlBytes(new TextEncoder().encode(text));
}

function b64urlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function safeJson(text: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" ? value : null;
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
