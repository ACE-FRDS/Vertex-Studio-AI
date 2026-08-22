import os,platform,shutil,socket,urllib.request,json
from .contracts import Contact
class Radar:
 def scan(self):
  c=[Contact("os",platform.system(),health="READY",trust="LOCAL"),
     Contact("python",platform.python_version(),health="READY",trust="LOCAL")]
  for tool in ("git","cargo","rustc","node","npm","python"):
   p=shutil.which(tool)
   if p:c.append(Contact("toolchain",tool,health="READY",trust="LOCAL",metadata={"path":p}))
  for kind,url in (("LMStudio","http://127.0.0.1:1234/v1/models"),("Ollama","http://127.0.0.1:11434/api/tags")):
   try:
    with urllib.request.urlopen(url,timeout=.3) as r:d=json.loads(r.read().decode())
    c.append(Contact("provider",kind,health="ONLINE",trust="LOCAL",metadata=d))
   except Exception as e:c.append(Contact("provider",kind,health="OFFLINE",trust="LOCAL",metadata={"error":str(e)}))
  return c
