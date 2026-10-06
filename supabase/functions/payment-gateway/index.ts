// payment-gateway — provider-agnostic online payments for the super-app.
//
// Actions (all authenticated):
//   { action: "create_intent", orderId }        -> { provider, clientSecret?|approveUrl?, ... }
//   { action: "confirm", orderId, providerRef } -> { status: "paid"|"pending", ... }
//
// Providers: `manual` (staff/settlement stub), `stripe`, `paypal`.
// A provider is "enabled" only when its secret is present, so the app degrades
// cleanly: it always offers wallet / cash-on-delivery, and shows the online
// option only when the backend reports a provider is configured.
//
// Secrets (set with `supabase secrets set`):
//   STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
//   PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_API_BASE (optional)
//   PAYMENT_ENABLED_PROVIDERS (optional CSV override, e.g. "stripe,paypal")

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
const PAYPAL_CLIENT_ID = Deno.env.get("PAYPAL_CLIENT_ID") ?? "";
const PAYPAL_CLIENT_SECRET = Deno.env.get("PAYPAL_CLIENT_SECRET") ?? "";
const PAYPAL_API_BASE = Deno.env.get("PAYPAL_API_BASE") ?? "https://api-m.paypal.com";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function enabledProviders(): string[] {
  const override = (Deno.env.get("PAYMENT_ENABLED_PROVIDERS") ?? "")
    .split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (override.length) return override;
  const providers = ["manual"];
  if (STRIPE_SECRET_KEY) providers.push("stripe");
  if (PAYPAL_CLIENT_ID && PAYPAL_CLIENT_SECRET) providers.push("paypal");
  return providers;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ ok: false, error: "server_configuration_missing" }, 500);

  const raw = await req.text();
  const stripeSignature = req.headers.get("stripe-signature");

  // Stripe webhooks are unauthenticated but HMAC-signed.
  if (stripeSignature) return handleStripeWebhook(raw, stripeSignature);

  const parsed = safeJson(raw);
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return json({ ok: false, error: "authentication_required" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7).trim());
  if (userError || !userData.user) return json({ ok: false, error: "invalid_session" }, 401);
  const uid = userData.user.id;

  if (!parsed || typeof parsed !== "object") return json({ ok: false, error: "invalid_json" }, 400);
  const action = String(parsed.action ?? "").trim();

  try {
    if (action === "providers") return json({ ok: true, enabledProviders: enabledProviders() });
    if (action === "create_intent") return await createIntent(admin, uid, parsed);
    if (action === "confirm") return await confirmPayment(admin, uid, parsed);
    return json({ ok: false, error: "unknown_action", enabledProviders: enabledProviders() }, 400);
  } catch (e) {
    return json({ ok: false, error: "payment_gateway_error", detail: String(e) }, 500);
  }
});

async function createIntent(admin: SupabaseClient, uid: string, body: Record<string, unknown>) {
  const orderId = String(body.orderId ?? "").trim();
  if (!orderId) return json({ ok: false, error: "order_id_required" }, 400);

  const order = await loadOrder(admin, orderId);
  if (!order) return json({ ok: false, error: "order_not_found" }, 404);
  if (order.customer_id !== uid) return json({ ok: false, error: "forbidden" }, 403);
  if (order.metadata?.payment_status === "paid") return json({ ok: false, error: "already_paid" }, 409);

  const providers = enabledProviders();
  const requested = String(body.provider ?? "").trim().toLowerCase();
  const provider = requested || (providers.includes("stripe") ? "stripe" : providers.includes("paypal") ? "paypal" : "manual");
  if (!providers.includes(provider)) return json({ ok: false, error: "provider_not_enabled", provider, enabledProviders: providers }, 400);

  const amount = Number(order.total ?? 0);
  const currency = String(order.currency ?? "USD").toUpperCase();
  if (!(amount > 0)) return json({ ok: false, error: "invalid_order_total" }, 400);

  let result: Record<string, unknown>;
  if (provider === "stripe") result = await stripeCreateIntent(orderId, amount, currency, uid);
  else if (provider === "paypal") result = await paypalCreateOrder(orderId, amount, currency);
  else result = { provider: "manual", status: "pending", instructions: "manual_settlement" };

  if (result.providerRef) {
    await admin.rpc("attach_payment_provider", {
      p_order_id: orderId, p_provider: provider, p_provider_ref: result.providerRef,
    });
  }
  return json({ ok: true, orderId, amount, currency, ...result });
}

