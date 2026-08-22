from pathlib import Path
from typing import Any, Dict
from .util import read_json

class GatewayConfig:
    def __init__(self, root: Path):
        self.root = root
        self.gateway = read_json(root / "CONFIG" / "gateway.json")
        self.capabilities = read_json(root / "CONFIG" / "capabilities.json")
        self.command_profiles = read_json(root / "CONFIG" / "command_profiles.json")

    @property
    def bind_host(self) -> str:
        return self.gateway["bind_host"]

    @property
    def bind_port(self) -> int:
        return int(self.gateway["bind_port"])
