from pathlib import Path
from typing import Any, Dict
from ..util import read_json

class VURBridge:
    def __init__(self, vur_root: Path):
        self.root = vur_root

    def registry(self) -> Dict[str, Any]:
        return read_json(self.root / "REGISTRY" / "VUR_REGISTRY.json")

    def summary(self) -> Dict[str, int]:
        r = self.registry()
        keys = ["vcells","units","packs","templates","relations","sources","projects"]
        return {k: len(r.get(k, [])) for k in keys}
