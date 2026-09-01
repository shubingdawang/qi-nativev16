from copy import deepcopy

def apply_style_delta(asset, style):
    """
    Style changes visual properties only.
    Geometry/topology remains cloned from the base asset.
    """
    out = deepcopy(asset)
    out["style_ref"] = style.get("style_id", "variant")

    overrides = style.get("material_overrides", {})
    for part in out.get("parts", []):
        material = part.get("material")
        if material in overrides:
            part["material"] = overrides[material]

    out["style_delta"] = {
        "palette": style.get("palette", {}),
        "patterns": style.get("patterns", []),
        "decorations": style.get("decorations", [])
    }
    return out
