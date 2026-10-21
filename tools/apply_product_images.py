#!/usr/bin/env python3
"""Apply a saved product image map to Supabase without re-running lookups.

Companion to tools/enrich_product_images.py. That tool can produce a
`{product_id: image_url}` JSON with `--out` while running read-only; this
script applies that map later, which is much faster than repeating the
Open Food Facts lookups.

Writes require a service-role key (never stored in the repository):

    export SUPABASE_SERVICE_ROLE_KEY=...
    python3 tools/apply_product_images.py --map product_images_map.json
    python3 tools/apply_product_images.py --map product_images_map.json --dry-run
"""

import argparse
import json
import os
import re
import sys
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


def main():
    parser = argparse.ArgumentParser(description="Apply a saved product image map.")
    parser.add_argument("--map", required=True, help="JSON file: {product_id: image_url}")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", DEFAULT_URL))
    parser.add_argument("--service-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(args.map, encoding="utf-8") as handle:
        mapping = json.load(handle)
    if not isinstance(mapping, dict) or not mapping:
        sys.exit("map file must be a non-empty JSON object of {product_id: image_url}")

    if not args.dry_run and not args.service_key:
        sys.exit("SUPABASE_SERVICE_ROLE_KEY is required to apply (or pass --dry-run)")

    applied = failed = 0
    for product_id, image_url in mapping.items():
        if args.dry_run:
            applied += 1
            continue
        body = json.dumps({"image_url": image_url}).encode()
        request = urllib.request.Request(
            f"{args.url}/rest/v1/products?id=eq.{urllib.parse.quote(str(product_id))}",
            data=body,
            method="PATCH",
            headers={
                "apikey": args.service_key,
                "Authorization": f"Bearer {args.service_key}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
        )
        try:
            urllib.request.urlopen(request, timeout=30).read()
            applied += 1
        except urllib.error.HTTPError as error:
            failed += 1
            print(f"failed {product_id}: {error.code} {error.read()[:120]!r}", file=sys.stderr)

    print(f"DONE applied={applied} failed={failed} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
