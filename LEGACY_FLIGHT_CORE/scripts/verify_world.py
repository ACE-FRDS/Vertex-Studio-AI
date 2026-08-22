from pathlib import Path
import json, sys
root=Path(__file__).resolve().parents[1]
required=[
"README.md","WORLD/schema/world.vxn.json","CONTINUITY/StartupSource/manifest.json",
"CONTINUITY/VCC/index.json","CONTINUITY/VSP/current.json",
"VSA/mothership/projection_contract.json","REPOSITORY/convergence/strategy.json"
]
missing=[x for x in required if not (root/x).exists()]
if missing:
    print("FAIL",missing);sys.exit(1)
world=json.loads((root/"WORLD/schema/world.vxn.json").read_text())
assert "machine_cannot_self_promote_root" in world["invariants"]
vsa=json.loads((root/"VSA/mothership/projection_contract.json").read_text())
assert vsa["canonical_truth_owner"] is False
print("VERTEX WORLD STRUCTURAL GATE PASS")
