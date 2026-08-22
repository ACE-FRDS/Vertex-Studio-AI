
import re
def normalize(intent):
 goals=[x.strip() for x in re.split(r"[。\n;]+",intent) if x.strip()] or ["inspect world"]
 return {"intent":intent,"goals":goals,"constraints":["authority","scope","evidence","continuity"],"acceptance":["evidence-recorded","vsp-updated","no-unauthorized-mutation"]}
def decompose(c,reliable_units=2):
 out=[];chunk=max(1,reliable_units);roles=["architect","developer","reviewer","verifier"]
 for i in range(0,len(c["goals"]),chunk):
  g=c["goals"][i:i+chunk];role=roles[len(out)%len(roles)]
  h={"role":role,"current_position":"mission/decomposed","scope":["workspace","mission"],"authority":"bounded-human-delegation","available_evidence":["StartupSource","VCC","VSP","RepositoryEvidence"],"required_inputs":g,"forbidden_actions":["root-self-promotion","secret-exfiltration","out-of-scope-write","silent-truth-rewrite"]}
  f={"acceptance":c["acceptance"],"required_evidence":["result","changes","tests-or-reason"],"output_contract":["summary","evidence","unresolved","next"],"stop_conditions":["human-gate","authority-conflict","integrity-failure"],"relay_requirements":["preserve-mission-id","preserve-vha-id"],"vcc_update":"durable-decision-only","vsp_update":"always"}
  out.append({"title":" / ".join(g),"role":role,"header":h,"footer":f})
 return out
