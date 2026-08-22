from pathlib import Path
import sys, json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"VUR"/"SOURCE"))
from vur.service import VURService
from vur.vve import VVEChange

def test_vur_open():
    v=VURService.open(ROOT/"VUR")
    assert v.registry.load()["version"]=="1.0.0"

def test_vve_changeset_never_direct_writes(tmp_path):
    v=VURService.open(ROOT/"VUR")
    v.vve.outbox=tmp_path
    out=v.vve.create_changeset("test","project://vertex/test",[VVEChange(path="src/new.rs",operation="CREATE")])
    doc=json.loads(out.read_text(encoding="utf-8"))
    assert doc["real_repository_write"] is False
