from typing import Optional
import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

@dataclass
class VVEChange:
    path:str
    operation:str
    source_asset_id:Optional[str]=None
    source_path:Optional[str]=None

class VVEBoundary:
    def __init__(self,outbox:Path):
        self.outbox=outbox; self.outbox.mkdir(parents=True,exist_ok=True)
    def create_changeset(self,changeset_id,target_project_id,changes):
        doc={
            "schema":"VVE_CHANGESET","version":"1.0.0",
            "changeset_id":changeset_id,"target_project_id":target_project_id,
            "created_at":datetime.now(timezone.utc).isoformat(),
            "state":"DRAFT","real_repository_write":False,
            "changes":[asdict(c) for c in changes]
        }
        out=self.outbox/f"{changeset_id}.json"
        out.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        return out
