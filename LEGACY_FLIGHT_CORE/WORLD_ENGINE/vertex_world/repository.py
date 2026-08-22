
from pathlib import Path
import json,hashlib,time
class SemanticRepository:
 def __init__(self,root):
  self.root=Path(root);(self.root/"objects").mkdir(parents=True,exist_ok=True);self.refs=self.root/"refs.json"
  if not self.refs.exists():self.refs.write_text(json.dumps({"HEAD":None,"history":[]},indent=2))
 def put(self,obj):
  raw=json.dumps(obj,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode();oid=hashlib.sha256(raw).hexdigest();p=self.root/"objects"/oid[:2]/oid[2:];p.parent.mkdir(parents=True,exist_ok=True)
  if not p.exists():p.write_bytes(raw)
  return oid
 def commit(self,mid,mut,evi,why):
  refs=json.loads(self.refs.read_text());obj={"kind":"SemanticRevision","mission_id":mid,"parent":refs["HEAD"],"mutation":mut,"evidence":evi,"rationale":why,"time":time.time()};oid=self.put(obj);refs["HEAD"]=oid;refs["history"].append(oid);self.refs.write_text(json.dumps(refs,indent=2));return oid
 def fsck(self):
  refs=json.loads(self.refs.read_text());bad=[]
  for oid in refs["history"]:
   p=self.root/"objects"/oid[:2]/oid[2:]
   if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=oid:bad.append(oid)
  return bad
