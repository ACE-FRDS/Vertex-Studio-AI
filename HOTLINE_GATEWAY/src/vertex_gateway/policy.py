from typing import Any, Dict
from .errors import CapabilityDenied

class CapabilityPolicy:
    def __init__(self, document: Dict[str, Any]):
        self.document = document
        self.map = document.get("capabilities", {})

    def require(self, capability: str) -> Dict[str, Any]:
        item = self.map.get(capability)
        if not item or item.get("enabled") is not True:
            raise CapabilityDenied("capability denied: %s" % capability)
        return item

    def list_enabled(self):
        return sorted([k for k,v in self.map.items() if v.get("enabled") is True])
