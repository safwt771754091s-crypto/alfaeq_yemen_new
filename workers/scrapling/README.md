# Alfaeq Yemen — Scrapling Worker

Server-side bridge between the user's Scrapling repository and the official alfaeq_yemen_new application.

Flow:
n8n / OpenSandbox -> Scrapling Worker -> validate/normalize/deduplicate -> Supabase products/sections

The worker never runs in Flutter and never exposes the Supabase service-role key to the app.

## What it does
- Fetches public product/category pages with Scrapling.
- Extracts JSON-LD Product data when available.
- Falls back to common product-card selectors.
- Normalizes Arabic/English names, prices, currency, stock and image URLs.
- Produces deterministic external IDs from source URL + product URL/name.
- Matches an existing Alfaeq store and section before publishing.
- Supports dry_run (default), so crawling cannot change production data accidentally.
- Publishes only when publish=true and the worker secret is valid.
- Stores source metadata on published products for refresh/deduplication.

The worker is conservative: it does not invent a store, price, stock value, or category mapping.

## Environment
Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SCRAPLING_WORKER_SECRET
Optional: SCRAPLING_HEADLESS (default false), SCRAPLING_REQUEST_TIMEOUT (default 30)

## Request
POST /scrape
Header: x-alfaeq-scrapling-secret: <SCRAPLING_WORKER_SECRET>

Example body:
{"url":"https://example.com/category/food","store_id":"existing-store-id","section_id":"existing-section-id","publish":false,"max_products":50}

Use publish=false first. Review the normalized response before allowing automation to publish.

## Run
Build the image from workers/scrapling and provide the three required environment variables.
The service listens on port 8080.

The source framework is the user's safwt771754091s-crypto/Scrapling repository. The official alfaeq_yemen_new repository remains the only source of truth for Alfaeq production data.
