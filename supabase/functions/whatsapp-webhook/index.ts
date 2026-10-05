// WhatsApp Cloud API webhook for Alfaeq Yemen.
//
// GET  : Meta verification handshake (hub.verify_token == WHATSAPP_VERIFY_TOKEN).
// POST : inbound merchant messages. Each message is ingested, parsed with the
//        platform AI, and either auto-published or held for confirmation. A
//        short acknowledgement is queued back to the sender.
//
// All secrets are read from Supabase Vault; nothing is exposed to the client.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ?? "").replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const AI_MODEL = Deno.env.get("AI_MODEL") ?? "gemini-flash-lite-latest";

type Admin = ReturnType<typeof createClient>;

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  if (req.method === "GET") return verify(url);

  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ ok: false, error: "server_configuration_missing" }, 500);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });

  const config = await loadConfig(admin);
  if (!config.verifyToken) return json({ ok: false, error: "whatsapp_not_configured" }, 503);

  const raw = await req.text();
  if (!(await authorize(req, url, raw, config))) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const body = safeJson(raw);
  if (!body) return json({ ok: false, error: "invalid_json" }, 400);

  if (Array.isArray(body.statuses) && !Array.isArray(body.messages)) {
    return json({ ok: true, statuses: body.statuses.length });
  }

  const messages = Array.isArray(body.messages) ? body.messages : [];
  let processed = 0;
  const results: Array<Record<string, unknown>> = [];

  for (const msg of messages) {
    if (msg?.type !== "text" || !msg?.text?.body) continue;
    const from = String(msg.from ?? "");
    const text = String(msg.text.body ?? "").slice(0, 4000);
    if (!from || !text.trim()) continue;

    try {
      const ingested = await ingest(admin, from, text, msg);
      if (!ingested?.import_id) continue;

      const parsed = await parseProduct(text);
      await admin.rpc("whatsapp_set_import_parsed", { p_import_id: ingested.import_id, p_parsed: parsed });

      const autoPublish = ingested.auto_publish === true;
      const storeId = await firstStoreId(admin, ingested.merchant_uid);
      if (autoPublish && storeId && Number(parsed.price) > 0) {
        await admin.rpc("confirm_whatsapp_import", {
          p_import_id: ingested.import_id,
          p_name: parsed.name ?? "صنف واتساب",
          p_price: Number(parsed.price) || 0,
          p_stock: Number(parsed.stock) || 0,
          p_publish: true,
          p_section_id: parsed.section_id ?? "markets",
          p_store_id: storeId,
        });
      }

      const reply = autoPublish
        ? `✅ تم استلام منتجك ونشره على المنصة:\n${parsed.name ?? ""} — ${parsed.price ?? 0} USD`
        : `✅ تم استلام منتجك من الفائق يمن وسيُراجع قبل النشر:\n${parsed.name ?? ""} — ${parsed.price ?? 0} USD`;
      await admin.rpc("whatsapp_enqueue_message", {
        p_to_phone: from,
        p_body: reply,
        p_role: "merchant",
        p_metadata: { import_id: ingested.import_id, auto_publish: autoPublish },
      });

      processed++;
      results.push({ import_id: ingested.import_id, auto_publish: autoPublish, parsed });
    } catch (error) {
      results.push({ from, error: String(error).slice(0, 300) });
    }
  }

  try { await admin.rpc("whatsapp_dispatch", { p_limit: 20 }); } catch { /* cron retries */ }

  return json({ ok: true, processed, results });
});

async function verify(url: URL) {
  const mode = url.searchParams.get("hub.mode");
  const token = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge") ?? "";
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const config = await loadConfig(admin);
  if (mode === "subscribe" && token && config.verifyToken && token === config.verifyToken) {
    return new Response(challenge, { status: 200, headers: { "Content-Type": "text/plain" } });
  }
  return json({ ok: false, error: "verification_failed" }, 403);
}

async function loadConfig(admin: Admin) {
  const { data: endpoint } = await admin
    .from("automation_endpoints")
    .select("shared_secret")
    .eq("id", "whatsapp")
    .maybeSingle();
  const { data: secret } = await admin.rpc("get_whatsapp_config");
  const cfg = (secret ?? {}) as Record<string, string>;
  return {
    verifyToken: cfg.verify_token ?? null,
    appSecret: cfg.app_secret ?? null,
    fallbackSecret: (endpoint?.shared_secret as string | undefined) ?? null,
  };
}

