# Height and depth diagnosis

The supplied bed example exposes the main failure mode:

### A. Screen-space drawing
Claude places polygons directly on the canvas. There is no persistent z-axis.

### B. Independent part placement
Mattress, blanket, pillow and headboard are positioned independently, so their
relative heights are guessed.

### C. No support graph
A real bed has:

floor
→ legs
→ frame
→ mattress
→ blanket/pillow

Without that graph, parts can look like stacked stickers.

### D. No camera
Without one camera model, different parts can have different perspective.

### E. No occlusion model
The drawing order follows code order rather than physical depth.

v5 fixes these with world-space coordinates, anchors, shared camera projection and
depth ordering.

This is a representation fix, not a "tell Claude to be more careful" fix.
