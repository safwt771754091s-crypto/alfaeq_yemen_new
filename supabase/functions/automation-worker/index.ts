import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WORKER_SECRET = Deno.env.get("ALFAEQ_AUTOMATION_WORKER_SECRET") ?? "";
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ ok: false, error: "method_not_allowed" }, { status: 405 });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return Response.json({ ok: false, error: "server_configuration_missing" }, { status: 500 });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: endpoint, error: endpointError } = await admin.from("automation_endpoints")
    .select("endpoint_url,shared_secret,enabled").eq("id", "n8n").maybeSingle();

  if (endpointError) return Response.json({ ok: false, error: "endpoint_lookup_failed", detail: endpointError.message }, { status: 500 });
  if (!endpoint?.enabled || !endpoint.endpoint_url || !endpoint.shared_secret) {
    return Response.json({ ok: true, processed: 0, state: "disabled" });
  }

  const internalSecret = req.headers.get("x-alfaeq-worker-secret") ?? "";
  let workerId = "automation-worker";
  if (WORKER_SECRET && internalSecret === WORKER_SECRET) workerId = "internal:n8n";
  else if (internalSecret && internalSecret === endpoint.shared_secret) workerId = "internal:db-trigger";
  else return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });

  const body = await req.json().catch(() => ({}));
  const requestedLimit = Number(body?.limit ?? 5);
  const limit = Number.isFinite(requestedLimit) ? Math.min(5, Math.max(1, Math.floor(requestedLimit))) : 5;
  const includeLegacy = body?.includeLegacy === true;

  const send = async (payload: Record<string, unknown>) => {
    const response = await fetch(endpoint.endpoint_url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-alfaeq-automation-secret": endpoint.shared_secret,
      },
      body: JSON.stringify(payload),
    });
    const responseText = await response.text();
    return { ok: response.ok, status: response.status, text: responseText };
  };

  let processed = 0, failed = 0, claimed = 0;
  const errors: Array<{eventId:string; status?:number; detail:string}> = [];

  // New durable ingress path.
  const { data: inboxRows, error: inboxError } = await admin.from("automation_event_inbox")
    .select("*").eq("status", "received").lte("available_at", new Date().toISOString()).lt("attempts", 10)
    .order("available_at", { ascending: true }).order("received_at", { ascending: true }).limit(Math.ceil(limit / 2));

  if (inboxError) return Response.json({ ok: false, error: "inbox_select_failed", detail: inboxError.message }, { status: 500 });

  for (const event of inboxRows ?? []) {
    const nextAttempt = (Number(event.attempts) || 0) + 1;
    const { data: claimedRows, error: claimError } = await admin.from("automation_event_inbox")
      .update({ status: "processing", attempts: nextAttempt, last_error: null, processing_at: new Date().toISOString() })
      .eq("id", event.id).eq("status", "received").select("id");

    if (claimError || !claimedRows?.length) continue;
    claimed++;

    const payload = {
      eventId: String(event.event_id),
      source: event.source,
      version: event.version,
      eventType: event.event_type,
      occurredAt: event.occurred_at,
      data: event.data ?? {},
      payload: event.data ?? {},
      attempt: nextAttempt,
    };

    try {
      const response = await send(payload);
      if (response.ok) {
        await admin.from("automation_event_inbox").update({
          status: "processed", processed_at: new Date().toISOString(), last_error: null, processing_at: null,
        }).eq("id", event.id);
        processed++;
      } else {
        const delay = Math.min(3600, Math.max(15, Math.pow(2, nextAttempt) * 15));
        await admin.from("automation_event_inbox").update({
          status: nextAttempt >= 10 ? "failed" : "received",
          available_at: new Date(Date.now() + delay * 1000).toISOString(),
          last_error: `HTTP ${response.status}: ${response.text.slice(0, 1000)}`.slice(0, 2000),
          processing_at: null,
        }).eq("id", event.id);
        failed++;
        errors.push({ eventId: String(event.event_id), status: response.status, detail: response.text.slice(0, 1000) });
      }
    } catch (error) {
      failed++;
      errors.push({ eventId: String(event.event_id), detail: String(error).slice(0, 1000) });
      await admin.from("automation_event_inbox").update({
        status: nextAttempt >= 10 ? "failed" : "received",
        available_at: new Date(Date.now() + Math.min(3600, Math.max(15, Math.pow(2, nextAttempt) * 15)) * 1000).toISOString(),
        last_error: String(error).slice(0, 2000),
        processing_at: null,
      }).eq("id", event.id);
    }
  }

  // Legacy queue remains supported so existing events can drain safely.
  let legacyRows: any[] = [];
  let legacyError: any = null;
  if (includeLegacy) {
    const legacyResult = await admin.from("automation_events").select("*")
      .eq("status", "pending").lte("available_at", new Date().toISOString())
      .lt("attempts", 10).not("event_type", "in", "('test.ping','system.test','system.automation_drain_kick')")
      .order("id", { ascending: true }).limit(Math.max(0, limit - claimed));
    legacyRows = legacyResult.data ?? [];
    legacyError = legacyResult.error;
  }

  if (legacyError) return Response.json({ ok: false, error: "legacy_select_failed", detail: legacyError.message }, { status: 500 });

  for (const event of legacyRows ?? []) {
    const nextAttempt = (Number(event.attempts) || 0) + 1;
    const { data: claimedRows, error: claimError } = await admin.from("automation_events")
      .update({ status: "processing", attempts: nextAttempt, last_error: null })
      .eq("id", event.id).eq("status", "pending").select("id");
    if (claimError || !claimedRows?.length) continue;
    claimed++;

    const payload = {
      eventId: String(event.id),
      eventType: event.event_type,
      occurredAt: event.created_at,
      aggregateType: event.aggregate_type,
      aggregateId: event.aggregate_id,
      data: event.payload ?? {},
      payload: event.payload ?? {},
      attempt: nextAttempt,
    };

    try {
      const response = await send(payload);
      if (response.ok) {
        await admin.from("automation_events").update({
          status: "processed", processed_at: new Date().toISOString(), last_error: null,
        }).eq("id", event.id);
        processed++;
      } else {
        const delay = Math.min(3600, Math.max(15, Math.pow(2, nextAttempt) * 15));
        await admin.from("automation_events").update({
          status: nextAttempt >= 10 ? "failed" : "pending",
          available_at: new Date(Date.now() + delay * 1000).toISOString(),
          last_error: `HTTP ${response.status}: ${response.text.slice(0, 1000)}`.slice(0, 2000),
        }).eq("id", event.id);
        failed++;
        errors.push({ eventId: String(event.id), status: response.status, detail: response.text.slice(0, 1000) });
      }
    } catch (error) {
      failed++;
      errors.push({ eventId: String(event.id), detail: String(error).slice(0, 1000) });
      const delay = Math.min(3600, Math.max(15, Math.pow(2, nextAttempt) * 15));
      await admin.from("automation_events").update({
        status: nextAttempt >= 10 ? "failed" : "pending",
        available_at: new Date(Date.now() + delay * 1000).toISOString(),
        last_error: String(error).slice(0, 2000),
      }).eq("id", event.id);
    }
  }

  if (claimed === 0) await sleep(50);
  return Response.json({
    ok: failed === 0,
    workerId,
    candidates: (inboxRows?.length ?? 0) + (legacyRows?.length ?? 0),
    claimed,
    processed,
    failed,
    errors: errors.slice(0, 3),
  }, { status: failed === 0 ? 200 : 502 });
});