# Pixel Asset Factory v7

## Mission

Pixel Asset Factory turns Claude Code into a procedural pixel-asset production
system capable of creating detailed, standalone pixel-art assets from natural
language.

It is NOT a prompt that says "make pixel art".

It is a layered representation + renderer + validator system.


# 0. Input modes

There are TWO valid entry points.

## Mode A — reference-assisted

```text
reference image + natural language
```

Use the image to extract visual language and use the text to define the request.

## Mode B — text-only

```text
natural language only
```

This is a first-class mode, not a degraded fallback.

The model must construct the missing visual specification using semantic
archetypes, material grammar, proportion rules, and generic design defaults.

The absence of a reference image must NEVER cause the renderer to collapse into
a few primitive rectangles.

### Text-only compiler

```text
user prose
  ↓
TextSpec
  ↓
DesignBrief
  ↓
AssetGraph
  ↓
Topology
  ↓
Geometry
  ↓
PixelRenderer
```

The compiler should extract explicit information first.

Then it should infer only what is necessary to make the asset coherent.

### Explicit beats inferred

If the user says:

> "蓝色木质衣柜"

then:
- blue = explicit
- wood = explicit
- wardrobe/cabinet = semantic identity

If the user says:

> "做得可爱一点"

then "cute" is a visual direction, not a topology change.

If the user says:

> "像你之前那套像素家具一样精细"

then increase cluster density/detail budget while preserving object identity.

### No-reference quality floor

Text-only mode must still target:

- recognizable silhouette
- believable construction
- consistent camera
- multiple depth planes
- material separation
- multi-scale pixel clusters
- deliberate highlights/shadows
- standalone transparency

A text-only asset is allowed to be stylistically original.
It is NOT allowed to become visually under-specified.

The target is reference-grade dense pixel art: readable silhouettes, coherent
3/4 perspective, real material separation, deliberate pixel clusters, and
physically plausible construction.

---

# 1. Non-negotiable pipeline

```text
USER DESCRIPTION
      ↓
SEMANTIC PARSE
      ↓
ASSET GRAPH
      ↓
TOPOLOGY / SUPPORT GRAPH
      ↓
WORLD-SPACE GEOMETRY
      ↓
CAMERA
      ↓
OCCLUSION / DEPTH
      ↓
MATERIAL PLANES
      ↓
SILHOUETTE
      ↓
PIXEL CLUSTER PASS
      ↓
DETAIL PASS
      ↓
STYLE DELTA
      ↓
SEMANTIC QC
      ↓
PIXEL QC
      ↓
INDIVIDUAL PNG EXPORT
```

Do not skip directly from prose to canvas coordinates.

---

# 2. Two representations must remain separate

## Semantic representation

Answers:

- what is the object?
- what parts does it have?
- which parts are required?
- which parts are optional?
- what supports what?
- what sits inside/on/behind what?
- what is front/back/top/head/foot/left/right?

## Visual representation

Answers:

- exact shape
- palette
- lighting
- pixel clusters
- texture
- decorative details

A visual style is never allowed to redefine object topology.

---

# 3. Asset Graph

Every asset is represented as a graph.

```yaml
asset:
  id: bed_001
  archetype: bed

parts:
  - frame
  - mattress
  - headboard
  - pillow
  - blanket
  - legs

relations:
  - frame supports mattress
  - mattress supports blanket
  - mattress supports pillow
  - frame supports headboard
  - legs support frame
```

For an animal:

```yaml
animal:
  body
  head
  ears
  legs
  paws
  tail
  eyes
```

The graph prevents accidental duplication.

If an animal already has one tail, a second tail cannot appear unless the
semantic description explicitly requests it.

---

# 4. Topology before geometry

Topology is the identity of an object.

Examples:

### Bed

```text
headboard → attached to head edge of frame
frame → supports mattress
mattress → supports bedding
legs → support frame
```

### Chair

```text
legs → support seat
seat → supports body
backrest → rises from rear of seat
```

### Cabinet

```text
feet → support carcass
carcass → contains shelves/drawers
doors → attached to carcass
handles → attached to doors
```

### Refrigerator

```text
body → stands on floor
doors → attached to front face
handle → attached to door
interior → exists behind open door only
```

The system should have archetypes for common classes, but archetypes are
templates for topology, not hard-coded appearances.

---

# 5. World-space geometry

Every volumetric part has:

