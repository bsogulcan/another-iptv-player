#!/usr/bin/env python3
"""Localized App Store marketing images from raw simulator screenshots.

captures/portrait/<device>/<lang>-<shot>.png  ->  out/<store locale>/<device>/<shot>.png
                                     out2/<store locale>/product-page/{header,search}.png
Headlines come from copy.json. Each image is an HTML page rendered by headless Chrome
at the exact size App Store Connect expects.
"""
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "captures", "portrait")
HTML = os.path.join(ROOT, "html")
OUT = os.path.join(ROOT, "out")
LOGO = os.path.normpath(os.path.join(ROOT, "..", "..", "..", "..", "docs", "public", "logo.png"))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
COPY = json.load(open(os.path.join(ROOT, "copy.json"), encoding="utf-8"))

# App Store locale -> language the screenshots were captured in.
LOCALES = {
    "en-US": "en", "en-GB": "en", "tr": "tr", "de-DE": "de", "es-ES": "es", "fr-FR": "fr",
    "pt-BR": "pt-BR", "ru": "ru", "ar-SA": "ar", "hi": "hi", "zh-Hans": "zh-Hans",
}
SHOTS = ["01-live", "02-movies", "03-movie-detail", "04-player", "05-series", "06-series-detail", "07-search"]
DEVICES = {
    "iphone": dict(w=1320, h=2868, shot=1040, head=112, sub=46, top=190, gap=90, radius=118, bezel=20),
    "ipad": dict(w=2064, h=2752, shot=1660, head=128, sub=54, top=170, gap=90, radius=64, bezel=26),
    "duo": dict(w=2007, h=2853, shot=1620, head=128, sub=54, top=180, gap=90, radius=80, bezel=24),
}

BASE_CSS = """
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
body {
  font-family: -apple-system, "SF Pro Display", "Helvetica Neue", "PingFang SC", "Kohinoor Devanagari",
               "Geeza Pro", sans-serif;
  color: #fff;
  background:
    radial-gradient(ellipse 70%% 45%% at 50%% 0%%, rgba(10,132,255,0.38), transparent 70%%),
    radial-gradient(ellipse 60%% 40%% at 50%% 100%%, rgba(94,92,230,0.22), transparent 70%%),
    #07070b;
  -webkit-font-smoothing: antialiased;
}
em { font-style: normal; background: linear-gradient(90deg, #4da3ff, #9d8cff);
     -webkit-background-clip: text; background-clip: text; color: transparent; }
"""

# Shrinks the headline until it fits in two lines (long German, French or Hindi copy).
FIT_JS = """
<script>
for (const el of document.querySelectorAll('[data-fit]')) {
  const max = parseFloat(el.dataset.fit);
  let size = parseFloat(getComputedStyle(el).fontSize);
  const lh = () => parseFloat(getComputedStyle(el).lineHeight);
  while (Math.round(el.scrollHeight / lh()) > max && size > 40) { size -= 4; el.style.fontSize = size + 'px'; }
}
</script>
"""


def page(w, h, css, body, lang):
    # Right-to-left only inside the copy blocks: on the root it would flip the
    # coordinate space the panorama is shifted in, and the slot would render empty.
    if lang == "ar":
        css += " .copy, .copy h1, .copy p { direction: rtl; }"
    return (f'<!DOCTYPE html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head>'
            f"<body>{body}{FIT_JS}</body></html>")


def screenshot_page(device, lang, shot):
    d = DEVICES[device]
    img = os.path.join(RAW, device, f"{lang}-{shot}.png")
    head, sub = COPY[lang][shot]
    css = BASE_CSS % d + """
body { display: flex; flex-direction: column; align-items: center; }
.copy { padding: %(top)dpx 6%% 0; text-align: center; width: 100%%; }
h1 { font-size: %(head)dpx; font-weight: 800; line-height: 1.08; letter-spacing: -0.02em; }
p { margin-top: 30px; font-size: %(sub)dpx; font-weight: 500; color: rgba(235,235,245,0.62); line-height: 1.25; }
.device { margin-top: %(gap)dpx; width: %(shot)dpx; flex-shrink: 0;
  padding: %(bezel)dpx; border-radius: %(radius)dpx; background: #141418;
  box-shadow: 0 0 0 2px rgba(255,255,255,0.10), 0 60px 140px rgba(0,0,0,0.65), 0 0 120px rgba(10,132,255,0.18); }
.device img { display: block; width: 100%%; border-radius: calc(%(radius)dpx - %(bezel)dpx); }
""" % d
    body = (f'<div class="copy"><h1 data-fit="2">{head}</h1><p data-fit="2">{sub}</p></div>'
            f'<div class="device"><img src="file://{img}"></div>')
    return page(d["w"], d["h"], css, body, lang)


PHONE_CSS = """
.phone { position: absolute; background: #141418;
  box-shadow: 0 0 0 2px rgba(255,255,255,0.10), 0 50px 120px rgba(0,0,0,0.7); }
.phone img { display: block; width: 100%; }
"""


def phone(img, width, extra, radius=104, bezel=18):
    return (f'<div class="phone" style="width:{width}px;padding:{bezel}px;border-radius:{radius}px;{extra}">'
            f'<img src="file://{img}" style="border-radius:{radius - bezel}px"></div>')


