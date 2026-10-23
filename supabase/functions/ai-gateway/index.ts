import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Provider-neutral server configuration.
// Backward-compatible with the existing UNSLOTH_* variables.
type AiProvider = { name: string; chatUrl: string; apiKey: string; model: string };

// Accept `https://host`, `https://host/v1` and pre-resolved chat endpoints
// (e.g. Pollinations `https://text.pollinations.ai/openai`) so the
// OpenAI-compatible path is never double-suffixed with `/v1`.
function normalizeChatUrl(base: string): string {
  const trimmed = base.replace(/\/$/, "");
  if (!trimmed) return "";
  if (trimmed.endsWith("/chat/completions")) return trimmed;
  if (trimmed.endsWith("/v1")) return `${trimmed}/chat/completions`;
  if (trimmed.endsWith("/openai")) return trimmed;
  return `${trimmed}/v1/chat/completions`;
}

const env = (name: string) => (Deno.env.get(name) ?? "").trim();

const primaryBase = env("AI_BASE_URL") || env("UNSLOTH_BASE_URL") || env("OPENAI_BASE_URL");
const primaryKey = env("AI_API_KEY") || env("UNSLOTH_API_KEY") || env("OPENAI_API_KEY");
const primaryModel = env("AI_MODEL") || env("UNSLOTH_MODEL") || env("OPENAI_MODEL");

// Optional explicit fallback provider with the same OpenAI-compatible shape.
const fallbackBase = env("AI_FALLBACK_BASE_URL");
const fallbackKey = env("AI_FALLBACK_API_KEY");
const fallbackModel = env("AI_FALLBACK_MODEL");

// Built-in free providers keep the assistant answering when the primary
// provider is rate-limited or out of quota. They need no secret. Set
// AI_ENABLE_FREE_FALLBACK=false to disable them.
const freeFallbackEnabled = env("AI_ENABLE_FREE_FALLBACK") !== "false";
const FREE_FALLBACKS: AiProvider[] = freeFallbackEnabled
  ? [
    { name: "llm7", chatUrl: "https://api.llm7.io/v1/chat/completions", apiKey: "unused", model: "default" },
    { name: "pollinations", chatUrl: "https://text.pollinations.ai/openai", apiKey: "", model: "openai" },
  ]
  : [];

const providers: AiProvider[] = [];
if (primaryBase && primaryModel) {
  providers.push({ name: "primary", chatUrl: normalizeChatUrl(primaryBase), apiKey: primaryKey, model: primaryModel });
}
if (fallbackBase && fallbackModel) {
  providers.push({ name: "fallback", chatUrl: normalizeChatUrl(fallbackBase), apiKey: fallbackKey, model: fallbackModel });
}
for (const candidate of FREE_FALLBACKS) {
  if (!providers.some((p) => p.chatUrl === candidate.chatUrl)) providers.push(candidate);
}

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
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "server_configuration_missing" }, 503);
  }
  if (providers.length === 0) {
    // No provider configured (no secrets and free fallback disabled).
    // Server-side secrets: AI_BASE_URL, AI_MODEL and AI_API_KEY.
    return json({ error: "ai_provider_not_configured" }, 503);
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
    messages,
    temperature,
    max_tokens: maxTokens,
    stream: body.stream === true,
    ...(Array.isArray(body.tools) ? { tools: body.tools } : {}),
    ...(body.tool_choice !== undefined ? { tool_choice: body.tool_choice } : {}),
    ...(typeof body.top_p === "number" ? { top_p: body.top_p } : {}),
  };

  const result = await callProviders(providers, payload);
  return new Response(result.body, {
    status: result.status,
    headers: { ...corsHeaders, "Content-Type": result.contentType },
  });
});

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Try each configured provider in order. Free/community providers frequently
// answer 429/5xx under load, so on a transient failure we move to the next
// provider (and retry each one a few times with backoff).
async function callProviders(providers: AiProvider[], payload: Record<string, unknown>) {
  let lastStatus = 502;
  let lastBody = JSON.stringify({ error: "ai_provider_unreachable" });
  let lastContentType = "application/json";

  for (const provider of providers) {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (provider.apiKey) headers.Authorization = `Bearer ${provider.apiKey}`;
    const result = await callUpstream(provider.chatUrl, { ...payload, model: provider.model }, headers);

    // A successful or client-visible (non-transient) response ends the chain.
    if (result.status < 500 && result.status !== 429) return result;

    lastStatus = result.status;
    lastBody = result.body;
    lastContentType = result.contentType;
  }

  return { status: lastStatus, body: lastBody, contentType: lastContentType };
}

async function callUpstream(
  chatCompletionsUrl: string,
  payload: unknown,
  headers: Record<string, string>,
) {
  const attempts = 3;
  let lastStatus = 502;
  let lastBody = JSON.stringify({ error: "ai_provider_unreachable" });
  let lastContentType = "application/json";

  for (let i = 0; i < attempts; i++) {
    let upstream: Response;
    try {
      upstream = await fetch(chatCompletionsUrl, {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      });
    } catch {
      lastStatus = 502;
      lastBody = JSON.stringify({ error: "ai_provider_unreachable" });
      lastContentType = "application/json";
      if (i < attempts - 1) await delay(400 * (i + 1));
      continue;
    }

    const text = await upstream.text();
    const contentType = upstream.headers.get("Content-Type") ?? "application/json";
    const transient = upstream.status === 429 || upstream.status === 502 ||
      upstream.status === 503 || upstream.status === 504;

    if (!transient) {
      // Surface provider auth failures as a stable, client-friendly code so the
      // app can show Arabic guidance instead of the raw upstream error body.
      if (upstream.status === 401 || upstream.status === 403) {
        return {
          status: 502,
          body: JSON.stringify({ error: "ai_provider_auth_failed", upstream_status: upstream.status }),
          contentType: "application/json",
        };
      }
      return { status: upstream.status, body: text, contentType };
    }

    lastStatus = upstream.status;
    lastBody = text;
    lastContentType = contentType;
    if (i < attempts - 1) await delay(500 * Math.pow(2, i));
  }

  const code = lastStatus === 429 ? "ai_provider_rate_limited" : "ai_provider_unavailable";
  let detail: unknown;
  try {
    detail = JSON.parse(lastBody);
  } catch {
    detail = lastBody.slice(0, 500);
  }
  return {
    status: lastStatus === 429 ? 429 : 503,
    body: JSON.stringify({ error: code, upstream_status: lastStatus, detail }),
    contentType: "application/json",
  };
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
