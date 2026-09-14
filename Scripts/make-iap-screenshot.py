#!/usr/bin/env python3
"""Render App Store Connect IAP review screenshot: 1242x2208 RGB, no alpha. No price."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1242, 2208
OUT = Path(__file__).resolve().parents[1] / "AppStore" / "IAP-Screenshot.png"

BG = (245, 247, 250)
CARD = (255, 255, 255)
WHITE = (255, 255, 255)
INK = (31, 41, 56)
SECONDARY = (102, 115, 133)
ACCENT = (31, 115, 122)
HERO_TOP = (22, 82, 88)
HERO_BOT = (31, 115, 122)

SF = "/System/Library/Fonts/SFNS.ttf"
SFR = "/System/Library/Fonts/SFNSRounded.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fill_gradient(img: Image.Image, box, c0, c1) -> None:
    x0, y0, x1, y1 = box
    crop = img.crop((x0, y0, x1, y1))
    px = crop.load()
    h = y1 - y0
    w = x1 - x0
    for y in range(h):
        color = lerp(c0, c1, y / max(h - 1, 1))
        for x in range(w):
            px[x, y] = color
    img.paste(crop, (x0, y0))


def main() -> None:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    f_close = font(SF, 36)
    f_kicker = font(SFR, 28)
    f_hero = font(SFR, 58)
    f_sub = font(SF, 32)
    f_head = font(SFR, 38)
    f_body = font(SF, 30)
    f_caption = font(SF, 24)
    f_btn = font(SFR, 40)

    draw.text((52, 36), "Close", font=f_close, fill=ACCENT)

    fill_gradient(img, (0, 96, W, 560), HERO_TOP, HERO_BOT)
    draw = ImageDraw.Draw(img)
    draw.text((W / 2, 160), "LIFECUE PRO", font=f_kicker, fill=WHITE, anchor="mt")
    draw.multiline_text(
        (W / 2, 220),
        "Capture. Review.\nLifeCue remembers.",
        font=f_hero,
        fill=WHITE,
        anchor="ma",
        align="center",
        spacing=8,
    )
    draw.text(
        (W / 2, 460),
        "One-time purchase. No subscription.",
        font=f_sub,
        fill=(230, 242, 242),
        anchor="mt",
    )

    def card(y0, y1):
        draw.rounded_rectangle((48, y0, W - 48, y1), radius=36, fill=CARD)

    card(596, 1188)
    draw.text((88, 628), "Free", font=f_head, fill=SECONDARY)
    free = [
        "Manual reminders and notes",
        "One-time notifications",
        "Snooze, complete, and edit",
        "Home, Calendar, People, Contexts",
    ]
    y = 700
    for line in free:
        draw.ellipse((88, y + 6, 122, y + 40), outline=ACCENT, width=3)
        draw.text((148, y + 2), line, font=f_body, fill=INK)
        y += 70

    card(1224, 2040)
    draw.text((88, 1256), "LifeCue Pro Lifetime", font=f_head, fill=INK)
    pro = [
        "Upload Image and Take Photo",
        "On-device image extraction",
        "Repeating and yearly reminders",
        "Forward and Backup",
    ]
    y = 1330
    for line in pro:
        draw.ellipse((88, y + 8, 124, y + 44), fill=ACCENT)
        draw.line([(98, y + 28), (107, y + 38), (118, y + 16)], fill=WHITE, width=4)
        draw.text((148, y + 4), line, font=f_body, fill=INK)
        y += 72

    draw.rounded_rectangle((88, 1648, W - 88, 1788), radius=28, fill=ACCENT)
    draw.text((W / 2, 1718), "Unlock Lifetime", font=f_btn, fill=WHITE, anchor="mm")
    draw.rounded_rectangle((88, 1820, W - 88, 1936), radius=28, fill=(232, 238, 238))
    draw.text((W / 2, 1878), "Restore Purchases", font=f_btn, fill=ACCENT, anchor="mm")
    draw.text(
        (W / 2, 1980),
        "Charged to your Apple ID. Restore anytime.",
        font=f_caption,
        fill=SECONDARY,
        anchor="mt",
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, format="PNG", optimize=True)
    check = Image.open(OUT)
    assert check.mode == "RGB" and check.size == (W, H)
    print(f"Wrote {OUT} {check.size} {check.mode}")


if __name__ == "__main__":
    main()
