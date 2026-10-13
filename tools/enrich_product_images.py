#!/usr/bin/env python3
"""Backfill product images from Open Food Facts.

Reads the live catalog, looks up each product's barcode in the Open Food
Facts / Open Beauty Facts / Open Products Facts databases, and writes the
resolved image back to `products.image_url`.

Reads use the publishable key (read-only). Writes require a service-role
key, which is never stored in the repository:

    export SUPABASE_SERVICE_ROLE_KEY=...      # required to apply
    python3 tools/enrich_product_images.py --dry-run
    python3 tools/enrich_product_images.py --limit 200

Notes
-----
* Coverage is bounded by Open Food Facts. Gulf/Middle-East SKUs (barcodes
  starting 628/629/694/885) are only partially indexed there, so expect a
  minority hit rate; the rest need merchant uploads or a paid data source.
* Safe to re-run: products that already have an image are skipped.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUPABASE_DART = os.path.join(REPO_ROOT, "lib", "services", "supabase_service.dart")


def dart_default(pattern):
    with open(SUPABASE_DART, encoding="utf-8") as handle:
        match = re.search(pattern, handle.read())
    return match.group(1) if match else ""


DEFAULT_URL = dart_default(r"projectUrl[\s\S]*?defaultValue:\s*'(https://[^']+)'")
DEFAULT_PUBLISHABLE = dart_default(r"_defaultPublishableKey\s*=\s*'([^']+)'")
FACTS_DOMAINS = (
    "world.openfoodfacts.org",
    "world.openbeautyfacts.org",
    "world.openproductsfacts.org",
)
UA = {"User-Agent": "AlfaeqYemenCatalogBot/1.0 (catalog enrichment)"}


def _request(url, headers, method="GET", body=None, timeout=40):
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=timeout)


def load_products(base, key, page_size=1000):
    products, offset = [], 0
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    while True:
        url = (f"{base}/rest/v1/products?select=id,name,image_url,metadata"
               f"&status=eq.active&order=id&limit={page_size}&offset={offset}")
        rows = json.loads(_request(url, headers).read().decode())
        if not rows:
            break
        products.extend(rows)
        offset += len(rows)
        if len(rows) < page_size:
            break
    return products


def lookup_image(barcode, timeout=8):
    # OFF returns 200 with status=0 for unknown barcodes and 429 when rate
    # limited; 429 is the only case worth retrying.
    for domain in FACTS_DOMAINS:
        url = f"https://{domain}/api/v2/product/{barcode}.json?fields=image_front_url,image_url"
        try:
            data = json.loads(_request(url, UA, timeout=timeout).read().decode())
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                time.sleep(5)
            continue
        except Exception:
            continue
        if data.get("status") == 1:
            product = data.get("product") or {}
            image = product.get("image_front_url") or product.get("image_url")
            if image:
                return image
    return None


def apply_image(base, service_key, product_id, image_url):
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    url = f"{base}/rest/v1/products?id=eq.{urllib.parse.quote(product_id)}"
    body = json.dumps({"image_url": image_url}).encode()
    _request(url, headers, method="PATCH", body=body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", DEFAULT_URL))
    parser.add_argument("--publishable-key",
                        default=os.environ.get("SUPABASE_PUBLISHABLE_KEY", DEFAULT_PUBLISHABLE))
    parser.add_argument("--service-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--limit", type=int, default=0, help="max products to attempt (0 = all)")
    parser.add_argument("--sleep", type=float, default=0.4, help="seconds between lookups")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--out", default="", help="write resolved {product_id: image_url} JSON here")
    args = parser.parse_args()

    if not args.dry_run and not args.service_key:
        sys.exit("SUPABASE_SERVICE_ROLE_KEY is required to apply (or pass --dry-run)")

    products = load_products(args.url, args.service_key or args.publishable_key)
    pending = [p for p in products
               if not (p.get("image_url") or "").strip()
               and ((p.get("metadata") or {}).get("barcode") or "").strip()]
    if args.limit:
        pending = pending[:args.limit]
    print(f"products={len(products)} pending_with_barcode={len(pending)}", flush=True)

    resolved = {}
    applied = missed = failed = 0
    for i, product in enumerate(pending, 1):
        barcode = (product["metadata"].get("barcode") or "").strip()
        image = lookup_image(barcode)
        if image:
            resolved[product["id"]] = image
            if args.dry_run:
                print(f"[dry] {product['id']} {barcode} -> {image}", flush=True)
            else:
                try:
                    apply_image(args.url, args.service_key, product["id"], image)
                except Exception as exc:  # noqa: BLE001 - keep going, report at end
                    failed += 1
                    print(f"[fail] {product['id']}: {exc}", flush=True)
                    time.sleep(args.sleep)
                    continue
            applied += 1
        else:
            missed += 1
        if i % 50 == 0:
            print(f"...{i}/{len(pending)} applied={applied} missed={missed} failed={failed}", flush=True)
            if args.out:
                json.dump(resolved, open(args.out, "w"))
        time.sleep(args.sleep)

    if args.out:
        json.dump(resolved, open(args.out, "w"))
    print(f"DONE applied={applied} missed={missed} failed={failed} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
