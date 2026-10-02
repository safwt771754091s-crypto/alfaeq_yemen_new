import express from "express";
import { createClient } from "@supabase/supabase-js";

const app = express();
app.use(express.json({ limit: "32kb" }));

const {
  PORT = "8080",
  COBALT_API_URL,
  COBALT_API_KEY,
  COBALT_GATEWAY_SECRET,
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
} = process.env;

if (!COBALT_API_URL || !COBALT_GATEWAY_SECRET || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing required Cobalt gateway environment variables");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function validSourceUrl(value) {
  try {
    const u = new URL(value);
    return u.protocol === "https:" && u.hostname.length > 0;
  } catch {
    return false;
  }
}

function safeId(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 200 ? value : null;
}

function bearerToken(req) {
  const header = req.get("authorization");
  if (!header) return null;
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

async function authenticatedUser(req) {
  const token = bearerToken(req);
  if (!token) return { error: "missing_bearer_token" };

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user?.id) return { error: "invalid_bearer_token" };

  return { user: data.user };
}

function cobaltPayload(body) {
  return {
    url: body.url,
    downloadMode: ["auto", "audio", "mute"].includes(body.download_mode) ? body.download_mode : "auto",
    videoQuality: ["max", "4320", "2160", "1440", "1080", "720", "480", "360", "240", "144"].includes(body.video_quality) ? body.video_quality : "1080",
    audioFormat: ["best", "mp3", "ogg", "wav", "opus"].includes(body.audio_format) ? body.audio_format : "mp3",
    audioBitrate: ["320", "256", "128", "96", "64", "8"].includes(body.audio_bitrate) ? body.audio_bitrate : "128",
    filenameStyle: ["classic", "pretty", "basic", "nerdy"].includes(body.filename_style) ? body.filename_style : "basic",
    alwaysProxy: true,
    disableMetadata: false
  };
}

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "alfaeq-cobalt-gateway" });
});

app.post("/media/resolve", async (req, res) => {
  if (req.get("x-alfaeq-cobalt-secret") !== COBALT_GATEWAY_SECRET) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const auth = await authenticatedUser(req);
  if (auth.error) {
    return res.status(401).json({ error: auth.error });
  }

  const { url, user_id: requestedUserId = null, entity_type = null, entity_id = null } = req.body ?? {};
  const userId = auth.user.id;

  if (requestedUserId !== null && requestedUserId !== userId) {
    return res.status(403).json({ error: "user_id_mismatch" });
  }

  if (!validSourceUrl(url)) {
    return res.status(400).json({ error: "invalid_request" });
  }

  const headers = {
    "Accept": "application/json",
    "Content-Type": "application/json",
  };
  if (COBALT_API_KEY) headers.Authorization = `Api-Key ${COBALT_API_KEY}`;

  const cobalt = await fetch(COBALT_API_URL.replace(/\/$/, "") + "/", {
    method: "POST",
    headers,
    body: JSON.stringify(cobaltPayload(req.body)),
  });

  const result = await cobalt.json().catch(() => ({ status: "error", error: { code: "invalid_json" } }));
  if (!cobalt.ok || result.status === "error") {
    return res.status(cobalt.status || 502).json(result);
  }

  if (result.status === "picker") {
    return res.json({ status: "picker", picker: result.picker ?? [], audio: result.audio ?? null });
  }

  if (!["tunnel", "redirect"].includes(result.status) || !result.url) {
    return res.status(502).json({ error: "unsupported_cobalt_response", result });
  }

  const sourceId = `cobalt:${userId}:${Buffer.from(url).toString("base64url").slice(0, 180)}`;
  const metadata = {
    provider: "cobalt",
    cobalt_status: result.status,
    filename: result.filename ?? null,
    source_url: url,
  };

  const { data: asset, error: assetError } = await supabase
    .from("media_assets")
    .upsert({
      owner_id: userId,
      entity_type: safeId(entity_type),
      entity_id: safeId(entity_id),
      source: "external_url",
      source_id: sourceId,
      public_url: result.url,
      mime_type: null,
      is_public: true,
      metadata,
    }, { onConflict: "source,source_id" })
    .select()
    .single();

  if (assetError) {
    return res.status(500).json({ error: "media_asset_persist_failed" });
  }

  const eventId = `media.resolved:${asset.id}:v1`;
  const { error: eventError } = await supabase
    .from("automation_event_inbox")
    .upsert({
      event_id: eventId,
      source: "cobalt",
      version: 1,
      event_type: "media.resolved",
      occurred_at: new Date().toISOString(),
      data: {
        media_asset_id: asset.id,
        user_id: userId,
        entity_type,
        entity_id,
        cobalt_status: result.status,
        filename: result.filename ?? null,
      },
    }, { onConflict: "event_id", ignoreDuplicates: true });

  if (eventError) {
    return res.status(500).json({ error: "automation_event_failed", media_asset: asset });
  }

  return res.json({
    status: result.status,
    media_asset: asset,
    filename: result.filename ?? null,
  });
});

app.listen(Number(PORT), () => {
  console.log(`Alfaeq Cobalt Gateway listening on :${PORT}`);
});
