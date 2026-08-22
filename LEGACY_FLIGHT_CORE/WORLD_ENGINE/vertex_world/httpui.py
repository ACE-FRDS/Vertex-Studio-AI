
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import json
from .world import VertexWorld
HTML="""<!doctype html><meta charset=utf-8><title>Vertex World</title><style>body{font-family:system-ui;background:#111;color:#eee;margin:2rem}button,textarea{font:inherit;padding:.6rem;margin:.3rem;background:#222;color:#eee;border:1px solid #555}pre{background:#181818;padding:1rem}.grid{display:grid;grid-template-columns:1fr 1fr;gap:1rem}.card{border:1px solid #444;padding:1rem;border-radius:12px}</style><h1>VERTEX WORLD — Mothership Projection</h1><div class=grid><div class=card><h2>Status</h2><button onclick=s1()>Refresh</button><pre id=s></pre></div><div class=card><h2>Mission</h2><textarea id=i rows=6 cols=60>Inspect continuity; validate authority; record evidence.</textarea><br><button onclick=m(false)>Execute</button><button onclick=m(true)>Inject Failure</button><pre id=o></pre></div></div><script>async function s1(){s.textContent=JSON.stringify(await(await fetch('/api/status')).json(),null,2)}async function m(f){let r=await fetch('/api/mission',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({intent:i.value,inject_failure:f})});o.textContent=JSON.stringify(await r.json(),null,2);s1()}s1()</script>"""
class H(BaseHTTPRequestHandler):
 world=None
 def j(self,x):b=json.dumps(x).encode();self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
 def do_GET(self):
  if self.path=="/":b=HTML.encode();self.send_response(200);self.send_header("Content-Type","text/html");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
  elif self.path=="/api/status":self.j(self.world.status())
  elif self.path=="/api/providers":self.j(self.world.discover_providers())
  else:self.send_error(404)
 def do_POST(self):
  if self.path!="/api/mission":return self.send_error(404)
  d=json.loads(self.rfile.read(int(self.headers.get("Content-Length","0"))) or b"{}");self.j(self.world.execute_mission(d.get("intent",""),inject_failure=bool(d.get("inject_failure"))))
 def log_message(self,*a):pass
def serve(root,port=8765):H.world=VertexWorld(Path(root));H.world.discover_providers();print(f"VSA Mothership Projection: http://127.0.0.1:{port}");ThreadingHTTPServer(("127.0.0.1",port),H).serve_forever()
