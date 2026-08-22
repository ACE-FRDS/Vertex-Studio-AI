from .radar import Radar
from .frontier import Frontier
from .hyper_agent import HyperAgent
from .vxn_runtime import VXNRuntime
from .aegis import Aegis
from .portable import PortableBay
from .fleet import SupplyShip,EscortShip,AegisShip
from .simulator import Simulator
class VertexWorld:
 def __init__(self):
  self.radar=Radar();self.frontier=Frontier();self.hyper=HyperAgent();self.vxn=VXNRuntime();self.aegis=Aegis()
  self.portable=PortableBay();self.supply=SupplyShip();self.escort=EscortShip();self.aegis_ship=AegisShip();self.sim=Simulator()
 def boot(self,intent="Enter Vertex World"):
  contacts=self.radar.scan();assessment=self.frontier.assess(contacts)
  mission=self.hyper.compile(intent,{"contacts":[c.__dict__ for c in contacts],"frontier":assessment})
  gate=self.aegis.evaluate(mission,{"kind":"execute_semantic_mission"})
  ir=self.vxn.canonicalize(mission);execution=self.vxn.execute(ir)
  portable=self.portable.launch_package(ir["mission_id"],["runtime","mission","vcc_subset","vsp_subset","knowledge_subset"])
  returned=self.portable.return_merge(portable,execution["trace"])
  return {"gate":gate,"mission":mission.__dict__,"ir":ir,"execution":execution,"portable":portable,"return":returned,
          "supply":self.supply.manifest(["runtime","knowledge"]),"escort":self.escort.guard(ir["mission_id"])}
