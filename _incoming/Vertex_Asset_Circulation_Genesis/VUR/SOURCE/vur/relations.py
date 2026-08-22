import json
from pathlib import Path
from .domain import Relation

class RelationGraph:
    def __init__(self,contract_path:Path):
        doc=json.loads(contract_path.read_text(encoding="utf-8"))
        self.allowed=set(doc["relation_types"])
    def validate(self,relation:Relation):
        if relation.relation_type not in self.allowed:
            raise ValueError(f"unsupported relation: {relation.relation_type}")
        if not relation.source_id or not relation.target_id:
            raise ValueError("source_id and target_id required")
