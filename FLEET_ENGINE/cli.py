import sys,json,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from vertex_fleet.world import VertexWorld
w=VertexWorld()
cmd=sys.argv[1] if len(sys.argv)>1 else "boot"
if cmd=="boot":print(json.dumps(w.boot(" ".join(sys.argv[2:]) or "Enter Vertex World"),indent=2,ensure_ascii=False))
elif cmd=="radar":print(json.dumps([x.__dict__ for x in w.radar.scan()],indent=2))
elif cmd=="simulate":print(json.dumps(w.sim.run(int(sys.argv[2]) if len(sys.argv)>2 else 10000),indent=2))
else:raise SystemExit("boot|radar|simulate")
