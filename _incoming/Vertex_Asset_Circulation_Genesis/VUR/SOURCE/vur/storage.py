import shutil
from pathlib import Path
from .integrity import sha256_file

class Storage:
    def __init__(self,root:Path):
        self.root=root
        self.vault=root/"VAULT"
        self.staging=root/"STAGING"
    def stage_file(self,source:Path,namespace:str)->Path:
        d=self.staging/namespace
        d.mkdir(parents=True,exist_ok=True)
        out=d/source.name
        shutil.copy2(source,out)
        return out
    def integrity_map(self,root:Path)->dict[str,str]:
        return {p.relative_to(root).as_posix():sha256_file(p) for p in root.rglob("*") if p.is_file()}
