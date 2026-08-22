import pathlib,sys,json
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"FLEET_ENGINE"))
from vertex_fleet.world import VertexWorld
constitution=json.loads((ROOT/"CANON/CONSTITUTION.json").read_text())
manifest=json.loads((ROOT/"CANON/FLEET_MANIFEST.json").read_text())
w=VertexWorld();r=w.boot("Build the world without shrinking intent")
assert r["gate"]["decision"]=="PASS"
assert r["execution"]["ok"]
assert r["portable"]["state"]=="DEPLOYED" and r["return"]["state"]=="RETURNED"
assert r["supply"]["state"]=="SUPPLIED" and r["escort"]["state"]=="GUARDED"
required={"hyper_agent","vxn_runtime","radar","frontier","simulator","portable_bay"}
assert required.issubset(set(manifest["mothership"]["systems"]))
assert {"supply_ship","escort_ship","aegis_ship","portable"}.issubset(manifest["fleet_units"])
s=w.sim.run(10000);assert s["worlds"]==10000
print("PASS FLEET GENESIS")
print(json.dumps({"contacts":len(r["mission"]["context"]["contacts"]),"trace":len(r["execution"]["trace"]),"simulation_worlds":s["worlds"]},indent=2))
