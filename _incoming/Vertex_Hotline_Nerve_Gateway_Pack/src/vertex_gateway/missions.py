from pathlib import Path
from typing import Any, Dict
from .util import write_json_atomic, read_json

class MissionStore:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, mission_id: str) -> Path:
        safe = mission_id.replace("://","__").replace("/","_").replace(":","_")
        return self.root / (safe + ".json")

    def save(self, mission: Dict[str, Any]) -> None:
        write_json_atomic(self._path(mission["mission_id"]), mission)

    def get(self, mission_id: str) -> Dict[str, Any]:
        return read_json(self._path(mission_id))
