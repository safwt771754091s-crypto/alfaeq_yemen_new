import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Provider-neutral server configuration.
// Backward-compatible with the existing UNSLOTH_* variables.
const aiBaseUrl = (
  Deno.env.get("AI_BASE_URL") ??
  Deno.env.get("UNSLOTH_BASE_URL") ??
  ""
).replace(/\/$/, "");
const aiApiKey =
  Deno.env.get("AI_API_KEY") ??
  Deno.env.get("UNSLOTH_API_KEY") ??
  "";
const defaultModel =
  Deno.env.get("AI_MODEL") ??
  Deno.env.get("UNSLOTH_MODEL") ??
  "";

const MAX_MESSAGES = 80;
const MAX_MESSAGE_CHARS = 120_000;
const MAX_TOKENS = 4096;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !aiBaseUrl || !defaultModel) {
    return json({ error: "ai_gateway_not_configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "missing_authorization" }, 401);
  }

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

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return json({ error: "messages_invalid" }, 400);
  }

  const serializedMessages = JSON.stringify(messages);
  if (serializedMessages.length > MAX_MESSAGE_CHARS) {
    return json({ error: "messages_too_large" }, 413);
  }

  // The public client cannot select an arbitrary upstream model.
  // Model/provider selection stays server-side so production policy cannot be bypassed.
  const requestedTokens =
    typeof body.max_tokens === "number" && Number.isFinite(body.max_tokens)
      ? Math.floor(body.max_tokens)
      : 1024;
  const maxTokens = Math.min(Math.max(requestedTokens, 1), MAX_TOKENS);

  const requestedTemperature =
    typeof body.temperature === "number" && Number.isFinite(body.temperature)
      ? body.temperature
      : 0.2;
  const temperature = Math.min(Math.max(requestedTemperature, 0), 2);

  const payload = {
    model: defaultModel,
    messages,
    temperature,
    max_tokens: maxTokens,
    stream: body.stream === true,
    ...(Array.isArray(body.tools) ? { tools: body.tools } : {}),
    ...(body.tool_choice !== undefined ? { tool_choice: body.tool_choice } : {}),
    ...(typeof body.top_p === "number" ? { top_p: body.top_p } : {}),
  };

  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (aiApiKey) headers.Authorization = `Bearer ${aiApiKey}`;

  try {
    const upstream = await fetch(`${aiBaseUrl}/v1/chat/completions`, {
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
  } catch {
    return json({ error: "ai_provider_unreachable" }, 502);
  }
});

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
