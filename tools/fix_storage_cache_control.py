#!/usr/bin/env python3
"""Set a durable cacheControl on storage objects that were uploaded without one.

Supabase serves a public object with `Cache-Control: private, no-cache` when the
upload did not set cacheControl, so every view costs a conditional request. The
client uploaders now set it, but objects already in the bucket keep whatever
they were stored with.

Supabase exposes no metadata-only update for objects, so this re-uploads the
same bytes to the same path with `x-upsert: true` and the cache-control header.
The URL is unchanged; only the stored metadata changes.

    export SUPABASE_SERVICE_ROLE_KEY=...
    python3 tools/fix_storage_cache_control.py --dry-run
    python3 tools/fix_storage_cache_control.py --limit 3
    python3 tools/fix_storage_cache_control.py

Only objects referenced by a product row are considered, so buckets are never
rewritten wholesale. Pass --bucket to restrict further.
"""

import argparse
import concurrent.futures
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUPABASE_DART = os.path.join(REPO_ROOT, "lib", "services", "supabase_service.dart")
PUBLIC_MARKER = "/storage/v1/object/public/"
MAX_AGE = "31536000"


def dart_default(pattern):
    with open(SUPABASE_DART, encoding="utf-8") as handle:
        match = re.search(pattern, handle.read())
    return match.group(1) if match else ""


DEFAULT_URL = dart_default(r"projectUrl[\s\S]*?defaultValue:\s*'(https://[^']+)'")
PUBLISHABLE_KEY = dart_default(r"_defaultPublishableKey\s*=\s*'([^']+)'")


def api(path, url, key, method="GET", body=None, headers=None):
    request = urllib.request.Request(
        f"{url}{path}",
        data=body,
        method=method,
        headers={"apikey": key, "Authorization": f"Bearer {key}", **(headers or {})},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def load_product_images(url, key):
    """Every non-empty product image_url, paged past the PostgREST 1000-row cap."""
    found, offset = {}, 0
    while True:
        query = (
            "/rest/v1/products?select=id,image_url&image_url=neq.&order=id"
            f"&limit=1000&offset={offset}"
        )
        rows = json.loads(api(query, url, key))
        if not rows:
            break
        for row in rows:
            found[row["id"]] = row["image_url"]
        if len(rows) < 1000:
            break
        offset += 1000
    return found


def split_storage_url(image_url):
    """Return (bucket, object_path) for a public storage URL, else None."""
    parsed = urllib.parse.urlparse(image_url)
    if PUBLIC_MARKER not in parsed.path:
        return None
    remainder = parsed.path.split(PUBLIC_MARKER, 1)[1]
    if "/" not in remainder:
        return None
    bucket, path = remainder.split("/", 1)
    return bucket, urllib.parse.unquote(path)


def current_cache_control(public_url):
    try:
        with urllib.request.urlopen(urllib.request.Request(public_url, method="HEAD"), timeout=45) as r:
            return r.headers.get("cache-control")
    except Exception as error:  # noqa: BLE001 - report, never abort the sweep
        return f"ERR:{type(error).__name__}"


def needs_fix(cache_control):
    return not cache_control or "no-cache" in cache_control or "ERR:" in cache_control


def rewrite(bucket, path, public_url, url, key):
    """Re-upload identical bytes with a cache-control header. Returns a status."""
    try:
        with urllib.request.urlopen(public_url, timeout=90) as response:
            payload = response.read()
            content_type = response.headers.get("content-type") or "application/octet-stream"
    except Exception as error:  # noqa: BLE001
        return f"download-failed:{type(error).__name__}"

    endpoint = f"/storage/v1/object/{bucket}/{urllib.parse.quote(path)}"
    try:
        api(
            endpoint,
            url,
            key,
            method="POST",
            body=payload,
            headers={
                "Content-Type": content_type,
                "Cache-Control": f"max-age={MAX_AGE}",
                "x-upsert": "true",
            },
        )
    except urllib.error.HTTPError as error:
        return f"upload-{error.code}"
    except Exception as error:  # noqa: BLE001
        return f"upload-failed:{type(error).__name__}"

    after = current_cache_control(public_url)
    return f"ok:{after}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", DEFAULT_URL))
    parser.add_argument("--service-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--bucket", default="", help="only this bucket")
    parser.add_argument("--limit", type=int, default=0, help="max objects to rewrite (0 = all)")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json-out", default="")
    args = parser.parse_args()

    if not args.dry_run and not args.service_key:
        sys.exit("SUPABASE_SERVICE_ROLE_KEY is required to rewrite (or pass --dry-run)")

    read_key = args.service_key or PUBLISHABLE_KEY
    images = load_product_images(args.url, read_key)
    targets = {}
    for image_url in images.values():
        parts = split_storage_url(image_url)
        if not parts:
            continue
        bucket, path = parts
        if args.bucket and bucket != args.bucket:
            continue
        targets[(bucket, path)] = image_url

    print(f"products with an image: {len(images)}")
    print(f"distinct storage objects referenced: {len(targets)}")

    with concurrent.futures.ThreadPoolExecutor(12) as pool:
        headers = list(pool.map(lambda item: current_cache_control(item[1]), targets.items()))
    stale = [(item, cc) for item, cc in zip(targets.items(), headers) if needs_fix(cc)]
    print(f"objects served no-cache (or unreadable): {len(stale)}")
    if args.limit:
        stale = stale[: args.limit]

    if args.dry_run:
        for (bucket, path), cc in stale[:10]:
            print(f"  would rewrite {bucket}/{path}  (now: {cc})")
        print(f"DRY RUN: would rewrite {len(stale)} objects")
        return

    results = {}
    with concurrent.futures.ThreadPoolExecutor(max(1, args.workers)) as pool:
        futures = {
            pool.submit(rewrite, bucket, path, image_url, args.url, args.service_key): (bucket, path)
            for (bucket, path), _ in stale
            for image_url in [targets[(bucket, path)]]
        }
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            results[f"{key[0]}/{key[1]}"] = future.result()

    ok = sum(1 for v in results.values() if v.startswith("ok:max-age"))
    other = {k: v for k, v in results.items() if not v.startswith("ok:max-age")}
    print(f"DONE rewritten={ok} needs_attention={len(other)}")
    for name, status in list(other.items())[:15]:
        print(f"  {status}  {name}")
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(results, handle, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
