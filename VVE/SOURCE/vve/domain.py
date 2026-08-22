from typing import Optional
from dataclasses import dataclass, field, asdict
from typing import Any

@dataclass
class VirtualFile:
    path:str
    state:str
    real_path:Optional[str]=None
    overlay_path:Optional[str]=None
    source_asset_id:Optional[str]=None
    metadata:dict[str,Any]=field(default_factory=dict)

@dataclass
class ChangeSet:
    changeset_id:str
    project_id:str
    files:list[VirtualFile]=field(default_factory=list)
    state:str="DRAFT"
    real_repository_write:bool=False
    def to_dict(self): return asdict(self)
