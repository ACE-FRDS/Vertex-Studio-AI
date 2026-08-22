from dataclasses import dataclass,field
from typing import Any
@dataclass
class Contact:
    kind:str; name:str; health:str="UNKNOWN"; trust:str="UNKNOWN"; capabilities:list[str]=field(default_factory=list); metadata:dict[str,Any]=field(default_factory=dict)
@dataclass
class Mission:
    intent:str; authority:str="HUMAN"; risk:str="NORMAL"; context:dict[str,Any]=field(default_factory=dict); tasks:list[dict]=field(default_factory=list)
@dataclass
class FleetUnit:
    name:str; role:str; capabilities:list[str]; authority:list[str]=field(default_factory=list); state:str="READY"
