// create-merchant-invite — mint a merchant onboarding link.
//
// Reimplemented (the deployed function had no source in the repo and hard-coded
// a dead `alfaeq-yemen.pages.dev` base). The base URL is resolved from, in
// order: an explicit `baseUrl` in the request, the `public_base_url` setting,
// the PUBLIC_APP_URL secret, then a safe default. Staff-only.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DEFAULT_BASE_URL = "https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/";
const INVITE_TTL_DAYS = 7;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ error: "server_configuration_missing" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return json({ error: "unauthenticated" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(authHeader.slice(7).trim());
  if (userError || !userData.user) return json({ error: "unauthenticated" }, 401);
  if (!isStaff(userData.user)) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const label = String(body?.label ?? "").trim().slice(0, 200);
  const baseUrl = await resolveBaseUrl(admin, body?.baseUrl);

  const token = mintToken();
  const tokenHash = await sha256Hex(token);
  const expiresAt = new Date(Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000);

  const { error: insertError } = await admin.from("merchant_invites").insert({
    token_hash: tokenHash,
    label: label || null,
    status: "active",
    created_by: userData.user.id,
    expires_at: expiresAt.toISOString(),
  });
  if (insertError) return json({ error: "invite_create_failed", detail: insertError.message }, 500);

  const url = `${baseUrl}?merchant_invite=${encodeURIComponent(token)}`;
  return json({ url, expiresAt: expiresAt.getTime(), label: label || null });
});

function isStaff(user: { app_metadata?: Record<string, unknown> }): boolean {
  const meta = user.app_metadata ?? {};
  return meta.app_role === "owner" || meta.app_role === "admin" || meta.app_role === "developer" ||
    meta.owner === true || meta.admin === true || meta.developer === true;
}

async function resolveBaseUrl(admin: ReturnType<typeof createClient>, requested: unknown): Promise<string> {
  const candidate = String(requested ?? "").trim();
  if (isHttpUrl(candidate)) return withTrailingSlash(candidate);

  const { data } = await admin.from("settings").select("value").eq("id", "public_base_url").maybeSingle();
  const configured = typeof data?.value === "string" ? data.value : (data?.value as { url?: string } | null)?.url;
  if (configured && isHttpUrl(configured)) return withTrailingSlash(configured);

  const env = Deno.env.get("PUBLIC_APP_URL") ?? "";
  if (isHttpUrl(env)) return withTrailingSlash(env);

  return DEFAULT_BASE_URL;
}

function isHttpUrl(value: string): boolean {
  if (!value) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:";
  } catch {
    return false;
  }
}

function withTrailingSlash(value: string): string {
  return value.endsWith("/") ? value : `${value}/`;
}

function mintToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
