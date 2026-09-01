def validate_anatomy(parts, allowed_counts):
    """
    Generic count validator.

    Example:
      {"eye": 2, "ear": 2, "tail": 1, "leg": 4}

    The caller may override counts for species or intentionally stylized assets.
    """
    errors = []
    counts = {}
    for p in parts:
        role = p.get("semantic_role")
        if role:
            counts[role] = counts.get(role, 0) + 1

    for role, expected in allowed_counts.items():
        actual = counts.get(role, 0)
        if actual != expected:
            errors.append(f"{role}: expected {expected}, found {actual}")

    return errors
