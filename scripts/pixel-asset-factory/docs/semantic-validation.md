# Semantic validation — v6

The previous prototype demonstrated an important failure: correct 2.5D math does
not guarantee that the model described the correct object.

A bed can become "a low chair with a pink block" if its topology is underspecified.

Therefore v6 validates **object semantics before rendering**.

## Bed invariants

A canonical bed has:

```text
                 HEADBOARD
            ┌─────────────────┐
            │                 │
            │                 │
            └─────────────────┘
        ┌─────────────────────────┐
        │         PILLOW          │
        │─────────────────────────│
        │                         │
        │          MATTRESS       │
        │                         │
        └─────────────────────────┘
          │                     │
          │       FRAME         │
          │                     │
        floor                 floor
```

The headboard is a **wide vertical slab across the head edge**.

It is never allowed to become a side rail, narrow end post, or a single diagonal
bar merely because of camera projection.

## Validation rules

Before rasterization:

1. `headboard.width ≈ mattress.width`
2. `headboard.depth << headboard.width`
3. `headboard.height > mattress.height`
4. `headboard.y` is at the head edge
5. `headboard.z` starts at or near the frame
6. `mattress.z > frame.z`
7. `blanket.z >= mattress.top`
8. `pillow` is inside the mattress footprint and near the head edge
9. four legs must terminate on the floor plane
10. no decorative object may be used to define structural geometry

## Object topology vs. style

A Christmas bed is still a bed.

Style changes:
- palette
- fabric pattern
- ornaments
- trim
- decorative silhouette

Style must NOT change:
- support relationships
- headboard orientation
- mattress placement
- gravity
- object scale
- camera conventions

This is the same mechanism that lets the factory create arbitrary themes
without hard-coding "Christmas = red and green".
