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
  if (WORKER_SECRET && internalSecret === WORKER_SECRET) {
    workerId = "internal:n8n";
  } else if (internalSecret && internalSecret === endpoint.shared_secret) {
    workerId = "internal:db-trigger";
  } else {
    return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });
  }

  const body = await req.json().catch(() => ({}));
  const requestedLimit = Number(body?.limit ?? 10);
  const limit = Number.isFinite(requestedLimit) ? Math.min(10, Math.max(1, Math.floor(requestedLimit))) : 10;

  const selectPending = async () => {
    const now = new Date().toISOString();
    return admin.from("automation_events").select("*")
      .eq("status", "pending").lte("available_at", now).lt("attempts", 10)
      .order("id", { ascending: true }).limit(limit);
  };

  let { data: candidates, error: selectError } = await selectPending();
  if (selectError) return Response.json({ ok: false, error: "claim_select_failed", detail: selectError.message }, { status: 500 });

  // The DB trigger can invoke this function before the INSERT transaction is visible.
  // Give the transaction a short window to commit, then re-check once.
  if (!candidates?.length) {
    await sleep(1200);
    const retry = await selectPending();
    candidates = retry.data;
    selectError = retry.error;
    if (selectError) return Response.json({ ok: false, error: "claim_select_failed", detail: selectError.message }, { status: 500 });
  }

  let processed = 0, failed = 0, claimed = 0;

  for (const event of candidates ?? []) {
    const nextAttempt = (Number(event.attempts) || 0) + 1;
    const { data: claimedRows, error: claimUpdateError } = await admin.from("automation_events")
      .update({ status: "processing", attempts: nextAttempt, last_error: null })
      .eq("id", event.id).eq("status", "pending").select("id");

    if (claimUpdateError || !claimedRows?.length) continue;
    claimed++;

    const payload = {
      eventId: String(event.id),
      eventType: event.event_type,
      occurredAt: event.created_at,
      aggregateType: event.aggregate_type,
      aggregateId: event.aggregate_id,
      payload: event.payload ?? {},
      attempt: nextAttempt,
    };

    try {
      const response = await fetch(endpoint.endpoint_url, {
        method: "POST",
        headers: { "content-type": "application/json", "x-alfaeq-automation-secret": endpoint.shared_secret },
        body: JSON.stringify(payload),
      });
      const responseText = await response.text();

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
          last_error: `HTTP ${response.status}: ${responseText.slice(0, 1000)}`.slice(0, 2000),
        }).eq("id", event.id);
        failed++;
      }
    } catch (error) {
      failed++;
      const delay = Math.min(3600, Math.max(15, Math.pow(2, nextAttempt) * 15));
      await admin.from("automation_events").update({
        status: nextAttempt >= 10 ? "failed" : "pending",
        available_at: new Date(Date.now() + delay * 1000).toISOString(),
        last_error: String(error).slice(0, 2000),
      }).eq("id", event.id);
    }
  }

  return Response.json({
    ok: failed === 0,
    workerId,
    candidates: candidates?.length ?? 0,
    claimed,
    processed,
    failed,
  }, { status: failed === 0 ? 200 : 502 });
});
