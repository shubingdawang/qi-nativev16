# Reference Analysis — v11

This layer converts a reference image into **evidence**, not a final drawing.

## Important distinction

Do not ask a coding model to "look at the image and recreate it" in one step.

Use:

```text
IMAGE
 ↓
IMAGE STATISTICS
 ↓
OBJECT REGIONS
 ↓
SILHOUETTES
 ↓
PARTS
 ↓
DEPTH / OCCLUSION
 ↓
CAMERA
 ↓
PALETTE
 ↓
MATERIALS
 ↓
PIXEL CLUSTER CHARACTERISTICS
 ↓
REFERENCE EVIDENCE
 ↓
ASSET GRAPH
```

## Stage 1 — global image analysis

Measure:

- canvas size
- alpha/background
- dominant colors
- approximate pixel scale
- edge density
- transparent margins

These measurements are evidence, not absolute truth.

## Stage 2 — object segmentation

For a sheet containing:

```text
bed
chair
lamp
cabinet
```

the analyzer must create four candidate object regions.

Each region becomes an independent AssetGraph candidate.

The final exports are:

```text
bed.png
chair.png
lamp.png
cabinet.png
```

No manual cutting should be required.

## Stage 3 — silhouette extraction

For each object:

```text
background
  ↓
object mask
  ↓
outer contour
  ↓
negative spaces
```

The silhouette is checked before interior detail.

## Stage 4 — semantic decomposition

Do not stop at a bounding box.

For a bed:

```text
frame
mattress
headboard
pillow
blanket
legs
```

For a cat:

```text
body
head
ears
eyes
legs
paws
tail
```

The exact anatomy is determined by the observed species/asset, not by a
hard-coded "cat = orange" template.

## Stage 5 — camera estimation

When several objects share a reference sheet, estimate one common camera:

```text
azimuth
elevation
orthographic scale
ground/contact plane
```

Do not let each asset invent a different camera.

## Stage 6 — palette analysis

Extract relationships rather than merely copying colors:

```text
outline
deep shadow
shadow
base
mid
light
accent
```

This lets the palette be transferred to another asset without destroying
material readability.

## Stage 7 — material inference

Use visual cues to estimate:

```text
wood
fabric
metal
ceramic
glass
fur
paper
plastic
```

Material inference must remain probabilistic.

## Stage 8 — cluster analysis

Estimate:

- average cluster size
- outline thickness
- detail density
- highlight density
- shadow density
- dithering tendency
- isolated-pixel frequency

The purpose is to reproduce the **pixel language**, not merely the image colors.

---

# Reference + text conflict resolution

Example:

Reference:
> a pink bed

Text:
> "保持结构，但改成蓝色"

Result:

```text
structure = reference
camera = reference
pixel language = reference
color = text
```

Text wins where it explicitly requests a change.

Another example:

Reference shows a cat.

Text:
> "把猫换成兔子"

Result:

```text
scene style = reference
new semantic identity = rabbit
rabbit topology = semantic defaults
```

Do not force the rabbit into cat anatomy.

---

# Reference-only generation

If the user provides only an image and says:

> "做成这种风格的一套家具"

the system should infer:

- style
- camera
- density
- material grammar
- palette relationships

and independently design new furniture using those constraints.

It is **style transfer of a visual language**, not pixel tracing.

---

# Text-only generation

If no image exists:

```text
text
 ↓
semantic compiler
 ↓
AssetGraph
 ↓
same renderer
```

The reference analyzer is simply bypassed.

Thus both modes converge on the exact same rendering backend.