async function confirmPayment(admin: SupabaseClient, uid: string, body: Record<string, unknown>) {
  const orderId = String(body.orderId ?? "").trim();
  if (!orderId) return json({ ok: false, error: "order_id_required" }, 400);

  const order = await loadOrder(admin, orderId);
  if (!order) return json({ ok: false, error: "order_not_found" }, 404);
  if (order.customer_id !== uid) return json({ ok: false, error: "forbidden" }, 403);
  if (order.metadata?.payment_status === "paid") return json({ ok: true, status: "paid", orderId });

  const provider = String(body.provider ?? order.metadata?.payment_provider ?? "").toLowerCase();
  const providerRef = String(body.providerRef ?? order.metadata?.payment_provider_ref ?? "").trim();
  if (!providerRef) return json({ ok: false, error: "provider_ref_required" }, 400);

  const amount = Number(order.total ?? 0);
  const currency = String(order.currency ?? "USD").toUpperCase();

  let paid = false;
  let meta: Record<string, unknown> = { confirmed_via: "client_confirm" };
  if (provider === "stripe") {
    const intent = await stripeGetIntent(providerRef);
    paid = intent?.status === "succeeded";
    meta = { ...meta, stripe_status: intent?.status };
  } else if (provider === "paypal") {
    const capture = await paypalCapture(providerRef);
    paid = capture?.status === "COMPLETED";
    meta = { ...meta, paypal_status: capture?.status, capture_id: capture?.captureId };
  } else {
    return json({ ok: false, error: "provider_requires_webhook", provider }, 400);
  }

  if (!paid) return json({ ok: true, status: "pending", orderId, provider });

  await admin.rpc("mark_order_paid", {
    p_order_id: orderId, p_provider: provider, p_provider_ref: providerRef,
    p_amount: amount, p_currency: currency, p_metadata: meta,
  });
  return json({ ok: true, status: "paid", orderId, provider });
}

// ---------------------------------------------------------------- Stripe

async function stripeCreateIntent(orderId: string, amount: number, currency: string, uid: string) {
  const params = new URLSearchParams();
  params.set("amount", String(Math.round(amount * 100)));
  params.set("currency", currency.toLowerCase());
  params.set("automatic_payment_methods[enabled]", "true");
  params.set("metadata[order_id]", orderId);
  params.set("metadata[uid]", uid);

  const res = await fetch("https://api.stripe.com/v1/payment_intents", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`stripe_create_intent_failed: ${data?.error?.message ?? res.status}`);
  return { provider: "stripe", providerRef: data.id, clientSecret: data.client_secret };
}

async function stripeGetIntent(intentId: string) {
  const res = await fetch(`https://api.stripe.com/v1/payment_intents/${encodeURIComponent(intentId)}`, {
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
  });
  return res.ok ? await res.json() : null;
}

async function handleStripeWebhook(raw: string, signature: string) {
  try {
    const valid = await verifyStripeSignature(raw, signature, STRIPE_WEBHOOK_SECRET);
    if (!valid) return json({ ok: false, error: "invalid_signature" }, 400);
    const event = JSON.parse(raw);
    const type = String(event?.type ?? "");
    const intent = event?.data?.object ?? {};
    if (type === "payment_intent.succeeded" && intent?.metadata?.order_id) {
      const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      await admin.rpc("mark_order_paid", {
        p_order_id: String(intent.metadata.order_id),
        p_provider: "stripe",
        p_provider_ref: String(intent.id ?? ""),
        p_amount: Number(intent.amount ?? 0) / 100,
        p_currency: String(intent.currency ?? "usd").toUpperCase(),
        p_metadata: { stripe_event: type },
      });
    }
    return json({ ok: true, received: true });
  } catch (e) {
    return json({ ok: false, error: "webhook_failed", detail: String(e) }, 400);
  }
}

// Minimal HMAC-SHA256 verification of the `Stripe-Signature` header (t=...,v1=...).
async function verifyStripeSignature(payload: string, header: string, secret: string): Promise<boolean> {
  if (!secret) return false;
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=") as [string, string]));
  const timestamp = parts["t"];
  const expected = parts["v1"];
  if (!timestamp || !expected) return false;
  const signedPayload = `${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedPayload));
  const digest = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return timingSafeEqual(digest, expected);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------- PayPal

async function paypalToken(): Promise<string> {
  const basic = btoa(`${PAYPAL_CLIENT_ID}:${PAYPAL_CLIENT_SECRET}`);
  const res = await fetch(`${PAYPAL_API_BASE}/v1/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`paypal_auth_failed: ${data?.error_description ?? res.status}`);
  return data.access_token;
}

async function paypalCreateOrder(orderId: string, amount: number, currency: string) {
  const token = await paypalToken();
  const res = await fetch(`${PAYPAL_API_BASE}/v2/checkout/orders`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      intent: "CAPTURE",
      purchase_units: [{ reference_id: orderId, amount: { currency_code: currency, value: amount.toFixed(2) } }],
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`paypal_create_order_failed: ${data?.message ?? res.status}`);
  const approveUrl = (data.links ?? []).find((l: { rel: string }) => l.rel === "approve")?.href ?? null;
  return { provider: "paypal", providerRef: data.id, approveUrl };
}

async function paypalCapture(paypalOrderId: string) {
  const token = await paypalToken();
  const res = await fetch(`${PAYPAL_API_BASE}/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  });
  const data = await res.json();
  if (!res.ok) return null;
  const captureId = data?.purchase_units?.[0]?.payments?.captures?.[0]?.id;
  return { status: data?.status, captureId };
}

// ---------------------------------------------------------------- helpers

async function loadOrder(admin: SupabaseClient, orderId: string) {
  const { data } = await admin.from("orders")
    .select("id, customer_id, total, currency, payment_method, metadata")
    .eq("id", orderId).maybeSingle();
  return data;
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

// deno-lint-ignore no-explicit-any
type SupabaseClient = ReturnType<typeof createClient<any>>;
