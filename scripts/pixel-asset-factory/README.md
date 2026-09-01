# Pixel Asset Factory v10

v10 establishes the **Unified Asset Graph**.

The core architecture is now:

```text
                    ┌─ TEXT ────────────┐
USER INPUT ─────────┤                    ├─→ VISUAL EVIDENCE
                    └─ REFERENCE IMAGE ─┘
                              ↓
                         ASSET GRAPH
                              ↓
                 ┌────────────┼────────────┐
                 ↓            ↓            ↓
              TOPOLOGY     GEOMETRY      STYLE
                 ↓            ↓            ↓
                 └────────────┼────────────┘
                              ↓
                       PIXEL CLUSTERS
                              ↓
                             QC
                              ↓
                      standalone PNGs
```

## This solves three important cases

### 1. Text only

> "做一个可爱的木质猫窝，奶油色，童话风，精细像素画。"

The system builds the semantic structure itself.

### 2. Reference only

The system extracts visual evidence from the image and reconstructs it
procedurally.

### 3. Reference + text

> "参考这套家具的像素风，但全部改成春日花园风。"

The reference supplies the visual language; the text supplies the requested
transformation.

## Style variants are deltas

A Christmas version is not a new unrelated drawing.

```text
base furniture
      +
Christmas StyleDelta
      ↓
Christmas furniture
```

The same mechanism works for:

- spring garden
- summer beach
- autumn
- winter cabin
- Halloween
- underwater
- space station
- Japanese room
- fantasy
- cyber
- industrial
- pastel
- dark academia
- etc.

The theme does not dictate object identity or a fixed palette.

## Sets remain modular

A set is metadata + independent graphs:

```text
bed.png
chair.png
cabinet.png
table.png
lamp.png
```

Every asset can be exported, recolored, restyled, or replaced independently.

## Current architecture status

- [x] Pixel-cluster renderer
- [x] Organic primitives
- [x] Material grammar
- [x] Anatomy validation
- [x] Text-only compiler
- [x] Generic theme palette
- [x] Unified Asset Graph
- [x] Reference image analysis layer
- [x] Reference/text evidence priority
- [x] Reference/text evidence fusion
- [x] StyleDelta architecture
- [x] Independent set assets

## Next major target

The remaining high-value layer is **reference analysis**:

```text
image
 ↓
object detection / segmentation
 ↓
silhouette extraction
 ↓
part decomposition
 ↓
camera estimation
 ↓
palette/material estimation
 ↓
cluster-density analysis
 ↓
AssetGraph
```

Once that is implemented, the same graph can genuinely accept:
**a sentence, an image, or both**.


## v11 reference analysis

A reference image can now be treated as measurable evidence:

```text
canvas
palette
pixel scale
edge density
object regions
silhouettes
parts
camera
materials
cluster language
```

The analyzer prototype lives in:

```text
engine/reference/analyzer.py
```

It intentionally does not pretend that simple image statistics can solve
semantic segmentation. The full pipeline is designed so more advanced
segmentation/vision methods can be plugged in later without changing the
AssetGraph or renderer.

The critical architecture remains:

```text
TEXT ─────────────┐
                  ├→ VISUAL EVIDENCE → ASSET GRAPH → RENDER → QC
REFERENCE IMAGE ──┘
```
