from .contracts import FleetUnit
class SupplyShip(FleetUnit):
 def __init__(self):super().__init__("Vertex Supply","SUPPLY",["package","model","runtime","toolchain","knowledge","cache","reinforcement"])
 def manifest(self,request):return {"state":"SUPPLIED","request":request}
class EscortShip(FleetUnit):
 def __init__(self):super().__init__("Vertex Escort","ESCORT",["sandbox","workspace_guard","process_watch","resource_limit","recovery","secret_isolation"])
 def guard(self,target):return {"state":"GUARDED","target":target}
class AegisShip(FleetUnit):
 def __init__(self):super().__init__("Vertex Aegis","AEGIS",["identity","trust_graph","policy","authority","invariant","anomaly","isolate","abort"])