```text
position = [x, y, z]
size     = [width, depth, height]
```

Every attachment has a named anchor.

Examples:

```text
mattress.bottom → frame.top
pillow.bottom  → mattress.top
headboard.base → frame.head_edge
```

Never fake height by stretching a 2D rectangle.

If an object is taller, its `z` extent increases.

---

# 6. Camera

One camera belongs to the entire scene/set.

Recommended default:

```yaml
projection: orthographic_2_5d
azimuth: 45°
elevation: 30°
```

Individual objects must not invent their own perspective.

A set of 30 furniture assets should look like it came from one game world.

---

# 7. Organic primitives

Boxes are NOT sufficient.

The renderer must support:

```text
box
rounded_box
capsule
ellipsoid
stepped_curve
arc
extruded_outline
soft_blob
cylinder
cone
custom_polygon
```

Use different primitives according to semantic identity.

Examples:

```text
mattress → rounded_box
pillow   → soft_blob
plate    → cylinder / ellipse
cat body → ellipsoid + custom silhouette
tail     → stepped_curve
bread    → custom_polygon + crust layers
shirt    → extruded_outline + cloth folds
```

This is essential for avoiding the "everything is a rectangular block" failure.

---

# 8. Silhouette first

Before interior detail, render a monochrome silhouette.

QC asks:

1. Is the object recognizable without texture?
2. Are its proportions correct?
3. Are appendages attached to plausible locations?
4. Are negative spaces correct?
5. Is the silhouette consistent with the archetype?

If silhouette QC fails, do NOT continue to texture.

---

# 9. Pixel cluster system

Pixel art is not a smooth illustration reduced to low resolution.

Use intentional clusters.

Cluster categories:

```text
OUTLINE
BASE
SHADOW
MIDTONE
HIGHLIGHT
MATERIAL_TEXTURE
ACCENT
CONTACT_SHADOW
```

A cluster should communicate form or material.

Avoid:

- random single-pixel noise
- anti-aliased edges
- blur
- smooth gradients
- photographic texture
- unnecessary dithering

Use stepped edges and controlled cluster sizes.

---

# 10. Material grammar

Materials have their own rendering grammar.

### Wood

```text
large warm planes
+
directional grain clusters
+
dark seams
+
small edge highlights
```

### Fabric

```text
soft large planes
+
fold clusters
+
low-contrast weave hints
+
contact shadows
```

### Metal

```text
hard silhouette
+
dark underside
+
bright narrow highlight
+
edge reflection
```

### Ceramic

```text
clean contour
+
large light plane
+
small rim highlight
+
subtle interior shadow
```

### Glass

```text
transparent/empty interior
+
strong rim
+
selective highlight
```

### Fur

```text
large body mass
+
controlled tuft silhouette
+
directional shadow clusters
```

The material system must be generic. It must not assume that a cat is orange,
a Christmas object is red/green, etc.

---

# 11. Style packs are deltas

A style is never a replacement asset.

```text
BASE ASSET
   ↓
STYLE DELTA
   ↓
RENDER
```

A style delta may change:

```text
palette
surface pattern
trim
ornaments
material treatment
decorative silhouette
```

It may NOT arbitrarily change:

```text
support graph
object identity
camera
gravity
part count
attachment points
```

Example:

```yaml
style:
  name: christmas
  palette: generated_from_theme
  decorations:
    - ribbon
    - ornament
    - pine
  material_variants:
    fabric: festive_fabric
```

The palette is generated from the theme rather than being hard-coded to
"Christmas = red + green".

---

# 12. Reference image usage

A reference image is a STYLE / STRUCTURE reference, not a tracing target.

Extract:

```text
composition
camera
silhouette language
pixel scale
cluster density
outline behavior
material grammar
palette relationships
```

Do NOT blindly copy object placement if the requested asset differs.

When a reference contains multiple objects, identify and reconstruct each
semantic asset separately.

---

# 13. Standalone export

Every requested asset must exist as an independent transparent PNG.

For a set:

```text
output/
  furniture/
    bed.png
    chair.png
    cabinet.png
    desk.png
  food/
    bread.png
    soup.png
    cake.png
```

A contact sheet is optional and is never the canonical asset.

Do not require the user to cut sprites out manually.

---

# 14. Physical plausibility QC

Before export, test:

### Gravity
Does every heavy object have support?

### Attachment
Do handles, legs, tails, straps, etc. actually connect to their parent?

