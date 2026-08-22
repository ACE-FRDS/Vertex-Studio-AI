from collections import defaultdict, deque
from typing import Any, Dict, List, Set, Tuple

class ARDRelationBridge:
    def __init__(self):
        self.edges = []
        self.outgoing = defaultdict(list)
        self.incoming = defaultdict(list)

    def add(self, relation_type: str, source_id: str, target_id: str, metadata=None):
        edge = {
            "relation_type":relation_type,
            "source_id":source_id,
            "target_id":target_id,
            "metadata":metadata or {}
        }
        self.edges.append(edge)
        self.outgoing[source_id].append(edge)
        self.incoming[target_id].append(edge)

    def load_vur_registry(self, registry: Dict[str, Any]):
        for rel in registry.get("relations", []):
            if rel.get("source_id") and rel.get("target_id"):
                self.add(rel.get("relation_type","RELATED_TO"), rel["source_id"], rel["target_id"], rel)
        for unit in registry.get("units", []):
            uid = unit.get("unit_id")
            for vid in unit.get("vcells", []):
                self.add("COMPOSED_OF", uid, vid, {"source":"VUR"})
        for cell in registry.get("vcells", []):
            cid = cell.get("vcell_id")
            lineage = cell.get("lineage") or {}
            for parent in lineage.get("derived_from", []) or []:
                self.add("DERIVED_FROM", cid, parent, {"source":"VUR"})

    def load_vve_changesets(self, changesets: List[Dict[str, Any]]):
        for cs in changesets:
            cid = cs.get("changeset_id")
            pid = cs.get("target_project_id")
            if cid and pid:
                self.add("TARGETS_PROJECT", cid, pid, {"source":"VVE","state":cs.get("state")})
            source_unit = cs.get("source_unit_id")
            if cid and source_unit:
                self.add("MATERIALIZED_FROM", cid, source_unit, {"source":"VVE"})

    def neighbors(self, asset_id: str) -> Dict[str, Any]:
        return {
            "asset_id":asset_id,
            "outgoing":self.outgoing.get(asset_id, []),
            "incoming":self.incoming.get(asset_id, [])
        }

    def impact(self, asset_id: str, max_depth: int = 4) -> Dict[str, Any]:
        seen = {asset_id}
        q = deque([(asset_id,0)])
        traversed = []
        while q:
            current, depth = q.popleft()
            if depth >= max_depth:
                continue
            edges = list(self.outgoing.get(current, [])) + list(self.incoming.get(current, []))
            for edge in edges:
                other = edge["target_id"] if edge["source_id"] == current else edge["source_id"]
                traversed.append(edge)
                if other not in seen:
                    seen.add(other)
                    q.append((other, depth+1))
        return {"root":asset_id,"max_depth":max_depth,"nodes":sorted(seen),"edges":traversed}
