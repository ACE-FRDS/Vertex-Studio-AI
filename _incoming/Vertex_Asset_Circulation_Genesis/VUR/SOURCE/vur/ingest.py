from pathlib import Path
from datetime import datetime, timezone
from .integrity import sha256_file

class IngestService:
    def __init__(self,storage,registry,lineage):
        self.storage=storage; self.registry=registry; self.lineage=lineage
    def ingest_external_file(self,source:Path,namespace:str,project:str,repository=None,commit=None):
        staged=self.storage.stage_file(source,namespace)
        rec={
            "source_id":f"source://{namespace}/{source.name}",
            "source_project":project,"source_repository":repository,"commit":commit,
            "original_path":str(source),"staged_path":str(staged),
            "sha256":sha256_file(staged),"bytes":staged.stat().st_size,
            "state":"STAGED","ingested_at":datetime.now(timezone.utc).isoformat()
        }
        self.registry.append_unique("sources",rec,"source_id")
        self.lineage.append({"event":"INGEST","asset_id":rec["source_id"],"project":project,"commit":commit})
        return rec
