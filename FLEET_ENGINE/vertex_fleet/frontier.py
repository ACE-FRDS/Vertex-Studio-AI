class Frontier:
 def assess(self,contacts):
  return [{"name":c.name,"kind":c.kind,"action":"USE" if c.health in ("READY","ONLINE") else "DIAGNOSE"} for c in contacts]
