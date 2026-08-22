from collections import defaultdict,deque
from .envelope import VXNEnvelope
class VXNNerveBus:
 def __init__(self):self.handlers={};self.trace=[];self.reflex=deque();self.stats=defaultdict(int)
 def register(self,name,handler):self.handlers[name]=handler
 def send(self,e:VXNEnvelope):
  ok,why=e.validate();
  if not ok:raise ValueError(why)
  self.trace.append({'id':e.id,'source':e.source,'target':e.target,'type':e.semantic_type,'digest':e.digest()});self.stats[e.semantic_type]+=1
  if e.target not in self.handlers:raise KeyError(f'unregistered target:{e.target}')
  return self.handlers[e.target](e)
 def emit_reflex(self,kind,payload):self.reflex.append((kind,payload))
