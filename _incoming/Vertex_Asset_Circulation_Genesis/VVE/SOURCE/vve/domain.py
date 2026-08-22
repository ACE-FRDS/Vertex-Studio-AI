from dataclasses import dataclass, field, asdict
from typing import Any

@dataclass(slots=True)
class VirtualFile:
    path:str
    state:str
    real_path:str|None=None
    overlay_path:str|None=None
    source_asset_id:str|None=None
    metadata:dict[str,Any]=field(default_factory=dict)

@dataclass(slots=True)
class ChangeSet:
    changeset_id:str
    project_id:str
    files:list[VirtualFile]=field(default_factory=list)
    state:str="DRAFT"
    real_repository_write:bool=False
    def to_dict(self): return asdict(self)
