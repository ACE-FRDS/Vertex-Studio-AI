from .contracts import Mission
class HyperAgent:
 """Human->World semantic ingress. Expands intent without silently shrinking it."""
 def compile(self,intent,world_context):
  m=Mission(intent=intent,context=world_context)
  m.tasks=[
   {"role":"Navigator","op":"context_reconstruction","header":{"scope":"world","authority":"READ"},"footer":{"evidence":True}},
   {"role":"Architect","op":"semantic_plan","header":{"scope":"mission","authority":"PLAN"},"footer":{"acceptance":"typed-plan"}},
   {"role":"Developer","op":"execute_vxn","header":{"scope":"virtual-workspace","authority":"EDIT_STAGE"},"footer":{"evidence":True}},
   {"role":"Reviewer","op":"verify","header":{"scope":"revision","authority":"VERIFY"},"footer":{"acceptance":"evidence"}},
  ]
  return m
