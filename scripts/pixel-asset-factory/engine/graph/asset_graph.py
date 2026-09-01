from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class VisualEvidence:
    """
    Evidence gathered from either text or a reference image.

    confidence:
      1.0 = explicitly stated / clearly observed
      0.0 = absent
    """
    source: str                  # "text", "reference", "inferred"
    key: str
    value: object
    confidence: float = 1.0
    locked: bool = False


@dataclass
class AssetNode:
    id: str
    semantic_role: str
    parent: Optional[str] = None
    relation: str = "part_of"
    dimensions: Dict[str, float] = field(default_factory=dict)
    material: Optional[str] = None
    visual: Dict[str, object] = field(default_factory=dict)
    required: bool = False


@dataclass
class AssetGraph:
    """
    Single canonical representation used by both generation modes.

    Text and reference observations are evidence.
    The graph is the source of truth used by topology, geometry, rendering,
    styling, variants, and QC.
    """
    asset_id: str
    category: str
    nodes: List[AssetNode] = field(default_factory=list)
    evidence: List[VisualEvidence] = field(default_factory=list)
    style: Dict[str, object] = field(default_factory=dict)
    camera: Dict[str, object] = field(default_factory=dict)
    constraints: List[str] = field(default_factory=list)
    variant_of: Optional[str] = None

    def add_evidence(self, source, key, value, confidence=1.0, locked=False):
        self.evidence.append(
            VisualEvidence(source, key, value, confidence, locked)
        )

    def add_node(self, node: AssetNode):
        self.nodes.append(node)

    def lock_explicit(self):
        for e in self.evidence:
            if e.source in ("text", "reference") and e.confidence >= .85:
                e.locked = True

    def resolve(self):
        """
        Resolve evidence without allowing weak inference to overwrite
        explicit user requirements.

        Priority:
          locked text/reference
          > strong observed reference
          > ordinary evidence
          > inference
        """
        resolved = {}
        priority = {"text": 4, "reference": 4, "inferred": 1}

        for e in self.evidence:
            score = priority.get(e.source, 0) + e.confidence
            old = resolved.get(e.key)
            if old is None or score > old[0]:
                resolved[e.key] = (score, e.value)

        return {k: v for k, (_, v) in resolved.items()}
