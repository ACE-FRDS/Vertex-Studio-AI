from .bus import VXNNerveBus
from .systems import System,HyperAgent,VXNRuntime,Aegis
class World:
 def __init__(self):
  self.bus=VXNNerveBus();self.hyper=HyperAgent('HyperAgent',self.bus);self.vxn=VXNRuntime('VXNRuntime',self.bus);self.aegis=Aegis('Aegis',self.bus)
  for n in ['VSA','Radar','Frontier','Supply','Escort','Portable','Repository','Hub','VCC','VSP','Memory','Observatory','Simulator']:System(n,self.bus)
 def enter(self,intent):return self.hyper.ingress(intent)
