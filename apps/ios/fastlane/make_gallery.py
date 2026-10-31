#!/usr/bin/env python3
"""Writes screenshots/screenshots.html: every App Store image on one page, by locale.

Run from apps/ios: python3 fastlane/make_gallery.py
It lists fastlane/screenshots/<locale>/*.png (uploaded by deliver) and
fastlane/store-assets/<locale>/... (iPhone Duo, product page header and search
images, uploaded by hand in App Store Connect).
"""
import html
import os
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "screenshots")
ASSETS = os.path.join(HERE, "store-assets")
OUT = os.path.join(SHOTS, "screenshots.html")


def pngs(folder):
    if not os.path.isdir(folder):
        return []
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(".png"))


def section(title, folder, rel_prefix, height):
    files = pngs(folder)
    if not files:
        return ""
    items = "".join(
        f'<figure><a href="{quote(rel_prefix + f)}"><img src="{quote(rel_prefix + f)}" style="height:{height}px"></a>'
        f"<figcaption>{html.escape(f)}</figcaption></figure>"
        for f in files
    )
    return f"<h3>{html.escape(title)}</h3><div class=row>{items}</div>"


def main():
    locales = sorted(d for d in os.listdir(SHOTS) if os.path.isdir(os.path.join(SHOTS, d)))
    asset_locales = sorted(d for d in os.listdir(ASSETS) if os.path.isdir(os.path.join(ASSETS, d))) if os.path.isdir(ASSETS) else []
    body = []
    for loc in sorted(set(locales) | set(asset_locales)):
        parts = [section("App Store screenshots (iPhone 6.9\" / iPad 13\")", os.path.join(SHOTS, loc), f"./{loc}/", 420)]
        a = os.path.join(ASSETS, loc)
        parts.append(section("iPhone Duo", os.path.join(a, "iphone-duo"), f"../store-assets/{loc}/iphone-duo/", 420))
        parts.append(section("Product page header & search", os.path.join(a, "product-page"), f"../store-assets/{loc}/product-page/", 300))
        if any(parts):
            body.append(f'<h2 id="{loc}">{html.escape(loc)}</h2>' + "".join(parts))
    nav = " · ".join(f'<a href="#{l}">{l}</a>' for l in sorted(set(locales) | set(asset_locales)))
    page = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>App Store images</title><style>
body {{ font-family: -apple-system, sans-serif; background: #111; color: #eee; margin: 24px; }}
a {{ color: #4da3ff; }} h2 {{ margin-top: 48px; border-bottom: 1px solid #333; padding-bottom: 8px; }}
.row {{ display: flex; gap: 16px; overflow-x: auto; padding-bottom: 12px; }}
figure {{ margin: 0; }} figcaption {{ font-size: 12px; color: #999; margin-top: 4px; }}
img {{ border-radius: 8px; display: block; }}
</style></head><body><h1>App Store images</h1><p>{nav}</p>{''.join(body)}</body></html>"""
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
