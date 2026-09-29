import "jsr:@supabase/supabase-js@2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ ok: false, error: "server_configuration_missing" }, 500);
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return json({ ok: false, error: "authentication_required" }, 401);
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const token = auth.slice(7).trim();
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ ok: false, error: "invalid_session" }, 401);
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") return json({ ok: false, error: "invalid_json" }, 400);
  const eventId = String(body.eventId ?? "").trim();
  const source = String(body.source ?? "alfaeq_yemen_new").trim();
  const eventType = String(body.eventType ?? "").trim();
  const version = Number(body.version ?? 1);
  const occurredAt = String(body.occurredAt ?? new Date().toISOString());
  const data = body.data && typeof body.data === "object" ? body.data : {};
  if (!eventId || !eventType) return json({ ok: false, error: "event_id_and_type_required" }, 400);
  if (!Number.isInteger(version) || version < 1) return json({ ok: false, error: "invalid_version" }, 400);
  if (!/^[a-z0-9_]+(?:\.[a-z0-9_]+)+$/i.test(eventType)) return json({ ok: false, error: "invalid_event_type" }, 400);
  if (Number.isNaN(Date.parse(occurredAt))) return json({ ok: false, error: "invalid_occurred_at" }, 400);
  const { data: accepted, error } = await admin.rpc("accept_automation_event", {
    p_event_id: eventId, p_source: source, p_version: version, p_event_type: eventType,
    p_occurred_at: occurredAt, p_data: data,
  });
  if (error) return json({ ok: false, error: "event_accept_failed", detail: error.message }, 500);
  const result = Array.isArray(accepted) ? accepted[0] : accepted;
  return json({ ok: true, actorUid: userData.user.id, eventId, eventType, accepted: Boolean(result?.accepted), duplicate: Boolean(result?.duplicate) });
});
function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function createClient(url: string, key: string, options: Record<string, unknown>) {
  return (globalThis as any).SupabaseClient ? new (globalThis as any).SupabaseClient(url, key, options) : null;
}