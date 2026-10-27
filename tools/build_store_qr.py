#!/usr/bin/env python3
"""Regenerate the store QR codes from the canonical URLs.

The Android QR always encodes `releases/latest/download/app-release.apk`, so it
keeps working as new releases are published (it never pins a version). Run from
the repo root:

    python3 tools/build_store_qr.py

If neither `segno` nor `qrcode` is installed the existing PNGs are left as-is,
so this is safe to call from CI.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO = "safwt771754091s-crypto/alfaeq_yemen_new"
WEB_URL = f"https://{REPO.split('/')[0]}.github.io/{REPO.split('/')[1]}/"
APK_URL = f"https://github.com/{REPO}/releases/latest/download/app-release.apk"

TARGETS = {
    "qr-app.png": WEB_URL,
    "qr-android.png": APK_URL,
}


def _make_png(url: str, out: Path) -> bool:
    try:
        import segno  # type: ignore
    except ImportError:
        segno = None
    if segno is not None:
        segno.make(url, error="m").save(str(out), scale=6, border=2, dark="#0B6E4F")
        return True

    try:
        import qrcode  # type: ignore
    except ImportError:
        return False
    img = qrcode.make(url)
    img.save(str(out))
    return True


def main() -> int:
    site = Path(__file__).resolve().parent.parent / "store" / "site"
    site.mkdir(parents=True, exist_ok=True)
    wrote = 0
    for name, url in TARGETS.items():
        out = site / name
        if _make_png(url, out):
            wrote += 1
            print(f"wrote {out.relative_to(site.parent.parent)} -> {url}")
        else:
            print(f"::warning::no QR library; keeping existing {name}")
    return 0 if wrote else 0


if __name__ == "__main__":
    sys.exit(main())
