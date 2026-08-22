from dataclasses import dataclass,field,asdict
from typing import Any
import uuid,time,hashlib,json
@dataclass
class VXNEnvelope:
 source:str; target:str; semantic_type:str; payload:dict[str,Any]; authority:str='HUMAN_DELEGATED'; scope:list[str]=field(default_factory=lambda:['world']); evidence:list[str]=field(default_factory=list); id:str=field(default_factory=lambda:str(uuid.uuid4())); created_ns:int=field(default_factory=time.time_ns)
 def canonical_bytes(self):
  d=asdict(self);return json.dumps(d,sort_keys=True,separators=(',',':')).encode()
 def digest(self):return hashlib.sha256(self.canonical_bytes()).hexdigest()
 def validate(self):
  if not self.source or not self.target:return False,'route'
  if not self.semantic_type:return False,'semantic_type'
  if not self.scope:return False,'scope'
  return True,'ok'
