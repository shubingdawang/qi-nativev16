from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class TextSpec:
    """
    Intermediate representation for text-only asset requests.

    The compiler intentionally separates:
      WHAT = semantic identity
      HOW = visual style
      WHERE = spatial arrangement
      DETAIL = small decorative intent
    """
    raw: str
    category: str = "unknown"
    subject: str = ""
    function: str = ""
    style_words: List[str] = field(default_factory=list)
    materials: List[str] = field(default_factory=list)
    colors: List[str] = field(default_factory=list)
    decorations: List[str] = field(default_factory=list)
    mood: List[str] = field(default_factory=list)
    composition: str = "single_asset"
    complexity: str = "detailed"
    constraints: List[str] = field(default_factory=list)


STYLE_LEXICON = {
    "可爱": "cute",
    "软萌": "cute",
    "治愈": "cozy",
    "温馨": "cozy",
    "复古": "vintage",
    "乡村": "cottage",
    "木质": "wooden",
    "极简": "minimal",
    "圣诞": "christmas",
    "万圣节": "halloween",
    "春日": "spring",
    "夏日": "summer",
    "海洋": "ocean",
    "水下": "underwater",
    "太空": "space",
    "赛博": "cyber",
    "日式": "japanese",
    "北欧": "scandinavian",
    "童话": "fairytale",
    "像素": "pixel",
}

MATERIAL_LEXICON = {
    "木头": "wood",
    "木质": "wood",
    "布": "fabric",
    "布料": "fabric",
    "毛绒": "fur",
    "毛": "fur",
    "陶瓷": "ceramic",
    "金属": "metal",
    "玻璃": "glass",
    "石头": "stone",
    "皮革": "leather",
    "纸": "paper",
}

COLOR_WORDS = [
    "红", "橙", "黄", "绿", "蓝", "紫", "粉", "白", "黑", "棕",
    "米色", "奶油", "薄荷", "薰衣草", "天蓝", "酒红", "深蓝"
]


def _contains(text: str, word: str) -> bool:
    return word.lower() in text.lower()


def compile_text_request(text: str) -> TextSpec:
    """
    Lightweight deterministic compiler.

    Claude Code should use this as an intermediate checklist, then expand it
    with its own semantic reasoning. The compiler does not attempt to replace
    the model's understanding.
    """
    spec = TextSpec(raw=text)

    for k, v in STYLE_LEXICON.items():
        if _contains(text, k):
            spec.style_words.append(v)

    for k, v in MATERIAL_LEXICON.items():
        if _contains(text, k):
            spec.materials.append(v)

    for c in COLOR_WORDS:
        if _contains(text, c):
            spec.colors.append(c)

    if any(x in text for x in ["一套", "整套", "家具套装", "套装", "系列"]):
        spec.composition = "asset_set"

    if any(x in text for x in ["精细", "丰富", "细节多", "高密度", "精致"]):
        spec.complexity = "reference_dense"

    # Preserve explicit user constraints instead of inventing visual facts.
    for x in ["不要", "不能", "避免", "不能有", "不需要"]:
        if x in text:
            spec.constraints.append(text[text.find(x):].strip())

    return spec


def build_design_brief(spec: TextSpec) -> Dict:
    """
    Converts the intermediate text spec into a design brief.

    Missing visual information is filled by category-appropriate defaults,
    not by arbitrary colors or object-specific stereotypes.
    """
    return {
        "semantic_identity": {
            "subject": spec.subject,
            "category": spec.category,
            "function": spec.function,
        },
        "visual_direction": {
            "style": list(dict.fromkeys(spec.style_words)),
            "materials": list(dict.fromkeys(spec.materials)),
            "colors": list(dict.fromkeys(spec.colors)),
            "mood": list(dict.fromkeys(spec.mood)),
        },
        "composition": {
            "mode": spec.composition,
            "camera": "shared_orthographic_2_5d",
            "centered": True,
            "standalone_export": True,
        },
        "detail_budget": {
            "level": spec.complexity,
            "macro_clusters": "required",
            "material_clusters": "required",
            "micro_accents": "required",
        },
        "constraints": spec.constraints,
        "must_infer": [
            "object archetype",
            "required structural parts",
            "support/attachment graph",
            "reasonable proportions",
            "camera-facing surfaces",
            "material-specific rendering grammar",
            "coherent palette relationships",
        ],
        "must_not_infer_as_fact": [
            "arbitrary object color",
            "arbitrary species anatomy",
            "arbitrary decoration",
            "arbitrary brand/logo",
        ],
    }
