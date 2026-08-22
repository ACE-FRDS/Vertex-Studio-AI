
from pathlib import Path
import sqlite3,json,time,uuid,hashlib
SCHEMA="""
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS world_state(key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS missions(id TEXT PRIMARY KEY,human_intent TEXT NOT NULL,state TEXT NOT NULL,created_at REAL NOT NULL,updated_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY,mission_id TEXT NOT NULL,title TEXT NOT NULL,role TEXT NOT NULL,state TEXT NOT NULL,header TEXT NOT NULL,footer TEXT NOT NULL,result TEXT,evidence TEXT);
CREATE TABLE IF NOT EXISTS vha(id TEXT PRIMARY KEY,name TEXT,role TEXT,provider TEXT,model TEXT,authority TEXT,updated_at REAL);
CREATE TABLE IF NOT EXISTS checkpoints(id TEXT PRIMARY KEY,mission_id TEXT,snapshot TEXT,created_at REAL);
CREATE TABLE IF NOT EXISTS semantic_revisions(id TEXT PRIMARY KEY,mission_id TEXT,parent_id TEXT,mutation TEXT,evidence TEXT,created_at REAL);
CREATE TABLE IF NOT EXISTS vcc(id TEXT PRIMARY KEY,kind TEXT,body TEXT,evidence TEXT,created_at REAL);
CREATE TABLE IF NOT EXISTS vsp(id INTEGER PRIMARY KEY AUTOINCREMENT,mission_id TEXT,state TEXT,build TEXT,test TEXT,risk TEXT,next_action TEXT,created_at REAL);
CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT,payload TEXT,created_at REAL);
"""
class WorldDB:
 def __init__(self,path):
  self.path=Path(path);self.path.parent.mkdir(parents=True,exist_ok=True);self.con=sqlite3.connect(self.path);self.con.row_factory=sqlite3.Row;self.con.executescript(SCHEMA);self.con.commit()
 def event(self,k,p): self.con.execute("INSERT INTO events(kind,payload,created_at) VALUES(?,?,?)",(k,json.dumps(p,ensure_ascii=False),time.time()));self.con.commit()
 def set_state(self,k,v): self.con.execute("INSERT INTO world_state VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at",(k,json.dumps(v,ensure_ascii=False),time.time()));self.con.commit()
 def get_state(self,k,d=None):
  r=self.con.execute("SELECT value FROM world_state WHERE key=?",(k,)).fetchone();return json.loads(r["value"]) if r else d
 def mission(self,intent):
  mid=str(uuid.uuid4());n=time.time();self.con.execute("INSERT INTO missions VALUES(?,?,?,?,?)",(mid,intent,"CREATED",n,n));self.con.commit();self.event("MISSION_CREATED",{"mission_id":mid});return mid
 def mission_state(self,mid,s): self.con.execute("UPDATE missions SET state=?,updated_at=? WHERE id=?",(s,time.time(),mid));self.con.commit();self.event("MISSION_STATE",{"mission_id":mid,"state":s})
 def task(self,mid,title,role,h,f):
  tid=str(uuid.uuid4());self.con.execute("INSERT INTO tasks(id,mission_id,title,role,state,header,footer) VALUES(?,?,?,?,?,?,?)",(tid,mid,title,role,"PENDING",json.dumps(h),json.dumps(f)));self.con.commit();return tid
 def task_state(self,tid,s,result=None,evidence=None): self.con.execute("UPDATE tasks SET state=?,result=COALESCE(?,result),evidence=COALESCE(?,evidence) WHERE id=?",(s,result,json.dumps(evidence) if evidence is not None else None,tid));self.con.commit()
 def vha(self,vid,name,role,provider,model,authority): self.con.execute("INSERT INTO vha VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET provider=excluded.provider,model=excluded.model,updated_at=excluded.updated_at",(vid,name,role,provider,model,authority,time.time()));self.con.commit()
 def checkpoint(self,mid,snap):
  cid=str(uuid.uuid4());self.con.execute("INSERT INTO checkpoints VALUES(?,?,?,?)",(cid,mid,json.dumps(snap),time.time()));self.con.commit();self.event("CHECKPOINT",{"mission_id":mid,"checkpoint_id":cid});return cid
 def latest_checkpoint(self,mid):
  r=self.con.execute("SELECT snapshot FROM checkpoints WHERE mission_id=? ORDER BY created_at DESC LIMIT 1",(mid,)).fetchone();return json.loads(r["snapshot"]) if r else None
 def revision(self,mid,parent,mut,evi):
  rid=hashlib.sha256((mid+json.dumps(mut,sort_keys=True)+str(time.time_ns())).encode()).hexdigest();self.con.execute("INSERT INTO semantic_revisions VALUES(?,?,?,?,?,?)",(rid,mid,parent,json.dumps(mut),json.dumps(evi),time.time()));self.con.commit();self.event("SEMANTIC_REVISION",{"mission_id":mid,"revision":rid});return rid
 def vcc(self,k,b,e): self.con.execute("INSERT INTO vcc VALUES(?,?,?,?,?)",(str(uuid.uuid4()),k,b,json.dumps(e),time.time()));self.con.commit()
 def vsp(self,mid,s,b,t,r,n): self.con.execute("INSERT INTO vsp(mission_id,state,build,test,risk,next_action,created_at) VALUES(?,?,?,?,?,?,?)",(mid,s,b,t,r,n,time.time()));self.con.commit()
 def summary(self):
  return {t:self.con.execute(f"SELECT COUNT(*) c FROM {t}").fetchone()["c"] for t in ["missions","tasks","vha","checkpoints","semantic_revisions","vcc","vsp","events"]}
