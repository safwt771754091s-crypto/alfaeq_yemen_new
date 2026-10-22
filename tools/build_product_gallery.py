#!/usr/bin/env python3
"""Build a public, self-contained product gallery for the Alfaeq Yemen catalog.

Reads every product from Supabase (REST, publishable/anon key) and writes:

  catalog/index.html          Arabic RTL gallery (search + filters, live images)
  catalog/products.json       full catalog snapshot (id, name, price, image...)
  catalog/missing-images.json products that still need a picture

The gallery is committed to the repository so it is visible to everyone, and it
is copied into the Pages build by .github/workflows/flutter_build.yml.

No third-party packages: only the standard library.

Env / flags
-----------
  SUPABASE_URL / SUPABASE_REST_URL   project URL (defaults to production)
  SUPABASE_PUBLISHABLE_KEY           read key (falls back to the app default)
  --out DIR                          output directory (default: catalog)
  --limit N                          max products (0 = all)
"""

import argparse
import html
import json
import os
import urllib.error
import urllib.parse
import urllib.request

PROJECT_URL = (
    os.environ.get("SUPABASE_URL")
    or os.environ.get("SUPABASE_REST_URL")
    or "https://esvljorjykzgrpnrxnma.supabase.co"
).rstrip("/")
DEFAULT_KEY = "sb_publishable_xJfLBgrqWM8yEa3FM9qfig_FwnfTKue"
READ_KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY") or DEFAULT_KEY

PAGE = 1000
COLUMNS = "id,name,price,currency,image_url,store_id,section_id,status"


