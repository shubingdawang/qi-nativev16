from engine.geometry.validate import validate_bed

bad = [
    {"id":"frame","position":[0,0,.45],"size":[2.25,1.85,.32]},
    {"id":"mattress","position":[.12,.10,.77],"size":[2.01,1.65,.32]},
    # Deliberately a side-like narrow block, not a real headboard.
    {"id":"headboard","position":[2.0,.2,.70],"size":[.12,1.5,.4]}
]

errors = validate_bed(bad)
print("REJECTED" if errors else "ACCEPTED")
for e in errors:
    print("-", e)
