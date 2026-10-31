#!/usr/bin/env python3
"""Round 2: product page header and search images redrawn for how the App Store
crops them, plus landscape screenshot slots (iPhone 08, iPad 08-09).

Header: on iPhone the 21:9 image is cut to about 1.9:1 (≈365 px off each side) and
the back / share buttons sit in the top corners, so the copy stays inside
x 560-3280 and clear of the top 420 px at the edges. The app icon and name are
right below the header in the store, so they are not repeated.
Search: shown about 400 pt wide on iPhone, so one large landscape player and big type.
"""
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import base as gen2  # noqa: E402

ROOT = gen2.ROOT
RAW, RAW3, OUT = gen2.RAW, os.path.join(ROOT, "captures", "landscape"), gen2.OUT
COPY = gen2.COPY
LAND = {"iphone": dict(w=2868, h=1320, slots=["08-player-land"]),
        "ipad": dict(w=2752, h=2064, slots=["08-player-land", "09-live-land"]),
        "duo": dict(w=2853, h=2007, slots=["10-live-land", "11-detail-land", "12-player-land"])}
# Captured slot -> the headline it reuses.
COPY_KEY = {"10-live-land": "09-live-land", "11-detail-land": "03-movie-detail", "12-player-land": "08-player-land"}

DEVICE_CSS = """
.dev { position: absolute; background: #141418;
  box-shadow: 0 0 0 2px rgba(255,255,255,.10), 0 60px 140px rgba(0,0,0,.7), 0 0 140px rgba(10,132,255,.20); }
.dev img { display: block; width: 100%; }
"""


def dev(src, width, style, radius, bezel):
    return (f'<div class="dev" style="width:{width}px;padding:{bezel}px;border-radius:{radius}px;{style}">'
            f'<img src="file://{src}" style="border-radius:{radius - bezel}px"></div>')


def land(lang, device="iphone", slot="08-player-land"):
    return os.path.join(RAW3, device, f"{lang}-{slot}.png")


def header_page(lang):
    head, sub = COPY[lang]["header"]
    rtl = lang == "ar"
    css = gen2.BASE_CSS % dict(w=3840, h=1646) + DEVICE_CSS + f"""
body {{ background:
  radial-gradient(ellipse 50% 85% at {'30%' if rtl else '70%'} 55%, rgba(10,132,255,.32), transparent 70%),
  radial-gradient(ellipse 40% 70% at {'85%' if rtl else '15%'} 100%, rgba(94,92,230,.22), transparent 70%), #07070b; }}
.copy {{ position: absolute; {'right' if rtl else 'left'}: 600px; top: 56%; transform: translateY(-50%); width: 1300px; }}
h1 {{ font-size: 176px; font-weight: 800; line-height: 1.02; letter-spacing: -0.03em; }}
p {{ margin-top: 50px; font-size: 64px; font-weight: 600; color: rgba(235,235,245,.7); line-height: 1.22; }}
"""
    side = "left" if rtl else "right"
    devices = (
        dev(land(lang), 1300, f"{side}:620px;top:520px;transform:rotate({3 if rtl else -3}deg);", 92, 16)
        + dev(os.path.join(RAW, "iphone", f"{lang}-03-movie-detail.png"), 460,
              f"{side}:470px;top:360px;transform:rotate({-6 if rtl else 6}deg);z-index:2;", 82, 14)
    )
    body = f'<div class="copy"><h1 data-fit="2">{head}</h1><p data-fit="2">{sub.replace("<br>", " ")}</p></div>{devices}'
    return gen2.page(3840, 1646, css, body, lang)