def fetch_products(limit):
    rows = []
    start = 0
    while True:
        end = start + PAGE - 1
        query = urllib.parse.urlencode(
            {"select": COLUMNS, "order": "name.asc", "limit": PAGE, "offset": start}
        )
        req = urllib.request.Request(
            f"{PROJECT_URL}/rest/v1/products?{query}",
            headers={
                "apikey": READ_KEY,
                "Authorization": f"Bearer {READ_KEY}",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=120) as response:
            batch = json.loads(response.read().decode("utf-8"))
        if not batch:
            break
        rows.extend(batch)
        if limit and len(rows) >= limit:
            return rows[:limit]
        if len(batch) < PAGE:
            break
        start += PAGE
    return rows


def normalise(rows):
    out = []
    for row in rows:
        image = (row.get("image_url") or "").strip()
        out.append(
            {
                "id": str(row.get("id") or ""),
                "name": (row.get("name") or "").strip(),
                "price": row.get("price"),
                "currency": row.get("currency") or "SAR",
                "image": image,
                "store_id": row.get("store_id") or "",
                "section_id": row.get("section_id") or "",
                "status": row.get("status") or "",
            }
        )
    return out


PLACEHOLDER = (
    "data:image/svg+xml;utf8,"
    "<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240'>"
    "<rect width='100%25' height='100%25' fill='%23eef2f7'/>"
    "<text x='50%25' y='50%25' font-size='16' fill='%2394a3b8' "
    "text-anchor='middle' dy='.35em'>لا صورة</text></svg>"
)


def render_html(products, missing):
    total = len(products)
    have = total - len(missing)
    cards = []
    for item in products:
        name = html.escape(item["name"] or item["id"])
        pid = html.escape(item["id"])
        price = item["price"]
        price_txt = f"{price:,.2f} {html.escape(item['currency'])}" if isinstance(price, (int, float)) else ""
        if item["image"]:
            img = html.escape(item["image"])
            media = (
                f'<img loading="lazy" src="{img}" alt="{name}" '
                f"onerror=\"this.onerror=null;this.src='{PLACEHOLDER}'\"/>"
            )
            badge = ""
            state = "has"
        else:
            media = f'<img loading="lazy" src="{PLACEHOLDER}" alt="{name}"/>'
            badge = '<span class="badge">ينقص صورة</span>'
            state = "missing"
        cards.append(
            f'<article class="card" data-state="{state}" '
            f'data-name="{name.lower()}" data-id="{pid.lower()}">'
            f'<div class="thumb">{media}{badge}</div>'
            f'<div class="meta"><h3>{name}</h3>'
            f'<p class="pid">{pid}</p><p class="price">{price_txt}</p></div></article>'
        )
    cards_html = "\n".join(cards)
    return f"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>كتالوج الفائق يمن — {total} منتج</title>
<style>
  :root {{ --brand:#0f766e; --ink:#0f172a; --muted:#64748b; --line:#e2e8f0; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font-family:"Segoe UI",Tahoma,system-ui,sans-serif; color:var(--ink); background:#f8fafc; }}
  header {{ background:var(--brand); color:#fff; padding:22px 18px; }}
  header h1 {{ margin:0 0 6px; font-size:22px; }}
  .stats {{ display:flex; gap:18px; flex-wrap:wrap; font-size:14px; opacity:.95; }}
  .stats b {{ font-size:18px; }}
  .toolbar {{ position:sticky; top:0; z-index:5; background:#fff; border-bottom:1px solid var(--line);
             padding:12px 18px; display:flex; gap:10px; flex-wrap:wrap; align-items:center; }}
  .toolbar input {{ flex:1; min-width:200px; padding:10px 14px; border:1px solid var(--line); border-radius:10px; font-size:15px; }}
  .filters button {{ padding:8px 14px; border:1px solid var(--line); background:#fff; border-radius:999px;
                     cursor:pointer; font-size:14px; }}
  .filters button.active {{ background:var(--brand); color:#fff; border-color:var(--brand); }}
  main {{ padding:16px; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:14px; }}
  .card {{ background:#fff; border:1px solid var(--line); border-radius:14px; overflow:hidden;
           display:flex; flex-direction:column; }}
  .thumb {{ position:relative; aspect-ratio:1/1; background:#eef2f7; }}
  .thumb img {{ width:100%; height:100%; object-fit:cover; display:block; }}
  .badge {{ position:absolute; inset-inline-start:8px; top:8px; background:#fee2e2; color:#b91c1c;
            font-size:12px; padding:3px 8px; border-radius:999px; }}
  .meta {{ padding:10px 12px; }}
  .meta h3 {{ margin:0 0 6px; font-size:14px; line-height:1.5; min-height:42px; }}
  .pid {{ margin:0 0 4px; font-size:11px; color:var(--muted); word-break:break-all; }}
  .price {{ margin:0; font-weight:700; color:var(--brand); }}
  .empty {{ padding:60px; text-align:center; color:var(--muted); display:none; }}
</style>
</head>
<body>
<header>
  <h1>كتالوج الفائق يمن</h1>
  <div class="stats">
    <span>الإجمالي <b>{total}</b></span>
    <span>بصور <b>{have}</b></span>
    <span>ينقصها صورة <b>{len(missing)}</b></span>
  </div>
</header>
<div class="toolbar">
  <input id="q" type="search" placeholder="ابحث بالاسم أو المعرّف…"/>
  <div class="filters" id="filters">
    <button data-f="all" class="active">الكل</button>
    <button data-f="missing">ينقصها صورة</button>
    <button data-f="has">بصور</button>
  </div>
</div>
<main>
  <div class="grid" id="grid">
{cards_html}
  </div>
  <div class="empty" id="empty">لا نتائج مطابقة.</div>
</main>
<script>
  const grid = document.getElementById('grid');
  const cards = Array.from(grid.querySelectorAll('.card'));
  const empty = document.getElementById('empty');
  const q = document.getElementById('q');
  let filter = 'all';
  function apply() {{
    const term = q.value.trim().toLowerCase();
    let shown = 0;
    for (const c of cards) {{
      const okFilter = filter === 'all' || c.dataset.state === filter;
      const okTerm = !term || c.dataset.name.includes(term) || c.dataset.id.includes(term);
      const ok = okFilter && okTerm;
      c.style.display = ok ? '' : 'none';
      if (ok) shown++;
    }}
    empty.style.display = shown ? 'none' : 'block';
  }}
  q.addEventListener('input', apply);
  document.getElementById('filters').addEventListener('click', (e) => {{
    const b = e.target.closest('button');
    if (!b) return;
    filter = b.dataset.f;
    document.querySelectorAll('#filters button').forEach((x) => x.classList.toggle('active', x === b));
    apply();
  }});
</script>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="catalog")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    products = normalise(fetch_products(args.limit))
    missing = [p for p in products if not p["image"]]

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "products.json"), "w", encoding="utf-8") as handle:
        json.dump(products, handle, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(args.out, "missing-images.json"), "w", encoding="utf-8") as handle:
        json.dump(missing, handle, ensure_ascii=False, indent=1)
    with open(os.path.join(args.out, "index.html"), "w", encoding="utf-8") as handle:
        handle.write(render_html(products, missing))

    print(f"gallery: {len(products)} products, {len(missing)} missing an image -> {args.out}/")


if __name__ == "__main__":
    main()
