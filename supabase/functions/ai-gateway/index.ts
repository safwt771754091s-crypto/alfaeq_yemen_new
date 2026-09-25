import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const unslothBaseUrl = (Deno.env.get("UNSLOTH_BASE_URL") ?? "").replace(/\/$/, "");
const unslothApiKey = Deno.env.get("UNSLOTH_API_KEY") ?? "";
const defaultModel = Deno.env.get("UNSLOTH_MODEL") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !unslothBaseUrl || !defaultModel) {
    return json({ error: "ai_gateway_not_configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "missing_authorization" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "invalid_session" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return json({ error: "messages_required" }, 400);
  }

  const model = typeof body.model === "string" && body.model.trim()
      ? body.model.trim() : defaultModel;

  const payload = {
    model,
    messages: body.messages,
    temperature: typeof body.temperature === "number" ? body.temperature : 0.2,
    max_tokens: typeof body.max_tokens === "number" ? body.max_tokens : 1024,
    stream: body.stream === true,
    ...(Array.isArray(body.tools) ? { tools: body.tools } : {}),
    ...(body.tool_choice !== undefined ? { tool_choice: body.tool_choice } : {}),
    ...(typeof body.top_p === "number" ? { top_p: body.top_p } : {}),
  };

  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (unslothApiKey) headers.Authorization = `Bearer ${unslothApiKey}`;

  const upstream = await fetch(`${unslothBaseUrl}/v1/chat/completions`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
    },
  });
});

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
