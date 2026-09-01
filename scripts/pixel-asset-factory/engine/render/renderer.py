from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Tuple, List, Optional
from PIL import Image, ImageDraw
import math
import random

RGBA = Tuple[int, int, int, int]


def shade(c: RGBA, factor: float) -> RGBA:
    return (
        max(0, min(255, round(c[0] * factor))),
        max(0, min(255, round(c[1] * factor))),
        max(0, min(255, round(c[2] * factor))),
        c[3],
    )


def mix(a: RGBA, b: RGBA, t: float) -> RGBA:
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] * (1-t) + b[i] * t) for i in range(4))


@dataclass
class Palette:
    outline: RGBA
    shadow: RGBA
    base: RGBA
    mid: RGBA
    light: RGBA
    accent: RGBA
    dark_accent: RGBA


@dataclass
class PixelPart:
    id: str
    kind: str
    position: Tuple[float, float, float]
    size: Tuple[float, float, float]
    material: str = "generic"
    palette: Optional[Palette] = None
    parent: Optional[str] = None
    layer: int = 0
    details: List[dict] = field(default_factory=list)


class PixelClusterRenderer:
    """
    Logical-resolution pixel renderer.

    Important: render at logical resolution and upscale with NEAREST.
    It deliberately avoids anti-aliasing and smooth vector rasterization.
    """

    def __init__(self, logical_size=(128, 128), scale_up=4, seed=7, camera=None):
        self.logical_size = logical_size
        self.scale_up = scale_up
        self.rng = random.Random(seed)
        self.camera = camera

    def _screen(self, x, y, z):
        if self.camera is not None:
            return self.camera.project(x, y, z)

        # Fixed orthographic 2.5D fallback.
        sx = (x - y) * 0.82 + self.logical_size[0] * .50
        sy = (x + y) * 0.43 - z * .92 + self.logical_size[1] * .62
        return sx, sy

    def _box(self, part: PixelPart):
        x, y, z = part.position
        w, d, h = part.size
        pts = {
            "tfl": self._screen(x, y, z+h),
            "tfr": self._screen(x+w, y, z+h),
            "tbr": self._screen(x+w, y+d, z+h),
            "tbl": self._screen(x, y+d, z+h),
            "bfl": self._screen(x, y, z),
            "bfr": self._screen(x+w, y, z),
            "bbr": self._screen(x+w, y+d, z),
            "bbl": self._screen(x, y+d, z),
        }
        return pts

    @staticmethod
    def _poly(draw, pts, fill, outline=None, width=1):
        pts = [(round(x), round(y)) for x, y in pts]
        draw.polygon(pts, fill=fill)
        if outline:
            draw.line(pts + [pts[0]], fill=outline, width=width, joint="curve")

    def _cluster_line(self, draw, a, b, color, width=1):
        # Stepped pixel line; never anti-aliased.
        x0, y0 = map(round, a)
        x1, y1 = map(round, b)
        draw.line((x0, y0, x1, y1), fill=color, width=max(1, round(width)))

    def _texture(self, draw, polygon, palette: Palette, material: str, density=0.16):
        # Deterministic small clusters, constrained to the bounding box.
        xs = [p[0] for p in polygon]
        ys = [p[1] for p in polygon]
        minx, maxx = max(0, int(min(xs))), min(self.logical_size[0]-1, int(max(xs)))
        miny, maxy = max(0, int(min(ys))), min(self.logical_size[1]-1, int(max(ys)))

        if maxx <= minx or maxy <= miny:
            return

        if material in ("wood", "stone"):
            step = 4
            for y in range(miny, maxy + 1, step):
                if self.rng.random() > density:
                    continue
                x = minx + self.rng.randrange(max(1, maxx-minx+1))
                length = self.rng.randrange(3, 9)
                col = mix(palette.shadow, palette.base, .35)
                draw.rectangle((x, y, min(maxx, x+length), y+1), fill=col)

        elif material in ("fabric", "fur"):
            step = 5
            for y in range(miny, maxy + 1, step):
                for x in range(minx, maxx + 1, step):
                    if self.rng.random() < density:
                        col = palette.mid if self.rng.random() < .65 else palette.light
                        draw.rectangle((x, y, x+1, y+1), fill=col)

        elif material == "ceramic":
            # A few restrained speckles; ceramic should remain clean.
            for _ in range(max(1, int((maxx-minx)*(maxy-miny)*density/350))):
                x = self.rng.randint(minx, maxx)
                y = self.rng.randint(miny, maxy)
                draw.point((x, y), fill=mix(palette.shadow, palette.base, .55))

    def _render_box(self, draw, p: PixelPart):
        pal = p.palette
        P = self._box(p)

        # Contact shadow is a separate cluster, not a darkening of the object.
        shadow = shade(pal.outline, .65)
        cx = (P["bfl"][0] + P["bbr"][0]) / 2
        cy = max(P["bfl"][1], P["bfr"][1], P["bbr"][1], P["bbl"][1]) + 1
        draw.ellipse((cx-7, cy-2, cx+8, cy+3), fill=shadow)

        self._poly(draw, [P["tfl"], P["tfr"], P["tbr"], P["tbl"]], pal.light, pal.outline)
        self._poly(draw, [P["tfl"], P["tfr"], P["bfr"], P["bfl"]], pal.base, pal.outline)
        self._poly(draw, [P["tfr"], P["tbr"], P["bbr"], P["bfr"]], pal.mid, pal.outline)

        # Material-specific cluster pass.
        self._texture(draw,
                      [P["tfl"], P["tfr"], P["tbr"], P["tbl"]],
                      pal, p.material, .11)
        self._texture(draw,
                      [P["tfl"], P["tfr"], P["bfr"], P["bfl"]],
                      pal, p.material, .10)

        # Deliberate edge highlight and underside cluster.
        self._cluster_line(draw, P["tfl"], P["tfr"], pal.light, 1)
        self._cluster_line(draw, P["bfl"], P["bfr"], shade(pal.outline, .85), 1)

    def _render_soft_blob(self, draw, p: PixelPart):
        pal = p.palette
        x, y, z = p.position
        w, d, h = p.size
        pts = []
        steps = 16
        for i in range(steps):
            t = math.tau * i / steps
            # 2.5D flattened organic silhouette.
            px = x + w/2 + math.cos(t) * w/2
            py = y + d/2 + math.sin(t) * d/2
            pz = z + h * (.50 + .10*math.sin(t))
            pts.append(self._screen(px, py, pz))

        # shadow first
        xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
        draw.ellipse((min(xs)-2, max(ys)-1, max(xs)+2, max(ys)+2), fill=shade(pal.outline,.65))
        self._poly(draw, pts, pal.base, pal.outline)

        # Large form clusters.
        hi = mix(pal.light, pal.base, .25)
        draw.polygon([
            (round(min(xs)+3), round(min(ys)+3)),
            (round(max(xs)-5), round(min(ys)+2)),
            (round(max(xs)-9), round(min(ys)+7)),
            (round(min(xs)+6), round(min(ys)+8)),
        ], fill=hi)

        self._texture(draw, pts, pal, p.material, .14)

    def _render_curve(self, draw, p: PixelPart):
        pal = p.palette
        x, y, z = p.position
        w, d, h = p.size
        # Stepped Bézier-like curve.
        points = []
        for i in range(17):
            t = i/16
            px = x + w*t
            py = y + d*(math.sin(t*math.pi)*.65)
            pz = z + h*(.15 + .55*math.sin(t*math.pi))
            points.append(self._screen(px, py, pz))
        self._cluster_line(draw, points[0], points[-1], pal.outline, 3)
        for a,b in zip(points, points[1:]):
            self._cluster_line(draw, a, b, pal.accent, 2)

    def _render_detail(self, draw, d, palette):
        typ = d.get("type")
        if typ == "seam":
            self._cluster_line(draw, d["a"], d["b"], palette.shadow, d.get("width",1))
        elif typ == "highlight":
            self._cluster_line(draw, d["a"], d["b"], palette.light, d.get("width",1))
        elif typ == "rect":
            x,y,w,h = d["box"]
            draw.rectangle((x,y,x+w,y+h), fill=d.get("fill", palette.accent))
        elif typ == "cluster":
            x,y = d["at"]
            r = d.get("radius",1)
            draw.rectangle((x-r,y-r,x+r,y+r), fill=d.get("fill",palette.accent))

    def render(self, parts: List[PixelPart], background=(0,0,0,0)):
        im = Image.new("RGBA", self.logical_size, background)
        draw = ImageDraw.Draw(im)

        # Stable world/depth order. layer breaks ties intentionally.
        ordered = sorted(
            parts,
            key=lambda p: (p.layer, sum(p.position) + p.position[2]*.35)
        )

        for p in ordered:
            if p.kind == "box":
                self._render_box(draw, p)
            elif p.kind == "soft_blob":
                self._render_soft_blob(draw, p)
            elif p.kind == "stepped_curve":
                self._render_curve(draw, p)
            else:
                raise ValueError(f"Unsupported primitive: {p.kind}")

            for detail in p.details:
                self._render_detail(draw, detail, p.palette)

        return im.resize(
            (self.logical_size[0]*self.scale_up,
             self.logical_size[1]*self.scale_up),
            Image.Resampling.NEAREST
        )
