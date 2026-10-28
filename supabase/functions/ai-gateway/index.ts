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
  // `/openai` is a *base* for OpenAI-compatible providers and still needs the
  // chat path appended. Gemini's documented base is
  // `https://generativelanguage.googleapis.com/v1beta/openai`, so treating it
  // as a complete endpoint made every primary request 404 and the app silently
  // fell back to the free providers.
  if (trimmed.endsWith("/openai")) return `${trimmed}/chat/completions`;
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
    // Pollinations has the higher free limit and supports tool-calling, so it
    // goes before llm7 (which rate-limits after a couple of calls). The full
    // chat endpoint is used so the URL never depends on normalization.
    { name: "pollinations", chatUrl: "https://text.pollinations.ai/openai/chat/completions", apiKey: "", model: "openai-fast" },
    { name: "llm7", chatUrl: "https://api.llm7.io/v1/chat/completions", apiKey: "unused", model: "default" },
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

// A misconfigured secret (e.g. a random hex value instead of a URL) would make
// every request burn three retries on an unparseable URL before falling through.
// Such a provider is dropped up front so the working provider answers fast.
const usableProviders = providers.filter((p) => isValidHttpUrl(p.chatUrl));

function isValidHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

const MAX_MESSAGES = 80;
const MAX_MESSAGE_CHARS = 120_000;
const MAX_TOKENS = 4096;

// A free upstream can answer 200 OK while the body is really a quota/limit
// notice (e.g. Pollinations' "API key ... reached its budget"). Returning that
// as an assistant reply shows the user a broken message, so it is treated as a
// provider failure and the chain moves on. Only explicit quota phrases are
// matched so a normal answer that merely mentions "budget" is never dropped.
const PROVIDER_NOTICE_PATTERNS = [
  /reached (?:its|your) budget/i,
  /raise the (?:key )?budget/i,
  /free (?:tier )?limit reached/i,
  /quota (?:exceeded|exhausted|reached)/i,
  /(?:rate|request) limit (?:reached|exceeded)/i,
  /insufficient (?:credits|balance|quota)/i,
];

function isProviderNotice(text: string): boolean {
  if (!text) return false;
  return PROVIDER_NOTICE_PATTERNS.some((re) => re.test(text));
}

/// Returns a stable error code when a 2xx body is really an upstream notice,
/// or null when the body is a genuine assistant answer.
function detectProviderNotice(body: string, contentType: string): string | null {
  if (!contentType.includes("json")) return null;
  try {
    const parsed = JSON.parse(body);
    const message = parsed?.choices?.[0]?.message;
    if (message && typeof message.content === "string" && isProviderNotice(message.content)) {
      return "ai_provider_notice";
    }
    // Some providers put the notice in `error` even with a 200 status.
    if (parsed?.error && typeof parsed.error === "string" && isProviderNotice(parsed.error)) {
      return "ai_provider_notice";
    }
    if (parsed?.error && typeof parsed?.error?.message === "string" && isProviderNotice(parsed.error.message)) {
      return "ai_provider_notice";
    }
  } catch {
    /* not JSON: an ordinary text answer, not a notice */
  }
  return null;
}

/// Returns a stable error code when a 2xx body carries no assistant content and
/// no tool calls (some free providers emit a reasoning-only or empty completion
/// under load). The app renders only `content`, so such a reply is unusable and
/// the chain must keep trying. Returns null for a usable answer.
function detectEmptyCompletion(body: string, contentType: string): string | null {
  if (!contentType.includes("json")) return null;
  try {
    const parsed = JSON.parse(body);
    const message = parsed?.choices?.[0]?.message;
    if (!message) return null;
    const hasTools = Array.isArray(message.tool_calls) && message.tool_calls.length > 0;
    const content = message.content;
    const hasContent = typeof content === "string" ? content.trim().length > 0 : content != null;
    if (!hasTools && !hasContent) return "ai_provider_empty";
  } catch {
    /* not JSON: nothing to classify */
  }
  return null;
}

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
  if (usableProviders.length === 0) {
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

  const result = await callProviders(usableProviders, payload);
  return new Response(result.body, {
    status: result.status,
    headers: { ...corsHeaders, "Content-Type": result.contentType },
  });
});

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Try each configured provider in order. A dead model, a bad key or a 429 on
// one provider must never stop the chain: only a usable 2xx answer ends it.
// Each provider is retried (a free provider's per-minute limit often clears in
// a couple of seconds) and the whole chain is swept twice, so a transient 429
// does not surface to the user while a sibling provider is still healthy.
const CHAIN_ATTEMPTS = 2;
const PROVIDER_ATTEMPTS = 2;

async function callProviders(providers: AiProvider[], payload: Record<string, unknown>) {
  let lastStatus = 502;
  let lastBody = "";

  for (let chain = 0; chain < CHAIN_ATTEMPTS; chain++) {
    let sawTransient = false;
    for (const provider of providers) {
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (provider.apiKey) headers.Authorization = `Bearer ${provider.apiKey}`;
      const result = await callUpstream(provider.chatUrl, { ...payload, model: provider.model }, headers);

      if (result.status >= 200 && result.status < 300) return result;

      lastStatus = result.status;
      lastBody = result.body;
      if (lastStatus === 429 || lastStatus === 502 || lastStatus === 503 || lastStatus === 504) {
        sawTransient = true;
      }
    }
    // Only sweep the chain again after a transient failure (a rolling quota
    // window or a brief outage). A hard 404/401/402 will not fix itself, so
    // retrying it would only add latency.
    if (chain < CHAIN_ATTEMPTS - 1 && sawTransient) await delay(1200);
    else if (chain < CHAIN_ATTEMPTS - 1) break;
  }

  // Every provider failed: surface one stable, client-friendly code instead of
  // leaking an empty 404 from an upstream that no longer serves the model.
  if (lastStatus === 429) {
    return {
      status: 429,
      body: JSON.stringify({ error: "ai_provider_rate_limited", upstream_status: 429 }),
      contentType: "application/json",
    };
  }
  // A quota/limit notice is not a transient outage: tell the app so it can show
  // the right guidance instead of "try again later".
  if (lastBody.includes("ai_provider_notice")) {
    return {
      status: 503,
      body: JSON.stringify({ error: "ai_provider_notice", upstream_status: 200 }),
      contentType: "application/json",
    };
  }
  let detail: unknown = lastBody.slice(0, 500);
  try {
    detail = JSON.parse(lastBody);
  } catch { /* keep the raw slice */ }
  return {
    status: 503,
    body: JSON.stringify({ error: "ai_provider_unavailable", upstream_status: lastStatus, detail }),
    contentType: "application/json",
  };
}

async function callUpstream(
  chatCompletionsUrl: string,
  payload: unknown,
  headers: Record<string, string>,
) {
  const attempts = PROVIDER_ATTEMPTS;
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

    // A 2xx body that is really a quota/limit notice must not be returned as an
    // answer. Treat it as a provider failure so the next provider is tried.
    if (upstream.ok) {
      const notice = detectProviderNotice(text, contentType);
      if (notice) {
        return {
          status: 503,
          body: JSON.stringify({ error: notice, upstream_status: 200 }),
          contentType: "application/json",
        };
      }
      // An empty 2xx body (some free providers return one under load) is not a
      // usable answer: treat it as a failure so the chain keeps trying.
      const empty = detectEmptyCompletion(text, contentType);
      if (empty) {
        lastStatus = 502;
        lastBody = JSON.stringify({ error: empty, upstream_status: 200 });
        lastContentType = "application/json";
        if (i < attempts - 1) await delay(300 * (i + 1));
        continue;
      }
    }

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
