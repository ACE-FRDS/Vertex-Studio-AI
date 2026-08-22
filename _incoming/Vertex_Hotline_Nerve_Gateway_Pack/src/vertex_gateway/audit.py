import json, threading, time, uuid
from pathlib import Path
from typing import Any, Dict

class AuditLog:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def append(self, event: Dict[str, Any]) -> Dict[str, Any]:
        item = dict(event)
        item.setdefault("audit_id", str(uuid.uuid4()))
        item.setdefault("ts", time.time())
        line = json.dumps(item, ensure_ascii=False, separators=(",", ":"))
        with self.lock:
            with self.path.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        return item
