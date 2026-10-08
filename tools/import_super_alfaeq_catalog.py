#!/usr/bin/env python3
"""Import the Super Al-Faiq catalog (alfaig-yemen-assets) into Supabase.

Reads products_source.csv from the GitHub assets repo and inserts only the
products that are not already in the live catalog, matching by barcode first
then by normalised name so nothing is duplicated. Prices are SAR.

Requires env vars:
  GITHUB_TOKEN            read access to safwt771754091s-crypto/alfaig-yemen-assets
  SUPABASE_ACCESS_TOKEN   Supabase management API token
  SUPABASE_PROJECT_REF    project ref (e.g. xxxx.supabase.co -> xxxx)

Usage: python3 tools/import_super_alfaeq_catalog.py [--dry-run]
"""
import csv
import hashlib
import io
import json
import os
import re
import sys
import urllib.request

ASSETS_REPO = 'safwt771754091s-crypto/alfaig-yemen-assets'
SOURCE_FILE = 'products_source.csv'
STORE_ID = 'store-super-alfaeq'
SECTION_ID = 'markets'
CURRENCY = 'SAR'
DEFAULT_STOCK = 100


def management_query(sql):
    ref = os.environ['SUPABASE_PROJECT_REF']
    token = os.environ['SUPABASE_ACCESS_TOKEN']
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({'query': sql}).encode(),
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    return json.loads(urllib.request.urlopen(req, timeout=180).read().decode())


def fetch_source():
    token = os.environ['GITHUB_TOKEN']
    req = urllib.request.Request(
        f"https://api.github.com/repos/{ASSETS_REPO}/contents/{SOURCE_FILE}",
        headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github.raw', 'User-Agent': 'alfaeq-import'},
    )
    text = urllib.request.urlopen(req, timeout=120).read().decode('utf-8-sig')
    return list(csv.DictReader(io.StringIO(text)))


def normalize(value):
    value = (value or '').strip()
    value = re.sub(r'[\u064B-\u0652\u0640]', '', value)
    value = value.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا').replace('ى', 'ي').replace('ة', 'ه')
    return re.sub(r'\s+', ' ', value).lower()


def esc(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    dry_run = '--dry-run' in sys.argv
    live = management_query("select name, metadata->>'barcode' as barcode from products")
    live_barcodes = {(p['barcode'] or '').strip() for p in live if (p['barcode'] or '').strip()}
    live_names = {normalize(p['name']) for p in live}

    rows = fetch_source()
    seen, to_insert, skipped = set(), [], {'existing': 0, 'dup': 0, 'badprice': 0, 'noname': 0}
    for row in rows:
        name = (row.get('الاسم') or '').strip()
        barcode = (row.get('باركود') or '').strip()
        if not name:
            skipped['noname'] += 1
            continue
        if (barcode and barcode in live_barcodes) or normalize(name) in live_names:
            skipped['existing'] += 1
            continue
        key = barcode or normalize(name)
        if key in seen:
            skipped['dup'] += 1
            continue
        seen.add(key)
        try:
            price = round(float(row.get('سعر البيع') or 0), 2)
        except ValueError:
            price = 0
        if price <= 0 or price > 100000:
            skipped['badprice'] += 1
            continue
        to_insert.append({
            'id': 'super-' + hashlib.md5(f'{name}|{barcode}'.encode()).hexdigest()[:12],
            'store_id': STORE_ID,
            'section_id': SECTION_ID,
            'name': name,
            'price': price,
            'currency': CURRENCY,
            'stock': DEFAULT_STOCK,
            'unit_label': (row.get('وحدة القياس') or 'حبة').strip(),
            'metadata': {
                'barcode': barcode,
                'source': f'{ASSETS_REPO}/{SOURCE_FILE}',
                'source_category': (row.get('فئة المنتج') or '').strip(),
                'source_unit': (row.get('وحدة القياس') or '').strip(),
                'internal_ref': (row.get('مرجع داخلي') or '').strip(),
                'cost': (row.get('التكلفة') or '').strip(),
            },
        })

    print(f'to insert: {len(to_insert)}  skipped: {skipped}')
    if dry_run or not to_insert:
        return

    for start in range(0, len(to_insert), 200):
        chunk = to_insert[start:start + 200]
        values = ','.join(
            '(' + ','.join([
                esc(p['id']), esc(p['store_id']), esc(p['section_id']), 'null', esc(p['name']), "''",
                str(p['price']), esc(p['currency']), str(p['stock']), str(p['stock']),
                "'piece'", esc(p['unit_label']), "'piece'", '1', '1', '1', '0', '0', "''", "'active'",
                esc(json.dumps(p['metadata'], ensure_ascii=False)) + '::jsonb',
            ]) + ')'
            for p in chunk
        )
        management_query(
            'insert into public.products '
            '(id,store_id,section_id,owner_id,name,description,price,currency,stock,stock_base,'
            'sale_unit,unit_label,base_unit,unit_scale,step_base,min_order_base,sold_quantity,'
            f'sold_quantity_base,image_url,status,metadata) values {values} on conflict (id) do nothing;'
        )
        print(f'  inserted {min(start + 200, len(to_insert))}/{len(to_insert)}')


if __name__ == '__main__':
    main()
