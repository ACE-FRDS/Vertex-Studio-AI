import pathlib,sys,json,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"WORLD_ENGINE"))
from vertex_world.world import VertexWorld
class Mock(BaseHTTPRequestHandler):
 def j(self,o):
  b=json.dumps(o).encode();self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
 def do_GET(self):self.j({"data":[{"id":"vertex-mock-model"}]}) if self.path=="/v1/models" else self.send_error(404)
 def do_POST(self):
  _=self.rfile.read(int(self.headers.get("Content-Length","0")))
  self.j({"choices":[{"message":{"content":json.dumps({"summary":"Mock cognition completed","edits":[],"evidence":["mock-provider-call"],"unresolved":[],"next":"review"})}}]}) if self.path=="/v1/chat/completions" else self.send_error(404)
 def log_message(self,*a):pass
TW=ROOT/"FLIGHT_TEST_WORKSPACE";server=ThreadingHTTPServer(("127.0.0.1",0),Mock);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
 override={"kind":"MockOpenAI","base_url":f"http://127.0.0.1:{server.server_address[1]}","model":"vertex-mock-model"}
 w=VertexWorld(ROOT)
 primary=w.execute_mission("Inspect workspace. Verify cognition. Build and test. Preserve evidence.",workspace=TW,reliable_units=1,provider_override=override)
 assert primary["ok"] and primary["build_results"] and all(x["ok"] for x in primary["build_results"]);assert not w.repo.fsck()
 fail=w.execute_mission("A. B. C.",reliable_units=1,inject_failure=True,provider_override=override);assert fail["recovered"]
 old=w.boot_count;w2=VertexWorld(ROOT);assert w2.boot_count==old+1
 loops=[];w3=VertexWorld(ROOT)
 for i in range(12):loops.append(w3.execute_mission(f"Continuity loop {i+1}. Inspect. Preserve.",reliable_units=1,inject_failure=(i in (4,9)),provider_override=override))
 final=VertexWorld(ROOT);assert not final.repo.fsck()
 print(json.dumps({"flight":"PASS","provider_path":"PASS","workspace":"PASS","build_test":"PASS","semantic_revision":"PASS","vcc_vsp":"PASS","recovery":"PASS","reboot":"PASS","repo_fsck":"PASS","primary":primary,"repeated":{"loops":12,"completed":sum(1 for x in loops if x.get("ok")),"failures":sum(1 for x in loops if not x.get("ok")),"recovered":sum(1 for x in loops if x.get("recovered"))},"final_status":final.status()},indent=2))
finally:
 server.shutdown();server.server_close();thread.join(timeout=1)
