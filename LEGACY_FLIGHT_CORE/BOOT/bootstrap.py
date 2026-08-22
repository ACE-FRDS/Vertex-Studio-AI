from pathlib import Path
import json, hashlib, sys

ROOT = Path(__file__).resolve().parents[1]
startup = json.loads((ROOT/"CONTINUITY/StartupSource/manifest.json").read_text())
missing = [p for p in startup["load_order"] if not (ROOT/p).exists()]
if missing:
    print("BOOT BLOCKED: missing evidence:", *missing, sep="\n- ")
    sys.exit(2)
print("VERTEX WORLD BOOTSTRAP")
for rel in startup["load_order"]:
    data=(ROOT/rel).read_bytes()
    print(rel, hashlib.sha256(data).hexdigest()[:16])
print("REENTRY POLICY:", startup["policy"])
