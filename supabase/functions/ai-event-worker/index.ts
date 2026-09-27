import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey) return json({ ok: false, error: "server_configuration_missing" }, 500);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // n8n authenticates with the same secret already stored for the Alfaeq
  // automation endpoint. The secret never reaches the Flutter client.
  const providedSecret = req.headers.get("x-alfaeq-automation-secret") ?? "";
  if (!providedSecret) return json({ ok: false, error: "missing_automation_secret" }, 401);

  const { data: endpoint, error: endpointError } = await admin
    .from("automation_endpoints")
    .select("shared_secret,enabled")
    .eq("id", "n8n")
    .maybeSingle();

  if (endpointError) return json({ ok: false, error: "endpoint_lookup_failed" }, 500);
  if (!endpoint?.enabled || !endpoint.shared_secret || providedSecret !== endpoint.shared_secret) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") return json({ ok: false, error: "invalid_json" }, 400);

  const eventId = String(body.eventId ?? "").trim();
  const eventType = String(body.eventType ?? "").trim();
  const occurredAt = String(body.occurredAt ?? new Date().toISOString());
  const data = body.data ?? body.payload ?? {};

  if (!eventId || !eventType) {
    return json({ ok: false, error: "event_id_and_type_required" }, 400);
  }

  const { data: existing, error: existingError } = await admin
    .from("ai_tasks")
    .select("id,status,assignee_id")
    .eq("metadata->>event_id", eventId)
    .maybeSingle();

  if (existingError) return json({ ok: false, error: "idempotency_lookup_failed" }, 500);
  if (existing) {
    return json({ ok: true, deduplicated: true, taskId: existing.id, status: existing.status });
  }

  const role = roleForEvent(eventType);
  const { data: agent, error: agentError } = await admin
    .from("ai_agents")
    .select("id,name,role,status,budget_monthly_cents,spend_monthly_cents")
    .eq("role", role)
    .in("status", ["idle", "active"])
    .order("created_at")
    .limit(1)
    .maybeSingle();

  if (agentError) return json({ ok: false, error: "agent_lookup_failed" }, 500);
  if (!agent) return json({ ok: false, error: "no_available_agent", role }, 409);

  const budget = Number(agent.budget_monthly_cents ?? 0);
  const spend = Number(agent.spend_monthly_cents ?? 0);
  if (budget > 0 && spend >= budget) {
    await admin.from("ai_agents").update({ status: "paused", updated_at: new Date().toISOString() }).eq("id", agent.id);
    return json({ ok: false, error: "agent_budget_exhausted", agentId: agent.id }, 429);
  }

  const title = titleForEvent(eventType, data);
  const { data: task, error: taskError } = await admin
    .from("ai_tasks")
    .insert({
      title,
      description: `Automation event ${eventType} received from n8n.`,
      status: "todo",
      priority: priorityForEvent(eventType),
      assignee_id: agent.id,
      metadata: {
        source: "n8n",
        event_id: eventId,
        event_type: eventType,
        occurred_at: occurredAt,
        payload: data,
      },
    })
    .select("id,title,status,priority,assignee_id")
    .single();

  if (taskError) {
    if (taskError.code === "23505") {
      const retry = await admin.from("ai_tasks").select("id,status").eq("metadata->>event_id", eventId).maybeSingle();
      if (retry.data) return json({ ok: true, deduplicated: true, taskId: retry.data.id, status: retry.data.status });
    }
    return json({ ok: false, error: "task_create_failed", detail: taskError.message }, 500);
  }

  await admin.from("ai_activity_log").insert({
    agent_id: agent.id,
    task_id: task.id,
    event_type: "task.created",
    payload: { source: "n8n", event_id: eventId, event_type: eventType },
  });

  return json({ ok: true, deduplicated: false, task });
});

function roleForEvent(eventType: string): string {
  if (eventType.startsWith("order.") || eventType.startsWith("merchant.") || eventType.startsWith("store.")) return "Operations";
  if (eventType.startsWith("product.")) return "CTO";
  if (eventType.startsWith("promotion.")) return "Marketing";
  if (eventType.startsWith("site_update.")) return "Marketing";
  return "Automation";
}

function priorityForEvent(eventType: string): string {
  if (eventType === "order.created") return "high";
  if (eventType.startsWith("order.")) return "normal";
  return "normal";
}

function titleForEvent(eventType: string, data: unknown): string {
  const suffix = typeof data === "object" && data !== null && "aggregateId" in data
    ? String((data as Record<string, unknown>).aggregateId ?? "")
    : "";
  return suffix ? `Handle ${eventType} — ${suffix}` : `Handle ${eventType}`;
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
