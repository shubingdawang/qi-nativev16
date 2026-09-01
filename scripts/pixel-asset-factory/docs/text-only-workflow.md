# Text-only generation

A reference image is optional.

The system must be able to start from:

> “做一张很可爱的奶油色小床，木质床架，软软的被子，
> 有一点童话感，但不要太花，做成精细像素画。”

The correct response is NOT to complain that there is no reference image.

Instead:

```text
natural language
      ↓
intent extraction
      ↓
semantic archetype
      ↓
design brief
      ↓
topology graph
      ↓
proportion plan
      ↓
camera
      ↓
silhouette
      ↓
material plan
      ↓
palette
      ↓
pixel clusters
      ↓
QC
```

## What Claude must infer

From "小床":

- archetype = bed
- likely required parts = frame + mattress + headboard + support
- headboard is at head edge and spans the bed width
- mattress is above the frame
- legs/supports contact the floor

From "软软的被子":

- blanket is a separate soft object
- it rests on the mattress
- it may have folds
- it must not merge into the mattress

From "木质床架":

- frame uses wood material grammar
- wood grain is subtle and directional
- structural edges remain readable

From "精细像素画":

- use a sufficiently high logical resolution
- multiple cluster scales
- material-specific clusters
- micro accents
- no anti-aliasing
- no smooth-gradient shortcut

## What Claude must NOT infer

Do not silently invent facts that change identity:

- a second tail
- an extra drawer
- a side-mounted headboard
- impossible supports
- arbitrary perspective
- random accessories that become part of the object

Creative additions are allowed only in the **decorative layer**, and should
never overwrite semantic structure.

---

# Text request grammar

A request can contain any subset of:

```text
SUBJECT
STYLE
MATERIAL
COLOR
MOOD
FUNCTION
COMPOSITION
DETAIL LEVEL
CONSTRAINTS
RELATIONSHIPS
```

Example:

```text
一张
[subject: 双人床]
[style: 童话 + 温馨]
[material: 木质 + 布料]
[color: 奶油色 + 粉色]
[detail: 精细]
[constraint: 不要太花]
```

Missing fields are not errors.

The system supplies **generic category-appropriate defaults** while keeping
the semantic identity fixed.

---

# Ambiguity policy

Do not ask the user to specify every tiny visual decision.

For low-impact ambiguity:

```text
infer → render → validate
```

For identity-critical ambiguity:

```text
detect ambiguity
→ choose the most semantically conventional interpretation
→ record the assumption
```

Examples:

- "床" → normal bed archetype
- "猫窝" → pet bed, not human bed
- "柜子" → cabinet archetype
- "可爱的柜子" → cabinet topology stays unchanged

The purpose is to make text-only generation usable rather than turning it into
a questionnaire.
