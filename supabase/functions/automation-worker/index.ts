import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ ok: false, error: "method_not_allowed" }, { status: 405 });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return Response.json({ ok: false, error: "server_configuration_missing" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });

  const uid = authData.user.id;
  const { data: actor, error: actorError } = await admin.from("users").select("uid,admin,owner,developer").eq("uid", uid).maybeSingle();
  if (actorError || !actor || !(actor.admin || actor.owner || actor.developer)) {
    return Response.json({ ok: false, error: "automation_staff_required" }, { status: 403 });
  }

  const { data: endpoint, error: endpointError } = await admin.from("automation_endpoints")
    .select("endpoint_url,shared_secret,enabled").eq("id", "n8n").maybeSingle();
  if (endpointError) return Response.json({ ok: false, error: "endpoint_lookup_failed" }, { status: 500 });
  if (!endpoint?.enabled || !endpoint.endpoint_url || !endpoint.shared_secret) {
    return Response.json({ ok: true, processed: 0, state: "disabled" });
  }

  const body = await req.json().catch(() => ({}));
  const requestedLimit = Number(body?.limit ?? 10);
  const limit = Number.isFinite(requestedLimit) ? Math.min(10, Math.max(1, Math.floor(requestedLimit))) : 10;

  const { data: events, error: claimError } = await admin.rpc("claim_automation_events", {
    p_limit: limit, p_worker_id: `edge:${uid}`,
  });
  if (claimError) return Response.json({ ok: false, error: "claim_failed", detail: claimError.message }, { status: 500 });

  let processed = 0, failed = 0;
  for (const event of events ?? []) {
    const payload = {
      eventId: String(event.id), eventType: event.event_type, occurredAt: event.created_at,
      aggregateType: event.aggregate_type, aggregateId: event.aggregate_id,
      payload: event.payload ?? {}, attempt: event.attempts,
    };
    try {
      const response = await fetch(endpoint.endpoint_url, {
        method: "POST",
        headers: { "content-type": "application/json", "x-alfaeq-automation-secret": endpoint.shared_secret },
        body: JSON.stringify(payload),
      });
      const responseText = await response.text();
      await admin.rpc("finish_automation_event", {
        p_event_id: event.id, p_success: response.ok,
        p_error: response.ok ? null : `HTTP ${response.status}: ${responseText.slice(0, 1000)}`,
      });
      if (response.ok) processed++; else failed++;
    } catch (error) {
      failed++;
      await admin.rpc("finish_automation_event", {
        p_event_id: event.id, p_success: false,
        p_error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return Response.json({ ok: failed === 0, claimed: events?.length ?? 0, processed, failed });
});
