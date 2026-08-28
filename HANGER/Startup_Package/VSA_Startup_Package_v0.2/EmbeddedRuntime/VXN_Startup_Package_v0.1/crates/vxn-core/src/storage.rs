use std::{collections::HashMap,fs,path::PathBuf,process::Command,sync::{Arc,Mutex}};
use crate::error::{VxnError,VxnResult};
pub trait KeyValueStore:Send+Sync{fn get(&self,key:&str)->VxnResult<Option<String>>;fn set(&self,key:&str,value:&str)->VxnResult<()>;}
#[derive(Clone,Default)] pub struct MemoryStore{inner:Arc<Mutex<HashMap<String,String>>>}
impl KeyValueStore for MemoryStore{
 fn get(&self,key:&str)->VxnResult<Option<String>>{Ok(self.inner.lock().map_err(|_|VxnError::Storage("lock poisoned".into()))?.get(key).cloned())}
 fn set(&self,key:&str,value:&str)->VxnResult<()>{self.inner.lock().map_err(|_|VxnError::Storage("lock poisoned".into()))?.insert(key.into(),value.into());Ok(())}
}
pub struct FileStore{root:PathBuf}
impl FileStore{pub fn new(root:impl Into<PathBuf>)->VxnResult<Self>{let root=root.into();fs::create_dir_all(&root).map_err(|e|VxnError::Storage(e.to_string()))?;Ok(Self{root})} fn path(&self,key:&str)->VxnResult<PathBuf>{if key.is_empty()||key.contains('/')||key.contains('\\')||key.contains(".."){Err(VxnError::Storage("unsafe key".into()))}else{Ok(self.root.join(key))}}}
impl KeyValueStore for FileStore{
 fn get(&self,key:&str)->VxnResult<Option<String>>{let p=self.path(key)?;if !p.exists(){return Ok(None)};fs::read_to_string(p).map(Some).map_err(|e|VxnError::Storage(e.to_string()))}
 fn set(&self,key:&str,value:&str)->VxnResult<()>{fs::write(self.path(key)?,value).map_err(|e|VxnError::Storage(e.to_string()))}
}
pub struct SqliteCliStore{db:PathBuf}
impl SqliteCliStore{
 pub fn new(path:impl Into<PathBuf>)->VxnResult<Self>{let s=Self{db:path.into()};s.exec("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY,v TEXT NOT NULL);")?;Ok(s)}
 fn q(v:&str)->String{format!("'{}'",v.replace('\'',"''"))}
 fn exec(&self,sql:&str)->VxnResult<String>{let o=Command::new("sqlite3").arg(&self.db).arg(sql).output().map_err(|e|VxnError::Storage(format!("sqlite3 unavailable: {e}")))?;if !o.status.success(){return Err(VxnError::Storage(String::from_utf8_lossy(&o.stderr).into_owned()))}Ok(String::from_utf8_lossy(&o.stdout).trim().into())}
}
impl KeyValueStore for SqliteCliStore{
 fn get(&self,key:&str)->VxnResult<Option<String>>{let v=self.exec(&format!("SELECT v FROM kv WHERE k={} LIMIT 1;",Self::q(key)))?;Ok((!v.is_empty()).then_some(v))}
 fn set(&self,key:&str,value:&str)->VxnResult<()>{self.exec(&format!("INSERT INTO kv(k,v) VALUES({},{}) ON CONFLICT(k) DO UPDATE SET v=excluded.v;",Self::q(key),Self::q(value))).map(|_|())}
}
