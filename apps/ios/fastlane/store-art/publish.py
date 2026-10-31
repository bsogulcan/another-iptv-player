#!/usr/bin/env python3
"""Copies out/ into the folders fastlane and App Store Connect uploads read from.

out/<locale>/iphone/NN.png       -> ../screenshots/<locale>/iPhone 6.9-NN.png    (deliver)
out/<locale>/ipad/NN.png         -> ../screenshots/<locale>/iPad Pro 13-NN.png   (deliver)
out/<locale>/duo/NN.png          -> ../screenshots/<locale>/iPhone Duo-NN.png    (deliver, fastlane >= 2.241.1)
                                    ../store-assets/<locale>/iphone-duo/NN.png
out/<locale>/product-page/*.png  -> ../store-assets/<locale>/product-page/       (uploaded by hand)
Then rebuilds ../screenshots/screenshots.html.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
FASTLANE = os.path.dirname(ROOT)
PREFIX = {"iphone": "iPhone 6.9", "ipad": "iPad Pro 13", "duo": "iPhone Duo"}


def main():
    out = os.path.join(ROOT, "out")
    for locale in sorted(os.listdir(out)):
        src = os.path.join(out, locale)
        if not os.path.isdir(src):
            continue
        shots = os.path.join(FASTLANE, "screenshots", locale)
        os.makedirs(shots, exist_ok=True)
        for device, prefix in PREFIX.items():
            folder = os.path.join(src, device)
            for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
                shutil.copy2(os.path.join(folder, name), os.path.join(shots, f"{prefix}-{name}"))
                if device == "duo":
                    duo = os.path.join(FASTLANE, "store-assets", locale, "iphone-duo")
                    os.makedirs(duo, exist_ok=True)
                    shutil.copy2(os.path.join(folder, name), os.path.join(duo, name))
        page = os.path.join(src, "product-page")
        if os.path.isdir(page):
            shutil.copytree(page, os.path.join(FASTLANE, "store-assets", locale, "product-page"), dirs_exist_ok=True)
        print("published", locale)
    subprocess.run([sys.executable, "-I", os.path.join(FASTLANE, "make_gallery.py")], check=True)


if __name__ == "__main__":
    main()