def search_page(lang):
    head, sub = COPY[lang]["search"]
    css = gen2.BASE_CSS % dict(w=3840, h=2560) + DEVICE_CSS + """
.copy { position: absolute; top: 150px; left: 160px; right: 160px; text-align: center; }
h1 { font-size: 250px; font-weight: 800; line-height: 1.02; letter-spacing: -0.03em; }
p { margin-top: 40px; font-size: 104px; font-weight: 600; color: rgba(235,235,245,.7); }
"""
    r = lambda n: os.path.join(RAW, "iphone", f"{lang}-{n}.png")
    devices = (
        dev(r("01-live"), 760, "left:120px;top:1060px;transform:rotate(-7deg);", 100, 16)
        + dev(r("02-movies"), 760, "right:120px;top:1060px;transform:rotate(7deg);", 100, 16)
        + dev(land(lang), 2600, "left:620px;top:1000px;z-index:2;", 130, 22)
    )
    body = f'<div class="copy"><h1 data-fit="1">{head}</h1><p data-fit="1">{sub}</p></div>{devices}'
    return gen2.page(3840, 2560, css, body, lang)


def landscape_page(device, lang, slot):
    """A portrait canvas (the set is portrait, and the store turns a landscape image
    sideways) with the landscape device lying across it."""
    d = gen2.DEVICES[device]
    w, h = d["w"], d["h"]
    head, sub = COPY[lang][COPY_KEY.get(slot, slot)]
    src = land(lang, device, slot)
    css = gen2.BASE_CSS % dict(w=w, h=h) + DEVICE_CSS + """
.copy { position: absolute; top: %(top)dpx; left: 6%%; right: 6%%; text-align: center; }
h1 { font-size: %(head)dpx; font-weight: 800; line-height: 1.08; letter-spacing: -.02em; }
p { margin-top: 30px; font-size: %(sub)dpx; font-weight: 500; color: rgba(235,235,245,.62); line-height: 1.25; }
""" % d
    if device == "iphone":
        # The upright player behind, the same player turned sideways in front.
        devices = (
            dev(os.path.join(RAW, "iphone", f"{lang}-04-player.png"), 760,
                "left:300px;top:1380px;transform:rotate(5deg);", 110, 18)
            + dev(src, 1480, "left:-80px;top:700px;transform:rotate(-7deg);z-index:2;", 100, 18)
        )
    else:
        width = int(w * 0.9)
        raw_ratio = (2064 / 2752) if device == "ipad" else (2007 / 2853)
        dev_h = int(width * raw_ratio) + 52
        top = 560 + max(0, (h - 560 - dev_h) // 2)
        devices = dev(src, width, f"left:{(w - width) // 2}px;top:{top}px;",
                      64 if device == "ipad" else 84, 26 if device == "ipad" else 24)
    body = f'<div class="copy"><h1 data-fit="2">{head}</h1><p data-fit="2">{sub}</p></div>{devices}'
    return gen2.page(w, h, css, body, lang)


def main():
    os.makedirs(gen2.HTML, exist_ok=True)
    only = sys.argv[1:]
    jobs, done = [], {}
    for locale, lang in gen2.LOCALES.items():
        if (only and locale not in only) or lang in done:
            continue
        done[lang] = locale
        jobs.append((f"r2-{locale}-header", header_page(lang),
                     os.path.join(OUT, locale, "product-page", "header-21x9-3840x1646.png"), 3840, 1646))
        jobs.append((f"r2-{locale}-search", search_page(lang),
                     os.path.join(OUT, locale, "product-page", "search-3x2-3840x2560.png"), 3840, 2560))
        for device, d in LAND.items():
            for i, slot in enumerate(d["slots"]):
                if os.path.exists(land(lang, device, slot)):
                    pw, ph = gen2.DEVICES[device]["w"], gen2.DEVICES[device]["h"]
                    jobs.append((f"r2-{locale}-{device}-{slot}", landscape_page(device, lang, slot),
                                 os.path.join(OUT, locale, device, f"{8 + i:02d}.png"), pw, ph))
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(gen2.render, jobs))
    import shutil
    for locale, lang in gen2.LOCALES.items():
        src = done.get(lang)
        if src and src != locale:
            shutil.copytree(os.path.join(OUT, src), os.path.join(OUT, locale), dirs_exist_ok=True)
    print(f"rendered {len(jobs)} images")


if __name__ == "__main__":
    main()
