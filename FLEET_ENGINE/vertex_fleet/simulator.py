import random
PROFILES=["reliable","permission_loop","premature_stop","hallucination","context_loss","overconfident","cautious"]
class Simulator:
 def run(self,n=1000,seed=7):
  r=random.Random(seed);stats={p:0 for p in PROFILES};recoveries=0
  for _ in range(n):
   p=r.choice(PROFILES);stats[p]+=1
   if p!="reliable":recoveries+=1
  return {"worlds":n,"profiles":stats,"recovery_opportunities":recoveries}
