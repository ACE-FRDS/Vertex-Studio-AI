import json
from datetime import datetime, timezone
from pathlib import Path

class LineageLedger:
    def __init__(self,path:Path): self.path=path
    def append(self,event):
        doc=json.loads(self.path.read_text(encoding="utf-8"))
        event=dict(event)
        event.setdefault("occurred_at",datetime.now(timezone.utc).isoformat())
        doc.setdefault("entries",[]).append(event)
        tmp=self.path.with_suffix(".next")
        tmp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        tmp.replace(self.path)
