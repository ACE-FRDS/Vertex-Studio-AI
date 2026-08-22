from collections import defaultdict, deque
from typing import Any, Dict, List
import json


class ARDRelationBridge:
    def __init__(self):
        self.edges = []
        self.outgoing = defaultdict(list)
        self.incoming = defaultdict(list)
        self._edge_keys = set()

    def _key(self, relation_type, source_id, target_id):
        return (relation_type, source_id, target_id)

    def add(self, relation_type: str, source_id: str, target_id: str, metadata=None):
        key = self._key(relation_type, source_id, target_id)

        if key in self._edge_keys:
            return

        self._edge_keys.add(key)

        edge = {
            "relation_type": relation_type,
            "source_id": source_id,
            "target_id": target_id,
            "metadata": metadata or {}
        }

        self.edges.append(edge)
        self.outgoing[source_id].append(edge)
        self.incoming[target_id].append(edge)

    def load_vur_registry(self, registry: Dict[str, Any]):
        for rel in registry.get("relations", []):
            if rel.get("source_id") and rel.get("target_id"):
                self.add(
                    rel.get("relation_type", "RELATED_TO"),
                    rel["source_id"],
                    rel["target_id"],
                    rel
                )

        for unit in registry.get("units", []):
            uid = unit.get("unit_id")

            for vid in unit.get("vcells", []):
                self.add(
                    "COMPOSED_OF",
                    uid,
                    vid,
                    {"source": "VUR"}
                )

        for cell in registry.get("vcells", []):
            cid = cell.get("vcell_id")
            lineage = cell.get("lineage") or {}

            for parent in lineage.get("derived_from", []) or []:
                self.add(
                    "DERIVED_FROM",
                    cid,
                    parent,
                    {"source": "VUR"}
                )

    def load_vve_changesets(self, changesets: List[Dict[str, Any]]):
        for cs in changesets:
            cid = cs.get("changeset_id")
            pid = cs.get("target_project_id")
            source_unit = cs.get("source_unit_id")

            if cid and pid:
                self.add(
                    "TARGETS_PROJECT",
                    cid,
                    pid,
                    {
                        "source": "VVE",
                        "state": cs.get("state")
                    }
                )

            if cid and source_unit:
                self.add(
                    "MATERIALIZED_FROM",
                    cid,
                    source_unit,
                    {"source": "VVE"}
                )

    def load_repository_edges(self, edges: List[Dict[str, Any]]):
        for edge in edges:
            self.add(
                edge["relation_type"],
                edge["source_id"],
                edge["target_id"],
                edge.get("metadata") or {}
            )

    def neighbors(self, asset_id: str) -> Dict[str, Any]:
        return {
            "asset_id": asset_id,
            "outgoing": self.outgoing.get(asset_id, []),
            "incoming": self.incoming.get(asset_id, [])
        }

    def impact(self, asset_id: str, max_depth: int = 4) -> Dict[str, Any]:
        seen_nodes = {asset_id}
        seen_edges = set()
        queue = deque([(asset_id, 0)])
        traversed = []

        while queue:
            current, depth = queue.popleft()

            if depth >= max_depth:
                continue

            edges = (
                list(self.outgoing.get(current, [])) +
                list(self.incoming.get(current, []))
            )

            for edge in edges:
                edge_key = self._key(
                    edge["relation_type"],
                    edge["source_id"],
                    edge["target_id"]
                )

                if edge_key not in seen_edges:
                    seen_edges.add(edge_key)
                    traversed.append(edge)

                other = (
                    edge["target_id"]
                    if edge["source_id"] == current
                    else edge["source_id"]
                )

                if other not in seen_nodes:
                    seen_nodes.add(other)
                    queue.append((other, depth + 1))

        return {
            "root": asset_id,
            "max_depth": max_depth,
            "nodes": sorted(seen_nodes),
            "edges": traversed
        }