import json
from pathlib import Path
from .errors import PolicyDenied

class PolicyEngine:
    def __init__(self,path:Path):
        doc=json.loads(path.read_text(encoding="utf-8"))
        self.zones={z["id"]:z for z in doc["zones"]}
    def zone(self,zone_id:str):
        if zone_id not in self.zones: raise PolicyDenied(f"unknown zone: {zone_id}")
        return self.zones[zone_id]
    def can_external_ai_read(self,zone_id:str)->bool:
        return self.zone(zone_id).get("external_ai") is True
