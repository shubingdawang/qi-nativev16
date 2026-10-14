# -*- coding: utf-8 -*-
# 栖岛四季预览：地面换季节配色（跟 IslandPaint.palette 一样），景换季节版（跟 IslandArt.sprite(_:season:) 一样）
import colorsys, json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain
from terrain import hx
import preview_regions as pr

SEASON = {
    "summer": dict(grass=["7DB57A", "98CA86", "A9D492", "BEE0A4"], blade=["649D6A", "CDEAAA"],
                   flowers=["F5A9B8", "FFFFFF", "C9B6E8", "FBE3A6", "A9DCDC"]),
    "autumn": dict(grass=["AFAA74", "C6C087", "D3CC93", "E1D9A6"], blade=["9E8A5A", "EBD9A2"],
                   flowers=["F2B07E", "E98F78", "F4CE7A", "D9A56F", "FBE3C2"]),
    "winter": dict(grass=["DCE4EE", "EBF0F6", "F4F7FB", "FFFFFF"], blade=["B7C4D4", "FFFFFF"],
                   flowers=["FFFFFF", "E6ECF4", "D9E2EE", "F4F7FB", "C8D4E2"],
                   water=["9CC6D4", "BADCE6", "CFE7EE", "EEF8FB"]),
}

def seasonal(im, key, season):
    if season not in ("autumn", "winter"): return im
    a = np.array(im.convert("RGBA")).copy()
    h, w = a.shape[:2]
    if not key.startswith("pine"):
        for y in range(h):
            for x in range(w):
                r, g, b, al = a[y, x]
                if al <= 200: continue
                hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                if not (0.17 < hh < 0.5 and ss > 0.12): continue
                if season == "autumn":
                    nh = [0.07, 0.03, 0.11][(x * 7 + y * 13 + (x // 5) * 3) % 3]; ns = min(1, ss * 1.25 + 0.05)
                else:
                    nh, ns = hh, ss * 0.45
                rr, gg, bb = colorsys.hsv_to_rgb(nh, ns, vv)
                a[y, x, :3] = (int(rr * 255), int(gg * 255), int(bb * 255))
    if season == "winter" and key not in ("lily", "rowboat", "reeds"):
        for x in range(w):
            for y in range(h):
                if a[y, x, 3] > 200 and (y == 0 or a[y - 1, x, 3] == 0):
                    for k, v in ((1, 250), (2, 232)):
                        if y + k < h and a[y + k, x, 3] > 200:
                            if int(a[y + k, x, 0]) + int(a[y + k, x, 1]) + int(a[y + k, x, 2]) < 260: break
                            a[y + k, x, :3] = (v, v, min(255, v + 6))
    return Image.fromarray(a, "RGBA")

if __name__ == "__main__":
    base_C = {k: list(v) if isinstance(v, list) else v for k, v in terrain.C.items()}
    orig_sprite = pr.sprite
    outs = []
    for season in ("spring", "summer", "autumn", "winter"):
        terrain.C.update({k: (list(v) if isinstance(v, list) else v) for k, v in base_C.items()})
        if season in SEASON:
            p = SEASON[season]
            terrain.C["grass"] = [hx(c) for c in p["grass"]]
            terrain.C["blade"] = [hx(c) for c in p["blade"]]
            terrain.C["flowers"] = [hx(c) for c in p["flowers"]]
            if "water" in p: terrain.C["water"] = [hx(c) for c in p["water"]]
        pr.sprite = (lambda s: (lambda key: seasonal(orig_sprite(key), key, s)))(season)
        sys.argv = ["x"]
        data = json.load(open(os.path.join(HERE, "..", "..", "Qi", "Resources", "Island", "island_regions.json"), encoding="utf-8"))
        rows = [list(r) for r in open(os.path.join(HERE, "island_map.txt")).read().splitlines()]
        for x, y in data["home"]["stone"]: rows[y][x] = "t"
        for e in data["home"]["exits"]:
            for x, y in e["cells"]: rows[y][x] = "b"
        dd = json.load(open(os.path.join(HERE, "island_decor.json")))
        from regions import NINJA
        base = [(NINJA[k], x, y) for k, x, y in dd["decor"]] + [("lamp", 11, 15), ("lamp", 14, 23), ("mailbox", 10, 10),
                ("bench", 18, 16), ("lily", 18, 13), ("lily", 20, 12)]
        path = os.path.join(HERE, "season_" + season + ".png")
        pr.render(["".join(r) for r in rows], base + [tuple(t) for t in data["home"]["extra"]], path)
        outs.append(Image.open(path))
    ims = [i.resize((i.width // 2, i.height // 2)) for i in outs]
    W = sum(i.width for i in ims) + 50; H = max(i.height for i in ims) + 20
    sheet = Image.new("RGB", (W, H), (154, 154, 154)); x = 10
    for i in ims: sheet.paste(i, (x, 10), i); x += i.width + 10
    sheet.save(os.path.join(HERE, "seasons_all.png"))
    print("ok")
