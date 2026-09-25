import hashlib
import json
import os
import re
from decimal import Decimal, InvalidOperation
from typing import Any
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from scrapling.fetchers import Fetcher, StealthyFetcher

app = FastAPI(title="Alfaeq Scrapling Worker", version="1.0.0")

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
WORKER_SECRET = os.getenv("SCRAPLING_WORKER_SECRET", "")
HEADLESS = os.getenv("SCRAPLING_HEADLESS", "false").lower() == "true"
TIMEOUT = int(os.getenv("SCRAPLING_REQUEST_TIMEOUT", "30"))


class ScrapeRequest(BaseModel):
    url: str
    store_id: str
    section_id: str | None = None
    publish: bool = False
    max_products: int = Field(default=50, ge=1, le=250)


def _required_config() -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY or not WORKER_SECRET:
        raise HTTPException(status_code=500, detail="server_configuration_missing")


def _supabase(path: str, method: str = "GET", payload: Any = None, query: str = "") -> Any:
    _required_config()
    url = f"{SUPABASE_URL}/rest/v1/{path}{query}"
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    if method == "POST":
        headers["Prefer"] = "return=representation,resolution=merge-duplicates"
    body = None if payload is None else json.dumps(payload).encode()
    request = Request(url, data=body, headers=headers, method=method)
    try:
        with urlopen(request, timeout=TIMEOUT) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"supabase_request_failed: {exc}") from exc


def _text(value: Any) -> str | None:
    if value is None:
        return None
    value = re.sub(r"\s+", " ", str(value)).strip()
    return value or None


def _price(value: Any) -> float | None:
    if value is None:
        return None
    raw = str(value).replace(",", "").replace("٬", "").strip()
    match = re.search(r"-?\d+(?:\.\d+)?", raw)
    if not match:
        return None
    try:
        return float(Decimal(match.group(0)))
    except (InvalidOperation, ValueError):
        return None


def _external_id(source_url: str, product_url: str | None, name: str) -> str:
    seed = f"{source_url}|{product_url or ''}|{name}".encode("utf-8")
    return "scrapling_" + hashlib.sha256(seed).hexdigest()[:40]


def _jsonld(page: Any) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for raw in page.css('script[type="application/ld+json"]::text').getall():
        try:
            data = json.loads(raw)
        except Exception:
            continue
        values = data if isinstance(data, list) else [data]
        for item in values:
            if not isinstance(item, dict):
                continue
            types = item.get("@type") or []
            types = types if isinstance(types, list) else [types]
            if "Product" in types:
                rows.append(item)
            graph = item.get("@graph")
            if isinstance(graph, list):
                rows.extend(
                    x for x in graph
                    if isinstance(x, dict) and "Product" in (
                        x.get("@type") if isinstance(x.get("@type"), list)
                        else [x.get("@type")]
                    )
                )
    return rows


def _extract_products(page: Any, source_url: str, limit: int) -> list[dict[str, Any]]:
    products: list[dict[str, Any]] = []

    for item in _jsonld(page)[:limit]:
        offers = item.get("offers") or {}
        if isinstance(offers, list):
            offers = offers[0] if offers else {}
        image = item.get("image")
        if isinstance(image, list):
            image = image[0] if image else None
        product_url = item.get("url")
        product_url = urljoin(source_url, str(product_url)) if product_url else None
        name = _text(item.get("name"))
        if not name:
            continue
        products.append({
            "external_id": _external_id(source_url, product_url, name),
            "name": name,
            "description": _text(item.get("description")),
            "price": _price(offers.get("price") if isinstance(offers, dict) else None) or 0,
            "currency": _text(offers.get("priceCurrency") if isinstance(offers, dict) else None) or "YER",
            "image_url": urljoin(source_url, str(image)) if image else None,
            "product_url": product_url,
            "source_url": source_url,
            "sku": _text(item.get("sku")),
            "availability": _text(offers.get("availability") if isinstance(offers, dict) else None),
            "category": _text(item.get("category")),
        })

    if products:
        return products[:limit]

    cards = page.css(".product, .product-card, [data-product], [itemtype*='Product']")
    for card in cards[:limit]:
        name = _text(card.css(
            "h1::text, h2::text, h3::text, .product-title::text, [itemprop='name']::text"
        ).get())
        if not name:
            continue
        href = card.css("a::attr(href)").get()
        image = card.css("img::attr(src), img::attr(data-src)").get()
        price = _price(card.css(
            ".price::text, [itemprop='price']::attr(content), [data-price]::attr(data-price)"
        ).get())
        products.append({
            "external_id": _external_id(
                source_url, urljoin(source_url, href) if href else None, name
            ),
            "name": name,
            "description": _text(card.css(
                ".description::text, [itemprop='description']::text"
            ).get()),
            "price": price or 0,
            "currency": _text(card.css(
                "[itemprop='priceCurrency']::attr(content)"
            ).get()) or "YER",
            "image_url": urljoin(source_url, image) if image else None,
            "product_url": urljoin(source_url, href) if href else None,
            "source_url": source_url,
            "sku": _text(card.css(
                "[itemprop='sku']::attr(content), [data-sku]::attr(data-sku)"
            ).get()),
            "availability": _text(card.css(
                "[itemprop='availability']::attr(href), [data-availability]::attr(data-availability)"
            ).get()),
            "category": None,
        })
    return products[:limit]


