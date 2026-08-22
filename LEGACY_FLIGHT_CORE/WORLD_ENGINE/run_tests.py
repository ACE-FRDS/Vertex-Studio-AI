import sys,pathlib,tempfile,traceback
ROOT=pathlib.Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT))
from vertex_world.world import VertexWorld
def run(n,f):
 try:f();print("PASS",n);return True
 except Exception:print("FAIL",n);traceback.print_exc();return False
def life():
 with tempfile.TemporaryDirectory() as td:
  w=VertexWorld(pathlib.Path(td));r=w.execute_mission("Build. Verify. Preserve.",reliable_units=1);assert r["ok"] and not w.repo.fsck()
def recovery():
 with tempfile.TemporaryDirectory() as td:
  w=VertexWorld(pathlib.Path(td));r=w.execute_mission("A. B. C.",reliable_units=1,inject_failure=True);assert r["recovered"]
def reboot():
 with tempfile.TemporaryDirectory() as td:
  p=pathlib.Path(td);a=VertexWorld(p);a.execute_mission("A. B.");n=a.boot_count;b=VertexWorld(p);assert b.boot_count==n+1 and b.status()["db"]["missions"]==1
sys.exit(0 if all([run("life",life),run("recovery",recovery),run("reboot",reboot)]) else 1)
