# -*- coding: utf-8 -*-
"""手帐的纸纹、胶带褶皱、墨印斑驳：全部用噪声算出来（不用别人的图）。

都是能无缝平铺的灰度图，平均亮度在 128 附近，App 里用叠加 / 正片叠底铺在纸色上，
纸本身的颜色照样透出来。

    python scripts/journal_textures.py      写进 Qi/Resources/Paper/，另出一张对照图 _看一眼/纸纹.png
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "Qi", "Resources", "Paper")
LOOK = os.path.join(ROOT, "_看一眼")
N = 512
rng = np.random.default_rng(20261021)


def tile_noise(scale_x, scale_y=None, octaves=4, seed=0):
    """可平铺的分形噪声（在频域里做，天然无缝）"""
    scale_y = scale_y or scale_x
    r = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        fx = np.fft.fftfreq(N)[None, :] * N
        fy = np.fft.fftfreq(N)[:, None] * N
        kx, ky = scale_x * (2 ** o), scale_y * (2 ** o)
        mask = np.exp(-((fx / kx) ** 2 + (fy / ky) ** 2))
        spec = np.fft.fft2(r.standard_normal((N, N))) * mask
        layer = np.real(np.fft.ifft2(spec))
        layer /= layer.std() + 1e-9
        out += layer * amp
        amp *= 0.5
    out /= out.std() + 1e-9
    return out


def fibers(count, length, width, seed, angle_jitter=0.6, base_angle=None):
    """一根根纤维：短弯线，可平铺（越界的从另一头接回来）"""
    r = np.random.default_rng(seed)
    img = np.zeros((N, N))
    for _ in range(count):
        x, y = r.uniform(0, N), r.uniform(0, N)
        a = (base_angle if base_angle is not None else r.uniform(0, np.pi)) + r.normal(0, angle_jitter)
        L = r.uniform(length * 0.4, length)
        v = r.uniform(0.4, 1.0) * (1 if r.random() < 0.7 else -1)
        curve = r.normal(0, 0.02)
        for t in np.linspace(0, L, int(L * 2)):
            a += curve
            px, py = int(x + np.cos(a) * t) % N, int(y + np.sin(a) * t) % N
            img[py, px] += v
            if width > 1:
                img[py, (px + 1) % N] += v * 0.5
    return img


def to_img(arr, contrast, name, blur=0):
    a = arr - arr.mean()
    a = a / (np.abs(a).max() + 1e-9)
    g = np.clip(128 + a * contrast, 0, 255).astype(np.uint8)
    im = Image.fromarray(g, "L")
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    im.save(os.path.join(OUT, name + ".jpg"), quality=88)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    # 牛皮纸：横向拉长的纤维 + 大块深浅 + 细颗粒
    kraft = tile_noise(3, 40, 5, 1) * 0.6 + tile_noise(2, 2, 2, 2) * 0.8 + rng.standard_normal((N, N)) * 0.25
    kraft += fibers(900, 40, 1, 3, 0.25, 0.0) * 0.5
    made.append(("paper_kraft", to_img(kraft, 70, "paper_kraft")))
    # 棉纸：很细的颗粒 + 极淡的云
    cotton = tile_noise(40, 40, 3, 4) * 0.5 + tile_noise(3, 3, 2, 5) * 0.4 + rng.standard_normal((N, N)) * 0.6
    made.append(("paper_cotton", to_img(cotton, 34, "paper_cotton", blur=0.4)))
    # 宣纸：长纤维、云絮
    rice = tile_noise(2, 2, 3, 6) * 0.6 + fibers(420, 90, 1, 7) * 0.9 + rng.standard_normal((N, N)) * 0.15
    made.append(("paper_rice", to_img(rice, 60, "paper_rice", blur=0.5)))
    # 新闻纸 / 旧书页：细颗粒 + 斑点 + 一点点黄斑
    news = tile_noise(30, 30, 3, 8) * 0.5 + rng.standard_normal((N, N)) * 0.5
    spots = np.zeros((N, N))
    r = np.random.default_rng(9)
    for _ in range(60):
        cx, cy, rad = r.uniform(0, N), r.uniform(0, N), r.uniform(1, 3.5)
        yy, xx = np.ogrid[:N, :N]
        d = np.hypot(((xx - cx + N / 2) % N) - N / 2, ((yy - cy + N / 2) % N) - N / 2)
        spots -= np.exp(-(d / rad) ** 2) * r.uniform(0.6, 1.4)
    news += spots * 1.2 + tile_noise(1.5, 1.5, 2, 10) * 0.5
    made.append(("paper_news", to_img(news, 52, "paper_news")))
    # 水彩纸：凹凸的冷压纹
    wc = tile_noise(14, 14, 4, 11)
    wc = np.sign(wc) * np.abs(wc) ** 0.8
    made.append(("paper_water", to_img(wc, 46, "paper_water", blur=0.6)))
    # 胶带褶皱：横向细长的折痕
    crease = tile_noise(1.2, 30, 3, 12) * 0.9 + tile_noise(6, 60, 2, 13) * 0.4
    made.append(("tape_crinkle", to_img(crease, 60, "tape_crinkle")))
    # 墨印斑驳：亮的地方是墨，暗的地方是没印上的（App 里当遮罩用）
    ink = tile_noise(60, 60, 3, 14) * 0.7 + tile_noise(8, 8, 2, 15) * 0.5 + rng.standard_normal((N, N)) * 0.45
    ink = (ink > -1.55).astype(float) * 255
    ink_im = Image.fromarray(ink.astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.5))
    # 存成带透明的：白（印上了）不透明，黑点（没印上）透明——App 里直接拿来当遮罩
    la = Image.merge("LA", (Image.new("L", ink_im.size, 255), ink_im))
    la.save(os.path.join(OUT, "ink_mask.png"))
    made.append(("ink_mask", ink_im))

    os.makedirs(LOOK, exist_ok=True)
    sheet = Image.new("L", (len(made) * 260, 260), 255)
    for i, (_, im) in enumerate(made):
        sheet.paste(im.crop((0, 0, 256, 256)), (i * 260, 2))
    sheet.save(os.path.join(LOOK, "纸纹.png"))
    print("ok", [m[0] for m in made])


if __name__ == "__main__":
    main()
