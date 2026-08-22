from pathlib import Path
from .registry import Registry
from .storage import Storage
from .policy import PolicyEngine
from .relations import RelationGraph
from .lineage import LineageLedger
from .vve import VVEBoundary
from .ingest import IngestService

class VURService:
    def __init__(self,root:Path):
        self.root=root
        self.registry=Registry(root/"REGISTRY"/"VUR_REGISTRY.json")
        self.storage=Storage(root)
        self.policy=PolicyEngine(root/"ZONES"/"ZONE_POLICY.json")
        self.relations=RelationGraph(root/"RELATIONS"/"RELATION_CONTRACT.json")
        self.lineage=LineageLedger(root/"LINEAGE"/"LINEAGE_LEDGER.json")
        self.vve=VVEBoundary(root/"CONNECTORS"/"VVE_OUTBOX")
        self.ingest=IngestService(self.storage,self.registry,self.lineage)
    @classmethod
    def open(cls,root): return cls(Path(root))
