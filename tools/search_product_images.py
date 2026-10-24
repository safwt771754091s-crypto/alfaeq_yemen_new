#!/usr/bin/env python3
"""Attach product images found by web image search, matched strictly by name.

Unlike tools/auto_product_images.py (which accepts a single shared token and
therefore attaches pictures of *other* brands), this tool only accepts an image
when its result title contains *every* significant token of the product name
(digits, weights and packaging words are ignored). An image whose URL contains
the product barcode is accepted outright.

Search providers, in order:
  1. Google Programmable Search (needs GOOGLE_API_KEY + GOOGLE_CSE_CX).
  2. DuckDuckGo image search via the `ddgs` package (free, no key).

Writes require a service-role key, which is never stored in the repository:

    export SUPABASE_SERVICE_ROLE_KEY=...
    python3 tools/search_product_images.py --dry-run --limit 40
    python3 tools/search_product_images.py --limit 200

Only confidently matched products are written. Everything else is written to a
review report so a human can decide. Idempotent: products that already have an
image are skipped unless --overwrite is given.
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
MAX_IMAGE_BYTES = 6 * 1024 * 1024
USER_AGENT = "Mozilla/5.0 (compatible; AlfaeqYemenImageBot/1.0)"
BARCODE_RE = re.compile(r"\d{8,14}")

# Social/pinboard hosts carry collages and unrelated pictures far too often to
# trust for a storefront; they are only accepted when the URL itself proves the
# match by containing the barcode.
BLOCKED_HOSTS = (
    "pinimg.com", "pinterest.", "fbcdn.net", "facebook.", "cdninstagram.com",
    "instagram.", "twimg.com", "twitter.", "tiktokcdn", "redd.it", "reddit.",
    "ytimg.com", "lookaside.", "licdn.com",
)

# Packaging words carry no brand/identity information and must not be required
# to appear in the result title.
STOPWORDS = {
    "جم", "مل", "كجم", "لتر", "حبه", "حبة", "علبه", "علبة", "كيس", "كيسه",
    "عدد", "منوع", "كبير", "صغير", "وسط", "باكت", "كرتون", "عبوه", "عبوة",
    "ملي", "جرام", "قرام", "دبه", "دبة", "انواع", "نوع", "ملفوف", "ساده",
    "جديد", "سعر", "عرض", "حجم", "وزن", "قطع", "قطعة", "اكياس", "علب",
    "كرتونة", "طقم", "حبات", "باكيت", "علاقة", "و", "في", "من", "علي",
    "الى", "مع", "ال", "بلاستيك", "ورق",
}


def dart_default(pattern):
    with open(SUPABASE_DART, encoding="utf-8") as handle:
        match = re.search(pattern, handle.read())
    return match.group(1) if match else ""


DEFAULT_URL = dart_default(r"projectUrl[\s\S]*?defaultValue:\s*'(https://[^']+)'")
DEFAULT_PUBLISHABLE = dart_default(r"_defaultPublishableKey\s*=\s*'([^']+)'")


def safe_url(url):
    """Percent-encode non-ASCII (e.g. Arabic file names) without touching structure."""
    return urllib.parse.quote(str(url), safe=":/?&=#%[]@!$&'()*+,;~")


def request(url, headers, method="GET", body=None, timeout=40, retries=1):
    last = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(safe_url(url), data=body, headers=headers, method=method)
            return urllib.request.urlopen(req, timeout=timeout)
        except (urllib.error.URLError, OSError) as error:
            last = error
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    raise last


def load_products(base, key, limit=0, pending_only=True):
    products, offset, page = [], 0, 1000
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    while True:
        flt = "&image_url=eq." if pending_only else ""
        url = (
            f"{base}/rest/v1/products?select=id,name,image_url,metadata"
            f"&status=eq.active{flt}&order=id&limit={page}&offset={offset}"
        )
        rows = json.loads(request(url, headers).read().decode())
        if not rows:
            break
        products.extend(rows)
        offset += len(rows)
        if len(rows) < page or (limit and len(products) >= limit):
            break
    return products[:limit] if limit else products


def product_barcode(product):
    meta = product.get("metadata")
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except ValueError:
            meta = {}
    value = (meta or {}).get("barcode")
    text = str(value).strip() if value is not None else ""
    return text if BARCODE_RE.fullmatch(text) else ""


def normalize(text):
    text = str(text or "")
    text = re.sub(r"[\u064B-\u065F\u0670]", "", text)
    for src, dst in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه"),
                     ("ؤ", "و"), ("ئ", "ي")):
        text = text.replace(src, dst)
    return text.lower()


def core_tokens(text):
    tokens = re.findall(r"[\u0600-\u06FF\w]{2,}", normalize(text))
    out = []
    for token in tokens:
        if token.isdigit() or re.search(r"\d", token) or token in STOPWORDS:
            continue
        out.append(token)
    return out


def score(name, title, barcode, url):
    """Return (score, reason). Score 1.0 means every core token is present."""
    wanted = core_tokens(name)
    if barcode and barcode in str(url):
        return 1.0, "barcode_in_url"
    if any(host in str(url).lower() for host in BLOCKED_HOSTS):
        return 0.0, "blocked_host"
    if not wanted:
        return 0.0, "no_name_tokens"
    if len(set(wanted)) < 2:
        # A single generic word ("ضغاط", "سمن") matches dozens of unrelated
        # products; require the barcode to prove such short names.
        return 0.0, "too_generic"
    present = set(core_tokens(title))
    missing = [t for t in wanted if t not in present]
    if not missing:
        return 1.0, "full_name"
    return 1 - len(set(missing)) / len(set(wanted)), "missing:" + ",".join(missing[:4])


def google_images(query, api_key, cx, count=10):
    if not (api_key and cx and query):
        return []
    url = "https://customsearch.googleapis.com/customsearch/v1?" + urllib.parse.urlencode(
        {"key": api_key, "cx": cx, "q": query, "searchType": "image",
         "num": min(count, 10), "safe": "active"}
    )
    try:
        data = json.loads(request(url, {}, timeout=20).read().decode())
    except (urllib.error.URLError, ValueError, OSError):
        return []
    return [(item.get("link"), item.get("title", "")) for item in (data.get("items") or [])]


def duckduckgo_images(query, count=12):
    try:
        from ddgs import DDGS
    except ImportError:
        return []
    out = []
    try:
        with DDGS() as search:
            for item in search.images(query, max_results=count):
                out.append((item.get("image"), item.get("title", "")))
    except Exception:  # noqa: BLE001 - a flaky provider must not stop the batch
        return out
    return out


def candidates(product, providers, google_key, google_cx, sleep):
    name = str(product.get("name") or "").strip()
    barcode = product_barcode(product)
    queries = [q for q in (f"{name} {barcode}".strip(), name) if q]
    seen, out = set(), []
    for provider in providers:
        for query in queries:
            if provider == "google":
                found = google_images(query, google_key, google_cx)
            elif provider == "ddg":
                found = duckduckgo_images(query)
            else:
                continue
            for url, title in found:
                if url and url not in seen:
                    seen.add(url)
                    out.append((url, title))
            time.sleep(sleep)
    return out


def download_image(image_url):
    try:
        response = request(image_url, {"User-Agent": USER_AGENT}, timeout=40)
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
            "Cache-Control": "max-age=31536000",
            "x-upsert": "true",
        }), method="POST", body=data, timeout=60).read()
    except urllib.error.HTTPError as error:
        detail = error.read()[:300].decode("utf-8", "replace")
        print(f"upload failed {path}: HTTP {error.code} {detail}", file=sys.stderr)
        return False
    except (urllib.error.URLError, OSError) as error:
        print(f"upload failed {path}: {error}", file=sys.stderr)
        return False
    return True


def probe_storage_write(base, service_key):
    path = f".probe/{int(time.time())}.txt"
    url = f"{base}/storage/v1/object/{BUCKET}/{urllib.parse.quote(path)}"
    try:
        request(url, service_headers(service_key, {
            "Content-Type": "text/plain", "x-upsert": "true",
        }), method="POST", body=b"probe", timeout=30)
        return "ok"
    except urllib.error.HTTPError as error:
        return f"http {error.code}: {error.read()[:200].decode('utf-8', 'replace')}"
    except (urllib.error.URLError, OSError) as error:
        return f"network: {error!r}"


def patch_product(base, service_key, product_id, image_url):
    url = f"{base}/rest/v1/products?id=eq.{urllib.parse.quote(str(product_id))}"
    body = json.dumps({"image_url": image_url}).encode()
    try:
        request(url, service_headers(service_key, {
            "Content-Type": "application/json", "Prefer": "return=minimal",
        }), method="PATCH", body=body).read()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as error:
        print(f"patch failed {product_id}: {error}", file=sys.stderr)
        return False
    return True


def register_media_asset(base, service_key, owner_id, product_id, public_url,
                         object_path, mime_type, source):
    url = f"{base}/rest/v1/media_assets?on_conflict=source,source_id"
    body = json.dumps([{
        "owner_id": owner_id or "",
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


def main():
    parser = argparse.ArgumentParser(description="Attach images matched strictly by name.")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL") or DEFAULT_URL)
    parser.add_argument("--publishable-key",
                        default=os.environ.get("SUPABASE_PUBLISHABLE_KEY") or DEFAULT_PUBLISHABLE)
    parser.add_argument("--service-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--providers", default="google,ddg")
    parser.add_argument("--google-key", default=os.environ.get("GOOGLE_API_KEY", ""))
    parser.add_argument("--google-cx", default=os.environ.get("GOOGLE_CSE_CX", ""))
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--min-score", type=float, default=1.0,
                        help="accept threshold; 1.0 = every core name token must appear")
    parser.add_argument("--sleep", type=float, default=0.4)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check-key", action="store_true")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    if args.check_key:
        print("storage-write:", probe_storage_write(args.url, args.service_key))
        return

    if not args.dry_run and not args.service_key:
        sys.exit("SUPABASE_SERVICE_ROLE_KEY is required to apply (or pass --dry-run)")

    providers = [p.strip() for p in args.providers.split(",") if p.strip()]
    products = load_products(args.url, args.publishable_key, args.limit,
                             pending_only=not args.overwrite)
    pending = [p for p in products if args.overwrite or not str(p.get("image_url") or "").strip()]
    print(f"products={len(products)} pending={len(pending)} "
          f"providers={','.join(providers)} min_score={args.min_score} workers={args.workers}")

    lock = threading.Lock()
    state = {"done": 0, "applied": 0, "review": 0, "missed": 0, "failed": 0}
    resolved, review = {}, {}

    def process(product):
        try:
            found = candidates(product, providers, args.google_key, args.google_cx, args.sleep)
            if not found:
                return "missed", None, None
            ranked = sorted(
                ((score(product["name"], title, product_barcode(product), url), url, title)
                 for url, title in found),
                key=lambda item: -item[0][0],
            )
            (best_score, reason), image_url, title = ranked[0]
            if best_score < args.min_score:
                return "review", image_url, {"reason": reason, "score": round(best_score, 3),
                                             "title": title}
            if args.dry_run:
                return "applied", image_url, {"reason": reason, "score": best_score, "title": title}
            downloaded = download_image(image_url)
            if not downloaded:
                return "missed", None, None
            data, content_type = downloaded
            digest = hashlib.sha256(data).hexdigest()[:12]
            object_path = (f"{product.get('owner_id') or 'catalog'}/{product['id']}-"
                           f"{digest}.{extension_for(content_type, image_url)}")
            if not upload_object(args.url, args.service_key, object_path, data, content_type):
                return "failed", None, None
            public_url = (f"{args.url}/storage/v1/object/public/{BUCKET}/"
                          f"{urllib.parse.quote(object_path)}")
            if not patch_product(args.url, args.service_key, product["id"], public_url):
                return "failed", None, None
            register_media_asset(args.url, args.service_key, product.get("owner_id") or "",
                                 product["id"], public_url, object_path, content_type, reason)
            return "applied", public_url, {"reason": reason, "score": best_score, "title": title}
        except Exception as error:  # noqa: BLE001 - one bad product must not stop the batch
            print(f"error {product.get('id')}: {error!r}", file=sys.stderr)
            return "failed", None, None

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futures = {pool.submit(process, product): product for product in pending}
        for future in as_completed(futures):
            product = futures[future]
            status, value, meta = future.result()
            with lock:
                state["done"] += 1
                state[status] += 1
                if status == "applied":
                    resolved[str(product["id"])] = value
                elif status == "review":
                    review[str(product["id"])] = {"name": product["name"], **(meta or {})}
                if state["done"] % 25 == 0 or state["done"] == len(pending):
                    print(f"[{state['done']}/{len(pending)}] applied={state['applied']} "
                          f"review={state['review']} missed={state['missed']} "
                          f"failed={state['failed']}", flush=True)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump({"applied": resolved, "review": review}, handle,
                      ensure_ascii=False, indent=2)
    print(f"DONE applied={state['applied']} review={state['review']} "
          f"missed={state['missed']} failed={state['failed']} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
