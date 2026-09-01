from __future__ import annotations

from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Tuple
from PIL import Image
import math


@dataclass
class ImageStats:
    width: int
    height: int
    has_alpha: bool
    opaque_bbox: Tuple[int, int, int, int] | None
    unique_colors: int
    dominant_colors: List[Tuple[int, int, int, int]]
    edge_density: float
    inferred_pixel_scale: int


@dataclass
class ReferenceEvidence:
    source: str
    key: str
    value: object
    confidence: float


def _dominant_colors(img, n=12):
    rgba = img.convert("RGBA")
    colors = rgba.getdata()
    counts = {}
    for c in colors:
        if c[3] == 0:
            continue
        counts[c] = counts.get(c, 0) + 1
    return [c for c, _ in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:n]]


def _edge_density(img):
    g = img.convert("L")
    w, h = g.size
    if w < 2 or h < 2:
        return 0.0

    changes = 0
    samples = 0
    px = g.load()
    for y in range(0, h-1):
        for x in range(0, w-1):
            a = px[x, y]
            b = px[x+1, y]
            c = px[x, y+1]
            changes += (abs(a-b) > 18) + (abs(a-c) > 18)
            samples += 2
    return changes / max(1, samples)


def _infer_pixel_scale(img):
    """
    Heuristic only.

    Repeated long runs of equal colors often indicate logical pixels or
    nearest-neighbor upscaling. This does not claim to identify the original
    pixel grid perfectly.
    """
    rgba = img.convert("RGBA")
    w, h = rgba.size
    candidates = []

    for y in range(0, h, max(1, h // 64)):
        last = None
        run = 0
        for x in range(w):
            c = rgba.getpixel((x, y))
            if c == last:
                run += 1
            else:
                if run >= 2:
                    candidates.append(run)
                last = c
                run = 1

    if not candidates:
        return 1

    candidates.sort()
    mid = candidates[len(candidates)//2]
    # Conservative: only infer a scale when repeated runs are clear.
    for s in (2, 3, 4, 5, 6, 8, 10, 12):
        if abs(mid - s) <= max(1, s * .25):
            return s
    return 1


def analyze_image(path: str | Path) -> Dict:
    img = Image.open(path).convert("RGBA")
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()

    stats = ImageStats(
        width=img.width,
        height=img.height,
        has_alpha=bbox is not None,
        opaque_bbox=bbox,
        unique_colors=len(set(img.getdata())),
        dominant_colors=_dominant_colors(img),
        edge_density=round(_edge_density(img), 4),
        inferred_pixel_scale=_infer_pixel_scale(img),
    )

    evidence = [
        ReferenceEvidence("reference", "canvas.size", [img.width, img.height], 1.0),
        ReferenceEvidence("reference", "alpha.present", bbox is not None, 1.0),
        ReferenceEvidence("reference", "palette.dominant", stats.dominant_colors, .75),
        ReferenceEvidence("reference", "pixel_scale.heuristic",
                          stats.inferred_pixel_scale, .45),
        ReferenceEvidence("reference", "edge_density", stats.edge_density, .65),
    ]

    return {
        "stats": asdict(stats),
        "evidence": [asdict(e) for e in evidence],
        "next_steps": [
            "segment objects",
            "estimate object bounding boxes",
            "estimate shared camera",
            "decompose semantic parts",
            "estimate material regions",
            "convert observations into AssetGraph",
        ],
    }
