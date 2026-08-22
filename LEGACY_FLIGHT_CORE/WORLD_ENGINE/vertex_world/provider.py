import json, urllib.request
def _request(url,body=None,timeout=20):
 data=None if body is None else json.dumps(body).encode()
 req=urllib.request.Request(url,data=data,headers={"Content-Type":"application/json","User-Agent":"VertexWorld/1"})
 with urllib.request.urlopen(req,timeout=timeout) as r:return json.loads(r.read().decode())
def discover():
 out=[]
 for kind,url,base in [("LMStudio","http://127.0.0.1:1234/v1/models","http://127.0.0.1:1234"),("Ollama","http://127.0.0.1:11434/api/tags","http://127.0.0.1:11434")]:
  try:
   d=_request(url,timeout=1)
   models=[x.get("id","") for x in d.get("data",[])] if kind=="LMStudio" else [x.get("name","") for x in d.get("models",[])]
   out.append({"kind":kind,"base_url":base,"models":[m for m in models if m],"healthy":True})
  except Exception as e:out.append({"kind":kind,"base_url":base,"models":[],"healthy":False,"error":str(e)})
 return out
def call(kind,base_url,model,messages,timeout=120):
 if kind in ("LMStudio","OpenAICompat","MockOpenAI"):
  d=_request(base_url.rstrip("/")+"/v1/chat/completions",{"model":model,"messages":messages,"temperature":0.1},timeout);return d["choices"][0]["message"]["content"]
 if kind=="Ollama":
  prompt="\n\n".join(f"{m['role'].upper()}:\n{m['content']}" for m in messages)
  return _request(base_url.rstrip("/")+"/api/generate",{"model":model,"prompt":prompt,"stream":False},timeout)["response"]
 raise ValueError(kind)