def _normalize(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    result = []
    for row in rows:
        key = row["external_id"]
        if key in seen:
            continue
        seen.add(key)
        row["name"] = row["name"][:300]
        row["description"] = row.get("description")[:5000] if row.get("description") else None
        row["currency"] = (row.get("currency") or "YER").upper()[:8]
        result.append(row)
    return result


def _store_exists(store_id: str) -> bool:
    rows = _supabase("stores", query=f"?select=id&limit=1&id=eq.{store_id}")
    return bool(rows)


def _section_match(section_id: str | None, category: str | None) -> str | None:
    if section_id:
        rows = _supabase("sections", query=f"?select=id&limit=1&id=eq.{section_id}")
        return section_id if rows else None
    if not category:
        return None
    rows = _supabase("sections", query="?select=id,title&status=eq.active&limit=100")
    wanted = category.casefold().strip()
    for row in rows or []:
        if str(row.get("title", "")).casefold().strip() == wanted:
            return row.get("id")
    return None


def _publish(store_id: str, section_id: str | None, products: list[dict[str, Any]]) -> dict[str, Any]:
    payloads = []
    for product in products:
        payloads.append({
            "id": product["external_id"],
            "store_id": store_id,
            "section_id": section_id or _section_match(None, product.get("category")),
            "name": product["name"],
            "description": product.get("description"),
            "price": product.get("price") or 0,
            "currency": product.get("currency") or "YER",
            "stock": 0,
            "stock_base": 0,
            "image_url": product.get("image_url"),
            "status": "active",
            "metadata": {
                "source": "scrapling",
                "source_url": product.get("source_url"),
                "product_url": product.get("product_url"),
                "external_id": product.get("external_id"),
                "sku": product.get("sku"),
                "availability": product.get("availability"),
                "category": product.get("category"),
            },
        })
    if not payloads:
        return {"published": 0}
    rows = _supabase("products", method="POST", payload=payloads)
    return {"published": len(rows or [])}


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "alfaeq-scrapling-worker"}


@app.post("/scrape")
def scrape(
    request: ScrapeRequest,
    x_alfaeq_scrapling_secret: str | None = Header(default=None),
) -> dict[str, Any]:
    _required_config()
    if x_alfaeq_scrapling_secret != WORKER_SECRET:
        raise HTTPException(status_code=401, detail="unauthorized")
    if urlparse(request.url).scheme not in {"http", "https"}:
        raise HTTPException(status_code=400, detail="invalid_url")
    if not _store_exists(request.store_id):
        raise HTTPException(status_code=400, detail="store_not_found")

    try:
        if HEADLESS:
            page = StealthyFetcher.fetch(
                request.url, headless=True, network_idle=True
            )
        else:
            page = Fetcher.get(request.url)
        products = _normalize(
            _extract_products(page, request.url, request.max_products)
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"scrape_failed: {exc}") from exc

    categories = sorted({p["category"] for p in products if p.get("category")})
    unmatched = [
        category for category in categories
        if _section_match(None, category) is None
    ]

    published = 0
    if request.publish:
        published = _publish(request.store_id, request.section_id, products)["published"]

    return {
        "ok": True,
        "dry_run": not request.publish,
        "source_url": request.url,
        "store_id": request.store_id,
        "count": len(products),
        "published": published,
        "unmatched_categories": unmatched,
        "products": products,
    }