### Occlusion
Does the front object hide the rear object correctly?

### Scale
Are small details appropriately scaled relative to the parent?

### Duplication
Are there accidental extra limbs, tails, handles, eyes, etc.?

### Material
Does the surface read as its intended material?

### Color contamination
Did a decoration accidentally change the material of the object beneath it?

Example failure:

```text
green Christmas decoration
        ↓
cat litter becomes green
```

That is forbidden.

### Soft-object deformation
A cat on a bed may compress a blanket locally, but must not melt into it.

---

# 15. Pixel QC

Check:

```text
transparent background
no anti-aliasing
nearest-neighbor upscale
consistent logical pixel size
closed silhouette
no accidental isolated pixels
no accidental fused components
```

The renderer should also inspect connected components where useful.

---

# 16. Iteration protocol

When the user says:

> "Make another set in Christmas style."

Do NOT regenerate the whole semantic structure from scratch.

Load:

```text
base_asset_set
```

clone it:

```text
variant_set = clone(base_asset_set)
```

apply:

```text
christmas.style_delta
```

then rerender.

When the user says:

> "Make the same furniture but Japanese style."

Only style/material/decorative layers change.

---

# 17. When Claude should use procedural rendering vs. an image model

Procedural rendering is preferred when:

- geometry is important
- assets must be independently exported
- exact transparency is required
- consistency across a set matters
- style variants must preserve topology

An image-generation adapter may be used when:

- an organic character is extremely irregular
- painterly micro-detail is required
- a reference contains details that are inefficient to hand-author

If an image adapter is used, its result still passes through semantic QC and
standalone extraction/export.

The skill must never falsely claim that procedural code has neural image
generation capabilities.

---

# 18. Definition of success

The result is successful only when all four layers are correct:

```text
SEMANTICS
"this is actually a bed"

GEOMETRY
"the bed occupies believable space"

PIXEL LANGUAGE
"this looks deliberately pixel-art"

DETAIL
"the object is rich enough to match the reference density"
```

A technically valid PNG that looks like a few rectangles is NOT success.


# Unified graph rule

Text-only generation and reference-assisted generation MUST converge into the
same `AssetGraph`.

Never maintain separate rendering logic for:
- text assets
- reference assets
- style variants

The renderer should not care where the visual evidence came from.

## Evidence model

```text
text fact       → evidence(source=text)
reference fact  → evidence(source=reference)
inference       → evidence(source=inferred)
```

Explicit text and strong reference observations outrank inference.

## Style variants

Never regenerate a variant by starting from a blank prompt.

Use:

```text
Base AssetGraph
      ↓
StyleDelta
      ↓
Variant AssetGraph
      ↓
Render
```

This preserves:
- object identity
- proportions
- topology
- anatomy
- shared visual language

while changing:
- palette relationships
- materials
- patterns
- trims
- decorations
- mood
- lighting

## Set generation

A "set" is a collection of independent assets plus a shared style contract.

Each output remains individually exportable:

```text
set/
  bed.png
  chair.png
  cabinet.png
  lamp.png
  table.png
```

The set relationship is metadata, not a requirement to render them into one
spritesheet.

## Quality floor

Whether the input is one sentence or a detailed reference image, the renderer
must not fall back to icon-level simplicity.

Minimum expected structure:

1. silhouette
2. depth planes
3. structural parts
4. material separation
5. shadow/highlight clusters
6. medium details
7. micro accents
8. semantic QC


# Reference analysis

When a reference image is available, treat it as a source of visual evidence.

Extract, in order:

1. global canvas/background
2. object regions
3. silhouettes
4. semantic parts
5. occlusion/depth
6. shared camera
7. palette relationships
8. material cues
9. pixel-cluster language

Do not trace the image directly into the final asset.

## Reference + text priority

Explicit text changes the requested dimension.

```text
reference structure + text color change
→ preserve structure, change color
```

```text
reference cat + text "replace with rabbit"
→ preserve visual language, replace semantic topology
```

```text
reference style + text "make it Christmas"
→ preserve pixel language, apply Christmas StyleDelta
```

## Reference-only mode

If the user provides an image without detailed instructions, infer the visual
language and use it as constraints for original procedural generation.

The output must still pass through the same AssetGraph and QC system.

## No-reference mode

If no image exists, skip reference analysis and construct the AssetGraph from
text + semantic defaults.

Both modes MUST converge before rendering.
