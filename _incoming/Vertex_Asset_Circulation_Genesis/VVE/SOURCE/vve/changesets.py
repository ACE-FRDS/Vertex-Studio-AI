import json
from datetime import datetime, timezone
from pathlib import Path
from .domain import ChangeSet

class ChangeSetStore:
    def __init__(self,root:Path):
        self.root=root; self.root.mkdir(parents=True,exist_ok=True)
    def save(self,changeset:ChangeSet)->Path:
        out=self.root/f"{changeset.changeset_id}.json"
        doc=changeset.to_dict()
        doc["saved_at"]=datetime.now(timezone.utc).isoformat()
        out.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        return out