def header_page(lang):
    head, sub = COPY[lang]["header"]
    side = "right" if lang == "ar" else "left"
    other = "left" if lang == "ar" else "right"
    css = BASE_CSS % dict(w=3840, h=1646) + PHONE_CSS + f"""
body {{ background:
  radial-gradient(ellipse 55% 90% at {'22%' if lang == 'ar' else '78%'} 40%, rgba(10,132,255,0.30), transparent 70%),
  radial-gradient(ellipse 40% 70% at {'90%' if lang == 'ar' else '10%'} 100%, rgba(94,92,230,0.18), transparent 70%), #07070b; }}
.copy {{ position: absolute; {side}: 300px; top: 50%; transform: translateY(-50%); width: 1750px; }}
.brand {{ display: flex; align-items: center; gap: 44px; margin-bottom: 70px; }}
.brand img {{ width: 190px; height: 190px; border-radius: 44px; }}
.brand span {{ font-size: 64px; font-weight: 700; color: rgba(235,235,245,0.85); }}
h1 {{ font-size: 150px; font-weight: 800; line-height: 1.04; letter-spacing: -0.025em; }}
p {{ margin-top: 48px; font-size: 58px; font-weight: 500; color: rgba(235,235,245,0.62); line-height: 1.3; }}
"""
    r = lambda n: os.path.join(RAW, "iphone", f"{lang}-{n}.png")
    phones = (
        phone(r("02-movies"), 600, f"{other}:1000px;top:250px;transform:rotate(-6deg);")
        + phone(r("03-movie-detail"), 600, f"{other}:220px;top:250px;transform:rotate(6deg);")
        + phone(r("01-live"), 640, f"{other}:580px;top:150px;z-index:2;")
    )
    body = (f'<div class="copy"><div class="brand"><img src="file://{LOGO}"><span>Another IPTV Player</span></div>'
            f'<h1 data-fit="2">{head}</h1><p>{sub}</p></div>{phones}')
    return page(3840, 1646, css, body, lang)


def search_page(lang):
    head, sub = COPY[lang]["search"]
    css = BASE_CSS % dict(w=3840, h=2560) + PHONE_CSS + """
.copy { position: absolute; top: 170px; left: 200px; right: 200px; text-align: center; }
h1 { font-size: 150px; font-weight: 800; line-height: 1.04; letter-spacing: -0.025em; }
p { margin-top: 40px; font-size: 62px; font-weight: 500; color: rgba(235,235,245,0.62); }
"""
    r = lambda n: os.path.join(RAW, "iphone", f"{lang}-{n}.png")
    w, top, mid = 900, 720, 3840 // 2 - 450
    phones = (
        phone(r("01-live"), w, f"left:{mid - 1080}px;top:{top + 90}px;")
        + phone(r("04-player"), w, f"left:{mid}px;top:{top}px;z-index:2;")
        + phone(r("02-movies"), w, f"left:{mid + 1080}px;top:{top + 90}px;")
    )
    body = f'<div class="copy"><h1 data-fit="1">{head}</h1><p>{sub}</p></div>{phones}'
    return page(3840, 2560, css, body, lang)


def render(job):
    key, html, png, w, h = job
    hp = os.path.join(HTML, key + ".html")
    with open(hp, "w", encoding="utf-8") as f:
        f.write(html)
    os.makedirs(os.path.dirname(png), exist_ok=True)
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
        "--force-device-scale-factor=1", f"--window-size={w},{h}", "--virtual-time-budget=3000",
        f"--screenshot={png}", "file://" + hp,
    ], check=True, capture_output=True)
    return png


def main():
    os.makedirs(HTML, exist_ok=True)
    only = sys.argv[1:]
    jobs = []
    rendered_langs = {}
    for locale, lang in LOCALES.items():
        if only and locale not in only:
            continue
        if lang in rendered_langs:  # en-GB reuses en-US
            continue
        rendered_langs[lang] = locale
        for device, d in DEVICES.items():
            for shot in SHOTS:
                if os.path.exists(os.path.join(RAW, device, f"{lang}-{shot}.png")):
                    jobs.append((f"{locale}-{device}-{shot}", screenshot_page(device, lang, shot),
                                 os.path.join(OUT, locale, device, f"{shot}.png"), d["w"], d["h"]))
        jobs.append((f"{locale}-header", header_page(lang),
                     os.path.join(OUT, locale, "product-page", "header-21x9-3840x1646.png"), 3840, 1646))
        jobs.append((f"{locale}-search", search_page(lang),
                     os.path.join(OUT, locale, "product-page", "search-3x2-3840x2560.png"), 3840, 2560))
    with ThreadPoolExecutor(max_workers=6) as pool:
        for png in pool.map(render, jobs):
            pass
    for locale, lang in LOCALES.items():
        src = rendered_langs.get(lang)
        if src and src != locale:
            shutil.copytree(os.path.join(OUT, src), os.path.join(OUT, locale), dirs_exist_ok=True)
    print(f"rendered {len(jobs)} images")


if __name__ == "__main__":
    main()
