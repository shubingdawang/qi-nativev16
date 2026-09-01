def validate_bed(parts, tolerance=0.35):
    by_id = {p["id"]: p for p in parts}
    required = ["frame", "mattress", "headboard"]
    missing = [x for x in required if x not in by_id]
    errors = [f"missing required part: {x}" for x in missing]
    if errors:
        return errors

    f = by_id["frame"]
    m = by_id["mattress"]
    h = by_id["headboard"]

    # [x, y, z], [w, d, h]
    if abs(h["size"][0] - m["size"][0]) > m["size"][0] * tolerance:
        errors.append("headboard must span approximately the full mattress width")

    if h["size"][1] >= h["size"][0] * 0.35:
        errors.append("headboard is too deep; it is becoming a side/box object")

    if h["size"][2] <= m["size"][2]:
        errors.append("headboard must be taller than mattress thickness")

    expected_head_y = f["position"][1] + f["size"][1]
    actual_head_y = h["position"][1]
    if abs(actual_head_y - expected_head_y) > max(0.15, f["size"][1] * 0.12):
        errors.append("headboard is not anchored to the head edge of the frame")

    mattress_bottom = m["position"][2]
    frame_top = f["position"][2] + f["size"][2]
    if abs(mattress_bottom - frame_top) > 0.18:
        errors.append("mattress is not resting on the frame")

    return errors
