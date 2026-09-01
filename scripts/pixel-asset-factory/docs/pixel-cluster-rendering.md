# Pixel Cluster Rendering — v8

The goal is not "more pixels". The goal is **more information per cluster**.

## Resolution

Use a logical canvas first:

```text
64×64 / 96×96 / 128×128 / 160×160
```

Then upscale with nearest-neighbor.

Never draw at final display resolution with anti-aliased primitives.

## Cluster hierarchy

```text
silhouette clusters
    ↓
large light/shadow planes
    ↓
material clusters
    ↓
structural seams
    ↓
small accents
```

Do not reverse this order.

## Cluster discipline

A detail should normally occupy a small connected group of pixels rather than
a cloud of unrelated one-pixel noise.

Use isolated single pixels only when they communicate:
- a tiny highlight
- a sparkle
- a button
- an eye
- a small accent

## Organic objects

Use `soft_blob` or `stepped_curve` rather than forcing animals, pillows, food,
clothing folds, tails, straps, etc. into rectangular boxes.

## Material separation

A green ornament must not recolor the surface underneath it.

A cat lying on a blanket must have:
- an independent silhouette
- a contact shadow
- an occlusion boundary
- independent fur clusters

This prevents the "melted into the blanket" failure.

## Density target

Reference-grade assets should have multiple information scales:

```text
macro  → silhouette
medium → planes / folds / panels
micro  → seams / texture / accents
```

If only macro shapes exist, the result is a simple pixel icon, not a detailed
asset.
