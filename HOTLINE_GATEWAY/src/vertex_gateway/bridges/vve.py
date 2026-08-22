import json, time, uuid
from pathlib import Path
from typing import Any, Dict, List
from ..util import write_json_atomic, read_json

class VVEBridge:
    def __init__(self, vve_root: Path, outbox: Path):
        self.root = vve_root
        self.outbox = outbox
        self.outbox.mkdir(parents=True, exist_ok=True)

    def list_changesets(self) -> List[Dict[str, Any]]:
        items = []
        for p in sorted(self.outbox.glob("*.json")):
            try:
                items.append(read_json(p))
            except Exception:
                continue
        return items

    def create_changeset(self, project_id: str, changes: List[Dict[str, Any]], source: str = "VCRAS") -> Dict[str, Any]:
        cid = "changeset://gateway/%s" % uuid.uuid4()
        doc = {
            "schema":"VVE_CHANGESET",
            "version":"1.0.0",
            "changeset_id":cid,
            "target_project_id":project_id,
            "source":source,
            "created_at":time.time(),
            "state":"DRAFT",
            "real_repository_write":False,
            "simulation_required":True,
            "human_gate_required":True,
            "changes":changes
        }
        safe = cid.split("/")[-1] + ".json"
        write_json_atomic(self.outbox / safe, doc)
        return doc
