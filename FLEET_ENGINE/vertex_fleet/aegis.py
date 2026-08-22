class Aegis:
 def evaluate(self,mission,action):
  forbidden=("delete_original_lineage","disable_evidence","bypass_human_irreversible","escape_workspace")
  if action.get("kind") in forbidden:return {"decision":"ABORT","reason":"constitutional invariant"}
  if mission.authority!="HUMAN" and action.get("irreversible"):return {"decision":"HUMAN_GATE","reason":"authority"}
  return {"decision":"PASS","reason":"within authority"}
