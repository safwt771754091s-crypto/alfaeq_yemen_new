#!/usr/bin/env python3
"""Export the Alfaeq Yemen product catalog (with images) to a Google Sheet.

Reads products from Supabase, resolves a missing image for each product the
same way tools/auto_product_images.py does (Open Food Facts by barcode/name,
then Google Programmable Search, then Openverse), and writes one row per
product to a Google Sheet. The image column is written as an ``=IMAGE("...")``
formula so the picture is rendered inside the sheet.

Auth uses a Google service account (Sheets API). The RS256 JWT is signed with
the ``openssl`` binary, so no third-party Python packages are required.

Environment / flags
-------------------
  GOOGLE_SERVICE_ACCOUNT_JSON   service-account key JSON (raw or base64)
  GOOGLE_SHEETS_DOCUMENT_ID     target spreadsheet id (or --spreadsheet-id)
  GOOGLE_SHEETS_TAB             tab name (default "Products")
  GOOGLE_API_KEY / GOOGLE_CSE_CX  optional image search keys
  SUPABASE_PUBLISHABLE_KEY      read key (falls back to the app's default)

  python3 tools/export_catalog_to_sheets.py --dry-run --limit 20
  python3 tools/export_catalog_to_sheets.py --limit 0        # everything
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auto_product_images as catalog  # noqa: E402

SHEETS_API = "https://sheets.googleapis.com/v4/spreadsheets"
DRIVE_API = "https://www.googleapis.com/drive/v3/files"
TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive"

COLUMNS = [
    "id", "name", "description", "price", "currency",
    "sale_unit", "unit_label", "base_unit", "unit_scale", "min_order_base",
    "stock", "status", "section_id", "store_id", "reference", "barcode",
    "image_url", "image", "image_source", "updated_at",
]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def load_service_account(raw, path):
    if path:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read()
    if not raw:
        sys.exit("GOOGLE_SERVICE_ACCOUNT_JSON (or --service-account-file) is required")
    raw = raw.strip()
    if not raw.startswith("{"):
        try:
            raw = base64.b64decode(raw).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            pass
    try:
        info = json.loads(raw)
    except ValueError as error:
        sys.exit(f"service account JSON is invalid: {error}")
    for field in ("client_email", "private_key", "token_uri"):
        if not info.get(field):
            sys.exit(f"service account JSON is missing '{field}'")
    return info


def access_token(info):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps({
        "iss": info["client_email"],
        "scope": SCOPE,
        "aud": info.get("token_uri", TOKEN_URL),
        "iat": now,
        "exp": now + 3600,
    }, separators=(",", ":")).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as key_file:
        key_file.write(info["private_key"])
        key_path = key_file.name
    try:
        with tempfile.NamedTemporaryFile(delete=False) as in_file:
            in_file.write(signing_input)
            in_path = in_file.name
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path, in_path],
            check=True, capture_output=True,
        ).stdout
    finally:
        for path in (key_path, in_path):
            try:
                os.unlink(path)
            except OSError:
                pass
    assertion = f"{header}.{claims}.{b64url(signature)}"
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    request = urllib.request.Request(
        info.get("token_uri", TOKEN_URL), data=body, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request, timeout=40) as response:
        return json.loads(response.read())["access_token"]


def sheets_call(token, url, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    return urllib.request.urlopen(request, timeout=60)


def create_spreadsheet(token, title, tab, folder_id=""):
    body = {"properties": {"title": title}, "sheets": [{"properties": {"title": tab}}]}
    data = json.loads(sheets_call(token, SHEETS_API, "POST", body).read())
    spreadsheet_id = data["spreadsheetId"]
    if folder_id:
        url = (f"{DRIVE_API}/{spreadsheet_id}?addParents={urllib.parse.quote(folder_id)}"
               "&supportsAllDrives=true&fields=id,parents")
        sheets_call(token, url, "PATCH", {})
    return spreadsheet_id


def share_file(token, file_id, email, role="writer"):
    body = {"type": "user", "role": role, "emailAddress": email}
    url = f"{DRIVE_API}/{file_id}/permissions?sendNotificationEmail=false&supportsAllDrives=true"
    sheets_call(token, url, "POST", body)


def ensure_tab(token, spreadsheet_id, tab):
    meta = json.loads(sheets_call(token, f"{SHEETS_API}/{spreadsheet_id}?fields=sheets.properties").read())
    titles = {s["properties"]["title"] for s in meta.get("sheets", [])}
    if tab in titles:
        return
    sheets_call(token, f"{SHEETS_API}/{spreadsheet_id}:batchUpdate", "POST", {
        "requests": [{"addSheet": {"properties": {"title": tab}}}],
    })


def write_values(token, spreadsheet_id, tab, values):
    range_ = urllib.parse.quote(f"{tab}!A1", safe="")
    url = f"{SHEETS_API}/{spreadsheet_id}/values/{range_}?valueInputOption=USER_ENTERED"
    sheets_call(token, url, "PUT", {"range": f"{tab}!A1", "majorDimension": "ROWS", "values": values})


def image_formula(url):
    return f'=IMAGE("{url}")' if url else ""


def product_row(product, image_url, source):
    meta = product.get("metadata") or {}
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except ValueError:
            meta = {}
    def cell(key, default=""):
        value = product.get(key)
        return default if value is None else value
    return [
        str(product.get("id") or ""),
        str(product.get("name") or ""),
        str(product.get("description") or ""),
        cell("price"),
        str(product.get("currency") or ""),
        str(product.get("sale_unit") or ""),
        str(product.get("unit_label") or ""),
        str(product.get("base_unit") or ""),
        cell("unit_scale"),
        cell("min_order_base"),
        cell("stock"),
        str(product.get("status") or ""),
        str(product.get("section_id") or ""),
        str(product.get("store_id") or ""),
        str(product.get("reference") or ""),
        str(meta.get("barcode") or ""),
        image_url or "",
        image_formula(image_url),
        source or "",
        str(product.get("updated_at") or ""),
    ]


def main():
    parser = argparse.ArgumentParser(description="Export products + images to Google Sheets.")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", catalog.DEFAULT_URL))
    parser.add_argument("--publishable-key", default=os.environ.get("SUPABASE_PUBLISHABLE_KEY", catalog.DEFAULT_PUBLISHABLE))
    parser.add_argument("--spreadsheet-id", default=os.environ.get("GOOGLE_SHEETS_DOCUMENT_ID", os.environ.get("ALFAEQ_GOOGLE_SHEETS_DOCUMENT_ID", "")))
    parser.add_argument("--tab", default=os.environ.get("GOOGLE_SHEETS_TAB", "Products"))
    parser.add_argument("--service-account-file", default="")
    parser.add_argument("--providers", default="off,google")
    parser.add_argument("--google-key", default=os.environ.get("GOOGLE_API_KEY", ""))
    parser.add_argument("--google-cx", default=os.environ.get("GOOGLE_CSE_CX", ""))
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workers", type=int, default=10)
    parser.add_argument("--sleep", type=float, default=0.1)
    parser.add_argument("--title", default=os.environ.get("GOOGLE_SHEETS_TITLE", "Alfaeq Yemen — Catalog"))
    parser.add_argument("--share-with", default=os.environ.get("GOOGLE_SHEETS_SHARE_WITH", ""))
    parser.add_argument("--folder-id", default=os.environ.get("GOOGLE_DRIVE_FOLDER_ID", ""))
    parser.add_argument("--create", action="store_true", help="create a new spreadsheet owned by the service account")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    providers = [p.strip() for p in args.providers.split(",") if p.strip()]
    products = catalog.load_products(
        args.url, args.publishable_key, args.limit, pending_only=False,
        select="id,name,description,price,currency,stock,status,section_id,store_id,"
               "reference,image_url,metadata,updated_at,sale_unit,unit_label,base_unit,"
               "unit_scale,min_order_base",
    )
    print(f"products={len(products)} providers={','.join(providers)} tab={args.tab}", flush=True)

    rows = {}
    state = {"done": 0, "resolved": 0}
    lock = threading.Lock()

    def resolve(product):
        current = str(product.get("image_url") or "").strip()
        if current:
            return product["id"], current, "supabase"
        found, source = catalog.find_image(product, providers, args.google_key, args.google_cx, args.sleep)
        return product["id"], found or "", source or ""

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futures = [pool.submit(resolve, product) for product in products]
        for future in as_completed(futures):
            pid, image_url, source = future.result()
            rows[pid] = (image_url, source)
            with lock:
                state["done"] += 1
                if image_url:
                    state["resolved"] += 1
                if state["done"] % 100 == 0 or state["done"] == len(products):
                    print(f"[{state['done']}/{len(products)}] with_image={state['resolved']}", flush=True)

    values = [COLUMNS]
    for product in products:
        image_url, source = rows.get(product["id"], ("", ""))
        values.append(product_row(product, image_url, source))

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(values, handle, ensure_ascii=False, indent=2)

    if args.dry_run:
        print(f"DONE rows={len(values) - 1} with_image={state['resolved']} dry_run=True")
        return

    info = load_service_account(os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", ""), args.service_account_file)
    token = access_token(info)

    spreadsheet_id = args.spreadsheet_id
    if not spreadsheet_id:
        if not args.create:
            sys.exit("Provide --spreadsheet-id (or GOOGLE_SHEETS_DOCUMENT_ID), or pass --create")
        spreadsheet_id = create_spreadsheet(token, args.title, args.tab, args.folder_id)
        print(f"created spreadsheet {spreadsheet_id}")
        print(f"created https://docs.google.com/spreadsheets/d/{spreadsheet_id}/edit")

    if args.share_with:
        share_file(token, spreadsheet_id, args.share_with)
        print(f"shared with {args.share_with}")

    ensure_tab(token, spreadsheet_id, args.tab)
    write_values(token, spreadsheet_id, args.tab, values)
    print(f"DONE rows={len(values) - 1} with_image={state['resolved']} dry_run=False")
    print(f"sheet https://docs.google.com/spreadsheets/d/{spreadsheet_id}/edit#gid=0")


if __name__ == "__main__":
    main()
