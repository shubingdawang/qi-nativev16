# Unified input architecture

There are not two separate generators.

There is **one generator with two evidence sources**.

```text
                 ┌── text ───────────┐
                 │                   ↓
user request ────┤              Visual Evidence
                 │                   ↓
                 └── reference ─────┘
                                     ↓
                               Asset Graph
                                     ↓
                         ┌───────────┼───────────┐
                         ↓           ↓           ↓
                      topology    geometry     style
                         ↓           ↓           ↓
                         └───────────┼───────────┘
                                     ↓
                               pixel renderer
                                     ↓
                                     QC
```

## Why this matters

A reference image tells the system things like:

- silhouette
- proportions
- camera
- palette relationships
- material appearance
- detail density

Text can tell the system things like:

- "make it Christmas"
- "replace the cat with a rabbit"
- "keep the bed structure"
- "make the blanket blue"
- "don't add accessories"

These should not fight each other.

They become separate evidence entries in the same graph.

---

# Evidence priority

The system must distinguish:

### Locked semantic facts

User explicitly says:

> "四条腿"

Do not generate five.

### Strong visual facts

Reference clearly shows:

> headboard spans the head edge of the bed.

Preserve it unless text explicitly requests a change.

### Inferred facts

The user did not specify:

> exact wood grain direction.

Infer it from material grammar.

---

# Style variants

A style variant is NOT a redraw from scratch.

It is:

```text
base AssetGraph
       +
StyleDelta
       ↓
variant AssetGraph
       ↓
render
```

Example:

```text
base:
  cream wooden bed
  pink blanket
  cat

StyleDelta:
  theme = winter_cabin
  add = knit trim
  add = pine ornament
  palette_shift = cool_cream
```

The topology remains the bed.

The cat remains a cat.

The blanket remains a blanket.

Only the requested style layer changes.

---

# "Same set, new style"

For a furniture collection:

```text
bed_001
chair_001
cabinet_001
table_001
lamp_001
```

store them as independent graphs.

Then:

```text
ordinary_set
     ↓
style_delta(christmas)
     ↓
christmas_set
```

This means a later request can modify the whole set without regenerating
unrelated geometry.

---

# Text-only + reference example

Text:

> "做一套和这张图一样精细的家具，但改成春日花园风，
> 不要圣诞元素。"

Reference supplies:

```text
pixel density
camera
outline language
cluster scale
proportion language
```

Text supplies:

```text
asset set
spring garden style
negative constraint: no Christmas
```

The renderer receives one unified graph.

---

# Critical rule

Never encode a theme as a fixed object-specific palette.

"Christmas" is a style delta.

It can affect:

- palette
- fabric pattern
- trim
- ornaments
- lighting
- small props

It must NOT imply:

- every object becomes red
- every animal becomes a specific color
- every material becomes green
- arbitrary anatomy changes

That distinction is what makes the system reusable.
