from pathlib import Path
import shutil,hashlib,difflib
class VirtualWorkspace:
 def __init__(self,source,work_root):self.source=Path(source).resolve();self.work_root=Path(work_root).resolve();self.stage=self.work_root/"stage"
 def mount(self):
  if self.stage.exists():shutil.rmtree(self.stage)
  if self.source.exists():shutil.copytree(self.source,self.stage,ignore=shutil.ignore_patterns(".git","target","node_modules",".venv","dist","STATE"))
  else:self.stage.mkdir(parents=True)
  return self.stage
 def inventory(self,limit=1000):
  out=[]
  for p in self.stage.rglob("*"):
   if p.is_file():
    try:out.append({"path":str(p.relative_to(self.stage)).replace("\\","/"),"bytes":p.stat().st_size})
    except OSError:pass
    if len(out)>=limit:break
  return out
 def read_text(self,rel,max_bytes=1000000):
  p=(self.stage/rel).resolve()
  if self.stage not in p.parents:raise ValueError("path escape")
  b=p.read_bytes()
  if len(b)>max_bytes:raise ValueError("too large")
  return b.decode("utf-8")
 def write_text(self,rel,text):
  p=(self.stage/rel).resolve()
  if self.stage not in p.parents:raise ValueError("path escape")
  p.parent.mkdir(parents=True,exist_ok=True);before=p.read_text(encoding="utf-8") if p.exists() else "";p.write_text(text,encoding="utf-8");return before,text
 def diff_text(self,rel,before,after):return "".join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile=f"a/{rel}",tofile=f"b/{rel}"))
 def materialize(self,rel):
  src=(self.stage/rel).resolve();dst=(self.source/rel).resolve()
  if self.stage not in src.parents or self.source not in dst.parents:raise ValueError("path escape")
  dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst);return dst
 def digest(self):
  h=hashlib.sha256()
  for p in sorted(self.stage.rglob("*")):
   if p.is_file():
    h.update(str(p.relative_to(self.stage)).encode())
    try:h.update(p.read_bytes())
    except OSError:pass
  return h.hexdigest()
