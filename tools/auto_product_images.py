#!/usr/bin/env python3
"""Automatically find, download and attach a product image to every product.

For each product (searched by name AND barcode) the tool tries, in order:

1. Open Food Facts by barcode (free, no key).
2. Google Programmable Search images by barcode, then by name (needs a key).
3. Openverse by name (free, no key, Creative-Commons images).

The winning image is downloaded, uploaded to the public Supabase Storage
bucket `media`, registered in `public.media_assets`, and finally linked to
the product via `products.image_url`. It is idempotent: products that
already have an image are skipped unless --overwrite is given.

Reads use the publishable key. Writes (Storage + tables) require a
service-role key, which is never stored in the repository:

    export SUPABASE_SERVICE_ROLE_KEY=...
    # optional, enables the Google provider
    export GOOGLE_API_KEY=... GOOGLE_CSE_CX=...

    python3 tools/auto_product_images.py --dry-run --limit 50
    python3 tools/auto_product_images.py --limit 200 --out images_map.json

Notes
-----
* Coverage from Open Food Facts is bounded: Gulf SKUs (628/629/694/885)
  are only partly indexed. The name-based providers cover the rest, but a
  wrong match is possible, so review --dry-run output for a sample first.
* Safe to re-run: an existing image_url is never replaced by default.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUPABASE_DART = os.path.join(REPO_ROOT, "lib", "services", "supabase_service.dart")
BUCKET = "media"
MAX_IMAGE_BYTES = 5 * 1024 * 1024
USER_AGENT = "AlfaeqYemen/1.0 (product image automation)"


def dart_default(pattern):
    with open(SUPABASE_DART, encoding="utf-8") as handle:
        match = re.search(pattern, handle.read())
    return match.group(1) if match else ""


DEFAULT_URL = dart_default(r"projectUrl[\s\S]*?defaultValue:\s*'(https://[^']+)'")
DEFAULT_PUBLISHABLE = dart_default(r"_defaultPublishableKey\s*=\s*'([^']+)'")


def request(url, headers=None, method="GET", body=None, timeout=40, retries=3):
    headers = dict(headers or {})
    headers.setdefault("User-Agent", USER_AGENT)
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    for attempt in range(retries):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
    raise urllib.error.URLError(url)


def key_diagnostics(key):
    raw = key or ""
    trimmed = raw.strip()
    parts = trimmed.split(".")
    if trimmed.startswith("eyJ") and len(parts) == 3:
        kind = "jwt(service_role/anon)"
    elif trimmed.startswith("sb_secret"):
        kind = "sb_secret (new API key — not a JWT)"
    elif trimmed.startswith("sb_publishable"):
        kind = "sb_publishable (publishable key — wrong)"
    elif not trimmed:
        kind = "empty"
    else:
        kind = "unknown (not a JWT)"
    return {"len": len(trimmed), "kind": kind, "whitespace": trimmed != raw}


def load_products(base, key, limit, pending_only=True, select=None):
    out, offset, page = [], 0, 1000
    fields = select or "id,name,owner_id,image_url,metadata,reference"
    missing = "&image_url=eq." if pending_only else ""
    while True:
        url = (
            f"{base}/rest/v1/products?select={fields}"
            f"{missing}&order=created_at.asc&offset={offset}&limit={page}"
        )
        rows = json.loads(request(url, {"apikey": key, "Authorization": f"Bearer {key}"}).read())
        if not rows:
            break
        out.extend(rows)
        if limit and len(out) >= limit:
            return out[:limit]
        offset += page
        if len(rows) < page:
            break
    return out


def product_barcode(product):
    meta = product.get("metadata") or {}
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except ValueError:
            meta = {}
    barcode = str(meta.get("barcode") or "").strip()
    if not barcode:
        reference = str(product.get("reference") or "").strip()
        if re.fullmatch(r"\d{8,14}", reference):
            barcode = reference
    return barcode


# --- providers: each returns an image URL or None -------------------------

def off_by_barcode(barcode):
    if not barcode:
        return None
    url = f"https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=image_front_url,image_url"
    try:
        data = json.loads(request(url, timeout=15).read())
    except (urllib.error.URLError, ValueError, OSError):
        return None
    if data.get("status") != 1:
        return None
    product = data.get("product") or {}
    return product.get("image_front_url") or product.get("image_url")


def off_by_name(name):
    if not name:
        return None
    url = "https://world.openfoodfacts.org/cgi/search.pl?" + urllib.parse.urlencode(
        {"search_terms": name, "search_simple": 1, "action": "process", "json": 1, "page_size": 1}
    )
    try:
        data = json.loads(request(url, timeout=20).read())
    except (urllib.error.URLError, ValueError, OSError):
        return None
    products = data.get("products") or []
    if not products:
        return None
    first = products[0]
    if not title_matches(name, first.get("product_name")):
        return None
    return first.get("image_front_url") or first.get("image_url")


def google_images(query, api_key, cx):
    if not (api_key and cx and query):
        return None, None
    url = "https://customsearch.googleapis.com/customsearch/v1?" + urllib.parse.urlencode(
        {"key": api_key, "cx": cx, "q": query, "searchType": "image", "num": 1, "safe": "active"}
    )
    try:
        data = json.loads(request(url, timeout=20).read())
    except (urllib.error.URLError, ValueError, OSError):
        return None, None
    items = data.get("items") or []
    if not items:
        return None, None
    return items[0].get("link"), items[0].get("title", "")


def openverse_images(query):
    if not query:
        return None, None
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(
        {"q": query, "page_size": 1, "license_type": "commercial"}
    )
    try:
        data = json.loads(request(url, timeout=12, retries=1).read())
    except (urllib.error.URLError, ValueError, OSError):
        return None, None
    results = data.get("results") or []
    if not results:
        return None, None
    return results[0].get("url"), results[0].get("title", "")


def name_tokens(text):
    tokens = re.findall(r"[\u0600-\u06FF\w]{3,}", str(text or "").lower())
    return {t for t in tokens if not t.isdigit()}


def title_matches(name, title):
    """Reject an obvious mismatch from a name-based provider.

    Lenient by design: an empty title (provider gave none) is accepted, and
    only a title with zero shared significant tokens is rejected.
    """
    if not title:
        return True
    wanted = name_tokens(name)
    if not wanted:
        return True
    return bool(wanted & name_tokens(title))


def find_image(product, providers, google_key, google_cx, sleep):
    name = str(product.get("name") or "").strip()
    barcode = product_barcode(product)
    queries = [q for q in (name, f"{name} {barcode}".strip()) if q]
    for provider in providers:
        if provider == "off":
            found = off_by_barcode(barcode)
            if not found:
                found = off_by_name(name)
            if found:
                return found, "off_barcode"
            time.sleep(sleep)
        elif provider == "google":
            for query in ([barcode] if barcode else []) + queries:
                found, title = google_images(query, google_key, google_cx)
                time.sleep(sleep)
                if found and title_matches(name, title):
                    return found, "google_image"
        elif provider == "openverse":
            for query in queries:
                found, title = openverse_images(query)
                time.sleep(sleep)
                if found and title_matches(name, title):
                    return found, "openverse"
    return None, None


# --- download + upload -----------------------------------------------------

def download_image(image_url):
    try:
        response = request(image_url, timeout=40)
    except (urllib.error.URLError, OSError):
        return None
    content_type = response.headers.get("Content-Type", "")
    if not content_type.startswith("image/"):
        return None
    data = response.read(MAX_IMAGE_BYTES + 1)
    if not data or len(data) > MAX_IMAGE_BYTES:
        return None
    return data, content_type.split(";")[0].strip()


def extension_for(content_type, image_url):
    mapping = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif"}
    if content_type in mapping:
        return mapping[content_type]
    match = re.search(r"\.(jpe?g|png|webp|gif)(?:$|\?)", image_url, re.IGNORECASE)
    return match.group(1).lower().replace("jpeg", "jpg") if match else "jpg"


def service_headers(service_key, extra=None):
    """Headers for privileged calls.

    Legacy keys are JWTs and go in both `apikey` and `Authorization: Bearer`.
    The newer `sb_secret_...` keys must NOT be sent as a Bearer JWT.
    """
    headers = {"apikey": service_key}
    if str(service_key).startswith("eyJ"):
        headers["Authorization"] = f"Bearer {service_key}"
    headers.update(extra or {})
    return headers


def upload_object(base, service_key, path, data, content_type):
    url = f"{base}/storage/v1/object/{BUCKET}/{urllib.parse.quote(path)}"
    try:
        request(url, service_headers(service_key, {
            "Content-Type": content_type,
            "x-upsert": "true",
        }), method="POST", body=data, timeout=60).read()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as error:
        print(f"upload failed {path}: {error}", file=sys.stderr)
        return False
    return True


def patch_product(base, service_key, product_id, image_url):
    url = f"{base}/rest/v1/products?id=eq.{urllib.parse.quote(str(product_id))}"
    body = json.dumps({"image_url": image_url}).encode()
    try:
        request(url, service_headers(service_key, {
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        }), method="PATCH", body=body).read()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as error:
        print(f"patch failed {product_id}: {error}", file=sys.stderr)
        return False
    return True


def register_media_asset(base, service_key, owner_id, product_id, public_url, object_path, mime_type, source):
    url = f"{base}/rest/v1/media_assets?on_conflict=source,source_id"
    body = json.dumps([{
        "owner_id": owner_id,
        "entity_type": "product",
        "entity_id": str(product_id),
        "source": "supabase_storage",
        "source_id": object_path,
        "bucket": BUCKET,
        "object_path": object_path,
        "public_url": public_url,
        "mime_type": mime_type,
        "metadata": {"provider": source},
    }]).encode()
    try:
        request(url, service_headers(service_key, {
            "Content-Type": "application/json",
            "Prefer": "resolution=ignore-duplicates,return=minimal",
        }), method="POST", body=body).read()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as error:
        print(f"media_assets failed {product_id}: {error}", file=sys.stderr)


def probe_storage_write(base, service_key):
    path = f".probe/{int(time.time())}.txt"
    url = f"{base}/storage/v1/object/{BUCKET}/{urllib.parse.quote(path)}"
    try:
        request(url, service_headers(service_key, {
            "Content-Type": "text/plain",
            "x-upsert": "true",
        }), method="POST", body=b"probe", timeout=30)
        return "ok"
    except urllib.error.HTTPError as error:
        body = error.read()[:200].decode("utf-8", "replace")
        return f"http {error.code}: {body}"
    except (urllib.error.URLError, OSError) as error:
        return f"network: {error!r}"


def main():
    parser = argparse.ArgumentParser(description="Auto-attach product images.")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", DEFAULT_URL))
    parser.add_argument("--publishable-key", default=os.environ.get("SUPABASE_PUBLISHABLE_KEY", DEFAULT_PUBLISHABLE))
    parser.add_argument("--service-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--providers", default="off,google")
    parser.add_argument("--google-key", default=os.environ.get("GOOGLE_API_KEY", ""))
    parser.add_argument("--google-cx", default=os.environ.get("GOOGLE_CSE_CX", ""))
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--sleep", type=float, default=0.5)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check-key", action="store_true")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    if not args.dry_run and not args.service_key:
        sys.exit("SUPABASE_SERVICE_ROLE_KEY is required to apply (or pass --dry-run)")

    if args.check_key:
        print("service-key", json.dumps(key_diagnostics(args.service_key)))
        print("storage-write", probe_storage_write(args.url, args.service_key))
        return

    providers = [p.strip() for p in args.providers.split(",") if p.strip()]
    products = load_products(args.url, args.publishable_key, args.limit, pending_only=not args.overwrite)
    pending = [p for p in products if args.overwrite or not str(p.get("image_url") or "").strip()]
    print(f"products={len(products)} pending={len(pending)} providers={','.join(providers)} workers={args.workers}")

    lock = threading.Lock()
    state = {"done": 0, "applied": 0, "missed": 0, "failed": 0}
    resolved = {}

    def progress():
        print(
            f"[{state['done']}/{len(pending)}] applied={state['applied']} "
            f"missed={state['missed']} failed={state['failed']}",
            flush=True,
        )

    def process(product):
        try:
            image_url, source = find_image(product, providers, args.google_key, args.google_cx, args.sleep)
            if not image_url:
                return "missed", None, None
            if args.dry_run:
                return "applied", image_url, None
            downloaded = download_image(image_url)
            if not downloaded:
                return "missed", None, None
            data, content_type = downloaded
            digest = hashlib.sha256(data).hexdigest()[:12]
            object_path = f"{product.get('owner_id') or 'catalog'}/{product['id']}-{digest}.{extension_for(content_type, image_url)}"
            if not upload_object(args.url, args.service_key, object_path, data, content_type):
                return "failed", None, None
            public_url = f"{args.url}/storage/v1/object/public/{BUCKET}/{urllib.parse.quote(object_path)}"
            if not patch_product(args.url, args.service_key, product["id"], public_url):
                return "failed", None, None
            register_media_asset(
                args.url, args.service_key, product.get("owner_id") or "",
                product["id"], public_url, object_path, content_type, source,
            )
            return "applied", image_url, public_url
        except Exception as error:  # noqa: BLE001 - one bad product must not stop the batch
            print(f"error {product.get('id')}: {error!r}", file=sys.stderr)
            return "failed", None, None

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futures = {pool.submit(process, product): product for product in pending}
        for future in as_completed(futures):
            product = futures[future]
            status, image_url, public_url = future.result()
            with lock:
                state["done"] += 1
                state[status] += 1
                if status == "applied":
                    resolved[str(product["id"])] = public_url or image_url
                if state["done"] % 25 == 0 or state["done"] == len(pending):
                    progress()

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(resolved, handle, ensure_ascii=False, indent=2)
    print(f"DONE applied={state['applied']} missed={state['missed']} failed={state['failed']} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