async function authorize(
  req: Request,
  url: URL,
  raw: string,
  config: { appSecret: string | null; fallbackSecret: string | null; verifyToken: string | null },
): Promise<boolean> {
  const signature = req.headers.get("x-hub-signature-256") ?? "";
  if (config.appSecret && signature) {
    const expected = await hmacHex(config.appSecret, raw);
    if (timingSafeEqual(signature, `sha256=${expected}`)) return true;
  }
  const provided = url.searchParams.get("secret") ?? req.headers.get("x-alfaeq-automation-secret") ?? "";
  if (config.fallbackSecret && provided && timingSafeEqual(provided, config.fallbackSecret)) return true;
  if (!config.appSecret) return true;
  return false;
}

async function ingest(admin: Admin, from: string, text: string, msg: unknown) {
  const { data, error } = await admin.rpc("whatsapp_ingest_message", {
    p_phone: from,
    p_message: text,
    p_payload: { wa_message_id: (msg as Record<string, unknown>)?.id ?? null, raw: msg },
  });
  if (error) throw error;
  return data as Record<string, unknown> | null;
}

async function firstStoreId(admin: Admin, merchantUid: unknown): Promise<string | null> {
  if (!merchantUid) return null;
  const { data } = await admin.from("stores").select("id").eq("owner_id", String(merchantUid)).limit(1).maybeSingle();
  return (data?.id as string | undefined) ?? null;
}

type ParsedProduct = { name?: string; price?: number; stock?: number; description?: string; barcode?: string; section_id?: string };

async function parseProduct(text: string): Promise<ParsedProduct> {
  if (!AI_BASE_URL || !AI_API_KEY) return heuristic(text);
  const prompt = [
    "أنت مساعد استخراج بيانات المنتجات لمتجر يمني.",
    "استخرج من رسالة التاجر: اسم المنتج، السعر (رقم)، الكمية/المخزون (رقم)، الوصف، الباركود إن وُجد.",
    "أعد النتيجة بصيغة JSON فقط بالمفاتيح: name, price, stock, description, barcode.",
    "رسالة التاجر:",
    text,
  ].join("\n");
  try {
    const res = await fetch(`${AI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${AI_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: AI_MODEL,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.1,
        max_tokens: 400,
        response_format: { type: "json_object" },
      }),
    });
    if (!res.ok) return heuristic(text);
    const payload = await res.json();
    const content = payload?.choices?.[0]?.message?.content ?? "";
    const parsed = safeJson(String(content).replace(/```json|```/g, "").trim());
    if (!parsed) return heuristic(text);
    return normalize(parsed, text);
  } catch {
    return heuristic(text);
  }
}

function heuristic(text: string): ParsedProduct {
  const priceMatch = text.match(/(?:سعر|price)\s*[:=]?\s*([0-9]+(?:[.,][0-9]+)?)/i) ?? text.match(/([0-9]+(?:[.,][0-9]+)?)\s*(?:دولار|ريال|ر\.?ي|ر\.?س|usd|yer|sar)/i);
  const stockMatch = text.match(/(?:كمية|مخزون|stock|qty)\s*[:=]?\s*([0-9]+)/i);
  const barcodeMatch = text.match(/(?:باركود|barcode)\s*[:=]?\s*([0-9]{6,})/i);
  const firstLine = text.split("\n").map((l) => l.trim()).filter(Boolean)[0] ?? "صنف واتساب";
  const name = firstLine.replace(/(?:سعر|price)\s*[:=]?\s*[0-9.,]+/i, "").trim() || "صنف واتساب";
  return {
    name,
    price: priceMatch ? Number(priceMatch[1].replace(",", ".")) : 0,
    stock: stockMatch ? Number(stockMatch[1]) : 0,
    description: text.slice(0, 500),
    barcode: barcodeMatch ? barcodeMatch[1] : undefined,
  };
}

function normalize(parsed: Record<string, unknown>, text: string): ParsedProduct {
  const num = (v: unknown) => {
    const n = Number(String(v ?? "").replace(/[^0-9.]/g, ""));
    return Number.isFinite(n) ? n : 0;
  };
  return {
    name: String(parsed.name ?? "").trim() || heuristic(text).name,
    price: num(parsed.price),
    stock: num(parsed.stock),
    description: String(parsed.description ?? text).slice(0, 500),
    barcode: parsed.barcode ? String(parsed.barcode) : undefined,
    section_id: typeof parsed.section_id === "string" ? parsed.section_id : undefined,
  };
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function safeJson(text: string): Record<string, any> | null {
  try { return JSON.parse(text); } catch { return null; }
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
