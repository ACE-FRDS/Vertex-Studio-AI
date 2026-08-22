from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Any

class Zone(str, Enum):
    PUBLIC="public"
    RESTRICTED="restricted"
    OWNER="owner"
    INTERNAL="internal"
    QUARANTINE="quarantine"

@dataclass
class Relation:
    relation_type:str
    source_id:str
    target_id:str
    metadata:dict[str,Any]=field(default_factory=dict)

@dataclass
class VCellManifest:
    vcell_id:str
    name:str
    version:str
    kind:str
    zone:Zone=Zone.RESTRICTED
    status:str="candidate"
    relations:list[Relation]=field(default_factory=list)
    lineage:dict[str,Any]=field(default_factory=dict)
    compatibility:dict[str,Any]=field(default_factory=dict)
    artifacts:list[dict[str,Any]]=field(default_factory=list)
    def to_dict(self): return asdict(self)

@dataclass
class UnitManifest:
    unit_id:str
    name:str
    version:str
    zone:Zone=Zone.RESTRICTED
    status:str="candidate"
    vcells:list[str]=field(default_factory=list)
    relations:list[Relation]=field(default_factory=list)
    lineage:dict[str,Any]=field(default_factory=dict)
    compatibility:dict[str,Any]=field(default_factory=dict)
    deployment:dict[str,Any]=field(default_factory=lambda:{
        "vve_materialize":True,
        "direct_repository_write":False,
        "simulation_required":True,
        "human_gate_required":True
    })
    def to_dict(self): return asdict(self)
