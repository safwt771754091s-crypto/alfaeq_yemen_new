# Alfaeq Yemen — Cobalt Media Gateway

Production integration for the user's Cobalt repository.

## Architecture

Flutter -> Supabase Auth/RLS -> Alfaeq Cobalt Gateway -> self-hosted Cobalt API
                                      \-> Supabase media_assets
                                      \-> automation_event_inbox

Cobalt remains an isolated media service. It is not copied into Flutter or the Supabase database.

Pinned Cobalt source:
https://github.com/safwt771754091s-crypto/cobalt
Commit: a636575b09de1fc55d9b8cd98cac88f5f2f16b42

The gateway accepts only authenticated service-to-service requests and forwards the public source URL to a self-hosted Cobalt instance. Do not use api.cobalt.tools without explicit permission.

## Environment

- COBALT_API_URL: URL of the self-hosted Cobalt API
- COBALT_API_KEY: optional Api-Key token
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- COBALT_GATEWAY_SECRET

## Endpoint

POST /media/resolve

Header:
x-alfaeq-cobalt-secret: <COBALT_GATEWAY_SECRET>

Body:
{
  "user_id": "<authenticated Alfaeq user uid>",
  "url": "https://...",
  "entity_type": "product",
  "entity_id": "<optional>",
  "download_mode": "auto",
  "video_quality": "1080"
}

The gateway validates the URL, calls Cobalt, stores a media asset for tunnel/redirect results, and emits a `media.resolved` event through the existing Supabase automation inbox.

Picker responses are returned without automatically selecting or publishing an item.

## Security

Never expose SUPABASE_SERVICE_ROLE_KEY, COBALT_API_KEY, or COBALT_GATEWAY_SECRET to Flutter, the browser, or n8n. The gateway is a server-side worker.

Only public content supported by the configured Cobalt instance should be processed. Users remain responsible for rights and permitted use of downloaded material.

## Run

```
npm install
npm start
```

Default port: 8080.
