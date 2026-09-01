# v7 architecture

The previous version solved two separate problems:

1. world-space height/depth
2. semantic topology

v7 connects them to a richer pixel renderer contract.

## The important distinction

```text
semantic topology
    = what the object IS

world geometry
    = where the object IS

pixel language
    = how the object LOOKS
```

These layers are intentionally independent.

This is what allows:

```text
one bed
  ├── cozy
  ├── christmas
  ├── halloween
  ├── spring
  ├── nautical
  └── cyberpunk
```

without turning each style into a new object definition.

## Why the original bed failed

The original renderer was mathematically capable of 2.5D boxes, but the model
could still specify the wrong topology. A narrow object at the head edge is not
necessarily a headboard.

v7 therefore validates semantic role + anchor + proportion before rasterization.

## Why "more pixels" is not enough

A 10,000-pixel image can still be bad pixel art.

Quality comes from:

```text
correct silhouette
+
correct construction
+
correct occlusion
+
material-specific clusters
+
controlled palette
+
intentional detail
```

The renderer should spend detail where it communicates information.
