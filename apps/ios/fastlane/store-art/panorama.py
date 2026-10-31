#!/usr/bin/env python3
"""Panoramic App Store screenshots: slots 1-2, 3-4 and 5-6 are drawn as one wide
canvas each, with a tilted "bridge" device across the seam; slot 7 stands alone.
Every slot keeps its own headline and its own upright device, so each one also
reads on its own. Product page header and search images come from base.
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import base as gen2  # noqa: E402

RAW, OUT, HTML, COPY = gen2.RAW, gen2.OUT, gen2.HTML, gen2.COPY

# (left slot screen, bridge screen, right slot screen); the slot number follows the order.
PAIRS = [("01-live", "05-series", "02-movies"),
         ("03-movie-detail", "02-movies", "04-player"),
         ("06-series-detail", "01-live", "07-search")]
SINGLE = "05-series"  # slot 7
SLOT_NAMES = ["01", "02", "03", "04", "05", "06", "07"]

# Proportions taken from the approved iPhone sample (1320 x 2868 per slot).
GEOM = {
    "iphone": dict(main=0.68, bridge=0.65, radius=118, bezel=20, head=112, sub=46),
    "ipad": dict(main=0.70, bridge=0.62, radius=64, bezel=26, head=128, sub=54),
    "duo": dict(main=0.70, bridge=0.62, radius=80, bezel=24, head=128, sub=54),
}


def pair_page(device, lang, left, bridge, right, shift):
    d = gen2.DEVICES[device]
    g = GEOM[device]
    w, h = d["w"], d["h"]
    img = lambda n: os.path.join(RAW, device, f"{lang}-{n}.png")
    main_w, bridge_w = int(w * g["main"]), int(w * g["bridge"])
    top_main, top_bridge = int(h * 0.223), int(h * 0.314)
    rtl = lang == "ar"
    # In Arabic the store lists slots right to left, so the story runs the other way.
    lx, rx = (int(w * 0.083), w + int(w * 0.242)) if not rtl else (w + int(w * 0.242), int(w * 0.083))
    bx = w - bridge_w // 2 - int(w * 0.03)
    lrot, rrot, brot = (-4, 4, 8) if not rtl else (4, -4, -8)

    def phone(src, width, x, top, rot, z=1):
        return (f'<div class="phone" style="width:{width}px;left:{x}px;top:{top}px;transform:rotate({rot}deg);'
                f'z-index:{z};padding:{g["bezel"]}px;border-radius:{g["radius"]}px">'
                f'<img src="file://{src}" style="border-radius:{g["radius"] - g["bezel"]}px"></div>')

    lh, ls = COPY[lang][left]
    rh, rs = COPY[lang][right]
    copy_l, copy_r = (0, w) if not rtl else (w, 0)
    css = gen2.BASE_CSS % dict(w=w, h=h) + f"""
html {{ width: {w}px; }}
body {{ position: relative; width: {2 * w}px; transform: translateX(-{shift}px);
  background:
   radial-gradient(ellipse 45% 35% at 22% 0%, rgba(10,132,255,.42), transparent 70%),
   radial-gradient(ellipse 45% 35% at 80% 100%, rgba(94,92,230,.35), transparent 70%),
   radial-gradient(ellipse 30% 50% at 50% 55%, rgba(10,132,255,.20), transparent 70%), #07070b; }}
.copy {{ position: absolute; top: {d['top']}px; width: {w}px; text-align: center; padding: 0 6%; }}
h1 {{ font-size: {g['head']}px; font-weight: 800; line-height: 1.08; letter-spacing: -.02em; }}
p {{ margin-top: 30px; font-size: {g['sub']}px; font-weight: 500; color: rgba(235,235,245,.62); line-height: 1.25; }}
.phone {{ position: absolute; background: #141418;
  box-shadow: 0 0 0 2px rgba(255,255,255,.10), 0 60px 140px rgba(0,0,0,.7), 0 0 120px rgba(10,132,255,.18); }}
.phone img {{ display: block; width: 100%; }}
"""
    body = (f'<div class="copy" style="left:{copy_l}px"><h1 data-fit="2">{lh}</h1><p data-fit="2">{ls}</p></div>'
            f'<div class="copy" style="left:{copy_r}px"><h1 data-fit="2">{rh}</h1><p data-fit="2">{rs}</p></div>'
            + phone(img(left), main_w, lx, top_main, lrot)
            + phone(img(bridge), bridge_w, bx, top_bridge, brot, 2)
            + phone(img(right), main_w, rx, top_main, rrot))
    return gen2.page(w, h, css, body, lang)


def main():
    os.makedirs(HTML, exist_ok=True)
    only = sys.argv[1:]
    jobs, done_langs = [], {}
    for locale, lang in gen2.LOCALES.items():
        if (only and locale not in only) or lang in done_langs:
            continue
        done_langs[lang] = locale
        for device, d in gen2.DEVICES.items():
            out_dir = os.path.join(OUT, locale, device)
            for i, (left, bridge, right) in enumerate(PAIRS):
                for side in (0, 1):
                    slot = SLOT_NAMES[2 * i + side]
                    # Right to left, the store shows slot 1 on the right: it is the right half.
                    half = (1 - side) if lang == "ar" else side
                    jobs.append((f"pano-{locale}-{device}-{slot}",
                                 pair_page(device, lang, left, bridge, right, half * d["w"]),
                                 os.path.join(out_dir, f"{slot}.png"), d["w"], d["h"]))
            jobs.append((f"pano-{locale}-{device}-07", gen2.screenshot_page(device, lang, SINGLE),
                         os.path.join(out_dir, "07.png"), d["w"], d["h"]))
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(gen2.render, jobs))
    for locale, lang in gen2.LOCALES.items():
        src = done_langs.get(lang)
        if src and src != locale:
            shutil.copytree(os.path.join(OUT, src), os.path.join(OUT, locale), dirs_exist_ok=True)
    print(f"rendered {len(jobs)} images")


if __name__ == "__main__":
    main()
