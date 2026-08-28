use std::{fs::{self,OpenOptions},io::Write,path::{Path,PathBuf}};
use vsa_foundation::{VsaError,VsaResult};

#[derive(Debug,Clone,PartialEq,Eq)]
pub struct VccRecord {
    pub stream_owner:String,
    pub record_type:String,
    pub status:String,
    pub text:String,
}
pub struct VccFile { path:PathBuf }
impl VccFile {
    pub fn new(path:impl Into<PathBuf>)->Self{Self{path:path.into()}}
    pub fn append(&self,r:&VccRecord)->VsaResult<()>{
        let mut f=OpenOptions::new().create(true).append(true).open(&self.path).map_err(|e|VsaError::Io(e.to_string()))?;
        let line=format!("{}\t{}\t{}\t{}\n",clean(&r.stream_owner),clean(&r.record_type),clean(&r.status),clean(&r.text));
        f.write_all(line.as_bytes()).map_err(|e|VsaError::Io(e.to_string()))
    }
    pub fn read_all(&self)->VsaResult<Vec<VccRecord>>{
        if !self.path.exists(){return Ok(vec![])}
        let s=fs::read_to_string(&self.path).map_err(|e|VsaError::Io(e.to_string()))?;
        Ok(s.lines().filter_map(|l|{
            let p:Vec<_>=l.splitn(4,'\t').collect(); if p.len()!=4{return None}
            Some(VccRecord{stream_owner:p[0].into(),record_type:p[1].into(),status:p[2].into(),text:p[3].into()})
        }).collect())
    }
}
fn clean(s:&str)->String{s.replace('\t'," ").replace('\n'," ")}
#[derive(Debug,Clone,PartialEq,Eq,Default)]
pub struct VspState {
    pub repository:String,pub workspace:String,pub branch:String,pub mission:String,
    pub assigned_worker:String,pub assigned_model:String,pub build_status:String,pub test_status:String,
    pub risk:String,pub next_action:String,
}
pub fn startup_order()->[&'static str;5]{["StartupSource","VCC","VSP","Repository Evidence","Mission"]}
pub fn ensure_parent(path:&Path)->VsaResult<()>{
    if let Some(p)=path.parent(){fs::create_dir_all(p).map_err(|e|VsaError::Io(e.to_string()))?} Ok(())
}
