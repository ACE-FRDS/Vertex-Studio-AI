import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from vertex_nerve.world import World
w=World();r=w.enter('Build Vertex World at full intended scale')
assert r['accepted'] and r['system']=='Observatory'
assert len(w.bus.trace)==4
assert [x['type'] for x in w.bus.trace]==['Mission.Compiled','Authority.Verify','Authority.Passed','Execution.Trace']
print('PASS VXN NERVOUS SYSTEM')
print('TRACE',len(w.bus.trace),dict(w.bus.stats))
