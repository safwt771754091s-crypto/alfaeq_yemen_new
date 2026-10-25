#!/usr/bin/env python3
"""Generate Google Play listing assets for الفائق يمن.

Produces:
  store/play/icons/icon-512.png          (512x512 app icon)
  store/play/feature/feature-1024x500.png (feature graphic)
  store/play/phone/0*.png                (1080x1920 phone screenshots)

The screenshots are branded placeholder frames; replace them with real
screenshots captured from the running app before publishing if desired.
"""
from __future__ import annotations

import pathlib

import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFont

NAVY = (10, 37, 64)
BLUE = (13, 110, 253)
GOLD = (255, 193, 7)
WHITE = (255, 255, 255)
FONT_PATH = "/tmp/fonts/Cairo-Bold.ttf"
OUT = pathlib.Path("store/play")


def ar(text: str) -> str:
    return get_display(arabic_reshaper.reshape(text))


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size)


def draw_cart(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float,
              stroke=BLUE, gold=GOLD) -> None:
    w = int(22 * s)
    d.line([(cx - 3.2 * s, cy - 1.4 * s), (cx - 2.1 * s, cy - 1.4 * s),
            (cx - 1.4 * s, cy + 2.1 * s), (cx + 2.9 * s, cy + 2.1 * s),
            (cx + 3.9 * s, cy - 0.7 * s), (cx - 0.2 * s, cy - 0.7 * s)],
           fill=stroke, width=w, joint="curve")
    d.line([(cx - 1.4 * s, cy + 3.4 * s), (cx + 2.9 * s, cy + 3.4 * s)],
           fill=stroke, width=w)
    for dx in (-0.9 * s, 2.4 * s):
        d.ellipse([cx + dx - 0.5 * s, cy + 3.0 * s - 0.5 * s,
                   cx + dx + 0.5 * s, cy + 3.0 * s + 0.5 * s], fill=BLUE)
    d.polygon([(cx - 1.7 * s, cy - 1.9 * s), (cx - 0.4 * s, cy - 2.6 * s),
               (cx + 1.9 * s, cy - 2.4 * s), (cx + 1.1 * s, cy - 1.4 * s)], fill=gold)
    d.line([(cx - 0.4 * s, cy - 2.6 * s), (cx - 1.0 * s, cy - 1.7 * s)],
           fill=(247, 217, 107), width=max(1, int(0.06 * s)))
    d.line([(cx + 1.9 * s, cy - 2.4 * s), (cx + 1.1 * s, cy - 1.4 * s)],
           fill=(247, 217, 107), width=max(1, int(0.06 * s)))


def gradient(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=(
            int(BLUE[0] * (1 - t) + NAVY[0] * t),
            int(BLUE[1] * (1 - t) + NAVY[1] * t),
            int(BLUE[2] * (1 - t) + NAVY[2] * t), 255))
    return img


def rounded(img: Image.Image, r: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, img.size[0] - 1, img.size[1] - 1], radius=r, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def build_icon() -> None:
    (OUT / "icons").mkdir(parents=True, exist_ok=True)
    icon = rounded(gradient(512, 512), 96)
    draw_cart(ImageDraw.Draw(icon), 256, 232, 34, WHITE, GOLD)
    icon.save(OUT / "icons" / "icon-512.png")


def build_feature() -> None:
    (OUT / "feature").mkdir(parents=True, exist_ok=True)
    fg = gradient(1024, 500)
    d = ImageDraw.Draw(fg)
    draw_cart(d, 190, 250, 62, WHITE, GOLD)
    d.text((560, 150), ar("الفائق يمن"), font=font(96), fill=WHITE, anchor="mm")
    d.text((560, 250), ar("سوقك الشامل في اليمن"), font=font(44), fill=(220, 232, 255), anchor="mm")
    d.text((560, 330), ar("تسوّق · توصيل · محفظة · بث مباشر"), font=font(34), fill=(200, 220, 255), anchor="mm")
    fg.convert("RGB").save(OUT / "feature" / "feature-1024x500.png")


def build_screen(title: str, lines: list[str], name: str) -> None:
    im = Image.new("RGB", (1080, 1920), (245, 248, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 1080, 260], fill=NAVY)
    draw_cart(d, 150, 130, 30, WHITE, GOLD)
    d.text((980, 130), ar(title), font=font(58), fill=WHITE, anchor="rm")
    y = 430
    for ln in lines:
        d.rounded_rectangle([70, y, 1010, y + 230], radius=28, fill=WHITE,
                            outline=(222, 230, 240), width=3)
        d.text((990, y + 115), ar(ln), font=font(46), fill=NAVY, anchor="rm")
        y += 270
    d.text((540, 1830), ar("الفائق يمن"), font=font(40), fill=(150, 165, 185), anchor="mm")
    im.save(OUT / "phone" / name)


def main() -> None:
    (OUT / "phone").mkdir(parents=True, exist_ok=True)
    build_icon()
    build_feature()
    build_screen("الرئيسية", ["المتاجر القريبة منك", "فيديو الفائق", "اللحظات", "ذكاء الفائق"], "01-home.png")
    build_screen("المحفظة", ["رصيدي", "إيداع الرصيد", "تحويل الأموال", "رمز الدفع QR"], "02-wallet.png")
    build_screen("إيداع الرصيد", ["بنك الكريمي — ريال يمني", "بنك الكريمي — ريال سعودي", "بنك الكريمي — دولار", "رقم الإيصال + صورة السند"], "03-deposit.png")
    build_screen("التوصيل والطلبات", ["تتبّع طلبك", "عروض وتخفيضات", "برامج مصغّرة", "خدمات ودفع"], "04-orders.png")
    print("assets generated")


if __name__ == "__main__":
    main()
