import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const OPENHANDS_API_KEY = Deno.env.get("OPENHANDS_API_KEY") ?? "";
const OPENHANDS_BASE_URL = (Deno.env.get("OPENHANDS_BASE_URL") ?? "https://app.all-hands.dev").replace(/\/$/, "");

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ ok: false, error: "server_configuration_missing" }, 500);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  if (!(await authorize(admin, req))) return json({ ok: false, error: "unauthorized" }, 401);
  if (!OPENHANDS_API_KEY) return json({ ok: false, error: "executor_provider_not_configured" }, 503);

  const body = await req.json().catch(() => ({}));
  const action = String(body?.action ?? "dispatch");

  try {
    if (action === "dispatch") return await dispatchOne(admin);
    if (action === "reconcile") return await reconcile(admin);
    if (action === "dispatch_and_reconcile") {
      const dispatched = await dispatchOne(admin);
      const reconciled = await reconcile(admin);
      return json({
        ok: dispatched.status < 300 && reconciled.status < 300,
        dispatch: await dispatched.json(),
        reconcile: await reconciled.json(),
      });
    }
    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (error) {
    return json({ ok: false, error: "executor_failed", detail: String(error).slice(0, 1000) }, 500);
  }
});

async function authorize(admin: ReturnType<typeof createClient>, req: Request) {
  const supplied = req.headers.get("x-alfaeq-automation-secret") ?? "";
  if (!supplied) return false;
  const { data, error } = await admin.from("automation_endpoints")
    .select("shared_secret,enabled").eq("id", "n8n").maybeSingle();
  return !error && Boolean(data?.enabled && data.shared_secret && supplied === data.shared_secret);
}

async function dispatchOne(admin: ReturnType<typeof createClient>): Promise<Response> {
  const { data: agents, error } = await admin.from("ai_agents")
    .select("id,status,budget_monthly_cents,spend_monthly_cents")
    .in("status", ["idle", "active"]).order("created_at");
  if (error) throw new Error(`agent_lookup_failed: ${error.message}`);

  let claimed: any = null;
  for (const agent of agents ?? []) {
    const budget = Number(agent.budget_monthly_cents ?? 0);
    const spend = Number(agent.spend_monthly_cents ?? 0);
    if (budget > 0 && spend >= budget) continue;

    const result = await admin.rpc("claim_ai_task_for_execution", {
      p_agent_id: agent.id,
      p_provider: "openhands",
      p_repository: "safwt771754091s-crypto/alfaeq_yemen_new",
      p_branch: "main",
    });
    if (result.error) {
      if (/agent_not_available|agent_budget_exhausted/i.test(result.error.message)) continue;
      throw new Error(`claim_failed: ${result.error.message}`);
    }
    if (Array.isArray(result.data) && result.data.length) {
      claimed = result.data[0];
      break;
    }
  }

  if (!claimed) return json({ ok: true, dispatched: false, reason: "no_claimable_task" });

  const runId = String(claimed.run_id);
  try {
    const response = await openHandsRequest("/api/conversations", "POST", {
      initial_user_msg: buildPrompt(claimed),
      repository: "safwt771754091s-crypto/alfaeq_yemen_new",
      selected_branch: "main",
    });

    const conversationId = String(response.conversation_id ?? response.id ?? "");
    if (!conversationId) throw new Error("openhands_missing_conversation_id");

    const providerStatus = String(response.status ?? "RUNNING").toUpperCase();
    if (["STOPPED", "COMPLETED", "SUCCEEDED"].includes(providerStatus)) {
      await complete(admin, runId, "succeeded", {
        provider: "openhands", provider_status: providerStatus, conversation_id: conversationId,
      }, conversationId, conversationId);
    } else {
      const { error } = await admin.from("ai_agent_runs").update({
        conversation_id: conversationId,
        external_run_id: conversationId,
        result: {
          provider: "openhands",
          provider_status: providerStatus,
          conversation_url: `${OPENHANDS_BASE_URL}/conversations/${conversationId}`,
        },
        updated_at: new Date().toISOString(),
      }).eq("id", runId);
      if (error) throw new Error(`run_persist_failed: ${error.message}`);
    }

    return json({ ok: true, dispatched: true, run_id: runId, conversation_id: conversationId, provider_status: providerStatus }, 202);
  } catch (error) {
    await complete(admin, runId, "failed", {
      provider: "openhands", dispatch_error: String(error).slice(0, 1000),
    }, null, null);
    throw error;
  }
}

