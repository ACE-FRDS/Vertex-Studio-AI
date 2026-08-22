import json,re
from .provider import call
SYSTEM="""You are a Vertex cognition worker. Return JSON only:
{"summary":"...","edits":[{"path":"relative/path","content":"complete replacement"}],"evidence":["..."],"unresolved":[],"next":"review"}
Honor Header scope/authority/forbidden actions and Footer acceptance/evidence."""
def execute_task(provider,task,inventory,read_files):
 bounded=dict((k,v[:12000]) for k,v in sorted(read_files.items(), key=lambda x: len(x[1]))[:6])
 payload={"header":task["header"],"task":task["title"],"footer":task["footer"],"workspace_inventory":inventory[:120],"read_files":bounded}
 raw=call(provider["kind"],provider["base_url"],provider["model"],[{"role":"system","content":SYSTEM},{"role":"user","content":json.dumps(payload,ensure_ascii=False)}])
 m=re.search(r"\{.*\}",raw,re.S)
 if not m:raise ValueError("provider returned no JSON")
 out=json.loads(m.group(0));out.setdefault("edits",[]);out.setdefault("evidence",[]);out.setdefault("unresolved",[]);out.setdefault("next","review");return out
