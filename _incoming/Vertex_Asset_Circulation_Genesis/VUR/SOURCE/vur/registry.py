import json
from datetime import datetime, timezone
from pathlib import Path

class Registry:
    def __init__(self,path:Path): self.path=path
    def load(self): return json.loads(self.path.read_text(encoding="utf-8"))
    def save(self,doc):
        doc["updated_at"]=datetime.now(timezone.utc).isoformat()
        tmp=self.path.with_suffix(self.path.suffix+".next")
        tmp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        tmp.replace(self.path)
    def append_unique(self,collection,value,id_key):
        doc=self.load(); items=doc.setdefault(collection,[])
        for i,item in enumerate(items):
            if item.get(id_key)==value[id_key]:
                items[i]=value; self.save(doc); return
        items.append(value); self.save(doc)
