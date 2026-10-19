# -*- coding: utf-8 -*-
"""clawd 的眼睛整体往上挪两行（图纸上一格 = 两行）。

只动脸上那几样：眼睛（k）、心心眼（E）、眼泪（f），只在两只眼睛那两列附近找，
道具（吉他、电脑、书）不碰；躺着、睡着那几张身子是横的，不动。
眼镜、墨镜那两张穿戴图跟着往上挪。

    python scripts/eyes_up.py --preview   只出对照图 _看一眼/眼睛往上.png
    python scripts/eyes_up.py --apply     改 Qi/Core/PixelSprite.swift 和眼镜图
"""
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Qi", "Core", "PixelSprite.swift")
SHIFT = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--shift=')), '2'))
SKIP = {"lying", "lying2", "sleep", "bubble"}
EYE_CHARS = set("kEf")
COLS = set(range(8, 14)) | set(range(20, 26))
ROWS = range(15, 23)
# 哭的那两张眼泪一直流到下面，整条一起挪
TEAR_ROWS = range(15, 27)


def blocks(text):
    start = text.index("enum ClawdSprites")
    end = text.index("\n}\n", start)
    for m in re.finditer(r"static let (\w+) = PixelSprite\(\[\n(.*?)\]", text[start:end], re.S):
        yield m.group(1), start + m.start(2), start + m.end(2), m.group(2)


def shift_rows(rows, name=""):
    g = [list(r) for r in rows]
    moved = []
    for r in (TEAR_ROWS if name.startswith("cry") else ROWS):
        if r >= len(g):
            continue
        for c in sorted(COLS):
            if c < len(g[r]) and g[r][c] in EYE_CHARS:
                moved.append((r, c, g[r][c]))
    for r, c, _ in moved:
        g[r][c] = "p" if (14 <= r <= 27 and 6 <= c <= 27) else "."
    for r, c, ch in moved:
        if 0 <= r - SHIFT < len(g):
            g[r - SHIFT][c] = ch
    return ["".join(x) for x in g]


PAL = {"p": (242, 113, 95), "k": (20, 20, 20), "E": (230, 80, 110), "f": (120, 190, 240)}


def draw(rows, px=6):
    im = Image.new("RGBA", (36 * px, len(rows) * px), (34, 33, 38, 255))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            c = PAL.get(ch, (150, 150, 160))
            for yy in range(px):
                for xx in range(px):
                    im.putpixel((x * px + xx, y * px + yy), c + (255,))
    return im


def main():
    text = open(SRC, encoding="utf-8", newline="").read()
    if "--preview" in sys.argv:
        names = ["idle", "blink", "happy", "cry2", "sweet", "walk1", "reading", "guitar"]
        found = {n: re.findall(r'"([^"]*)"', b) for n, _, _, b in blocks(text)}
        pairs = [(draw(found[n]), draw(shift_rows(found[n]))) for n in names if n in found]
        w, h = pairs[0][0].size
        sheet = Image.new("RGBA", (len(pairs) * (w + 10) + 10, 2 * (h + 10) + 10), (34, 33, 38, 255))
        for i, (a, b) in enumerate(pairs):
            sheet.paste(a, (10 + i * (w + 10), 10))
            sheet.paste(b, (10 + i * (w + 10), 20 + h))
        out = os.path.join(ROOT, "_看一眼", "眼睛往上.png")
        sheet.save(out)
        print(out)
        return
    if "--apply" in sys.argv:
        out = text
        for name, a, b, block in sorted(blocks(text), key=lambda t: -t[1]):
            if name in SKIP:
                continue
            rows = re.findall(r'"([^"]*)"', block)
            new = shift_rows(rows, name)
            if new == rows:
                continue
            # ⚠️ 按行号一行一行换，不能按字符串找：图纸里好几行长得一模一样，找第一个会换错行
            nl = chr(10)
            lines = block.split(nl)
            k = 0
            for li, line in enumerate(lines):
                m = re.search(r'"([^"]*)"', line)
                if m and k < len(new):
                    lines[li] = line[:m.start(1)] + new[k] + line[m.end(1):]
                    k += 1
            out = out[:a] + nl.join(lines) + out[b:]
        open(SRC, "w", encoding="utf-8", newline="").write(out)
        for n in (() if "--no-glasses" in sys.argv else ("glasses", "sunglasses")):
            p = os.path.join(ROOT, "Qi", "Resources", "furniture", "wear_" + n + ".png")
            im = Image.open(p).convert("RGBA")
            up = Image.new("RGBA", im.size, (0, 0, 0, 0))
            up.paste(im, (0, -SHIFT * 8))  # 图纸一行 = 图上 8 像素
            up.save(p, optimize=True)
        print("applied")


if __name__ == "__main__":
    main()