async function reconcile(admin: ReturnType<typeof createClient>): Promise<Response> {
  const { data: runs, error } = await admin.from("ai_agent_runs")
    .select("id,conversation_id,external_run_id").eq("status", "running")
    .not("conversation_id", "is", null).order("updated_at").limit(10);
  if (error) throw new Error(`active_runs_lookup_failed: ${error.message}`);

  let checked = 0, succeeded = 0, failed = 0;
  for (const run of runs ?? []) {
    checked++;
    const conversationId = String(run.conversation_id);
    try {
      const state = await openHandsRequest(`/api/conversations/${encodeURIComponent(conversationId)}`, "GET");
      const providerStatus = String(state.status ?? "UNKNOWN").toUpperCase();

      if (["STOPPED", "COMPLETED", "SUCCEEDED"].includes(providerStatus)) {
        await complete(admin, run.id, "succeeded", {
          provider: "openhands", provider_status: providerStatus, conversation_id: conversationId,
          reconciled_at: new Date().toISOString(),
        }, String(run.external_run_id ?? conversationId), conversationId);
        succeeded++;
      } else if (["FAILED", "ERROR", "CANCELLED"].includes(providerStatus)) {
        await complete(admin, run.id, "failed", {
          provider: "openhands", provider_status: providerStatus, conversation_id: conversationId,
          reconciled_at: new Date().toISOString(),
        }, String(run.external_run_id ?? conversationId), conversationId);
        failed++;
      } else {
        await admin.rpc("heartbeat_ai_agent_run", { p_run_id: run.id });
      }
    } catch (error) {
      console.error("reconcile_run_failed", run.id, String(error));
    }
  }
  return json({ ok: true, checked, succeeded, failed });
}

async function complete(admin: ReturnType<typeof createClient>, runId: string, status: string, result: Record<string, unknown>, externalRunId: string | null, conversationId: string | null) {
  const { error } = await admin.rpc("complete_ai_agent_run", {
    p_run_id: runId, p_status: status, p_result: result,
    p_error: status === "failed" ? String(result.provider_status ?? result.dispatch_error ?? "provider_failed") : null,
    p_external_run_id: externalRunId, p_conversation_id: conversationId,
  });
  if (error) throw new Error(`complete_run_failed: ${error.message}`);
}

async function openHandsRequest(path: string, method: "GET" | "POST", body?: Record<string, unknown>) {
  const response = await fetch(`${OPENHANDS_BASE_URL}${path}`, {
    method,
    headers: { Authorization: `Bearer ${OPENHANDS_API_KEY}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let parsed: any = {};
  try { parsed = JSON.parse(text); } catch { parsed = { raw: text.slice(0, 2000) }; }
  if (!response.ok) throw new Error(`OpenHands HTTP ${response.status}: ${JSON.stringify(parsed).slice(0, 1500)}`);
  return parsed;
}

function buildPrompt(task: any) {
  return `You are the Alfaeq engineering agent. Execute this production engineering task in an isolated workspace.

Task: ${String(task.title ?? "Untitled task")}

Description:
${String(task.description ?? "")}

Metadata:
${JSON.stringify(task.metadata ?? {}).slice(0, 12000)}

Required contract:
- Supabase PostgreSQL is the production source of truth.
- Inspect code, migrations, RLS, RPCs, event bus and tests before editing.
- Never request, print, commit, or store production service-role keys or other secrets.
- Critical order, inventory, payment and ledger changes must be transactional and idempotent.
- Preserve compensation metadata for reversible external side effects.
- Use canonical Supabase events; do not create a parallel business-state store.
- Run formatting, static analysis, tests, relevant builds and security checks.
- Do not claim completion without command/test evidence.
- Work on the selected branch and prepare a focused PR; do not merge directly to main.`;
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
