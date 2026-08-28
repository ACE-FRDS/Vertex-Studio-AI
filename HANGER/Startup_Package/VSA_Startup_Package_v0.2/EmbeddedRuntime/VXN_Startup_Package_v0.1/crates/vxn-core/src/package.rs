use std::{collections::HashMap,fs,path::Path};use crate::error::{VxnError,VxnResult};
#[derive(Debug,Clone,PartialEq,Eq)]pub struct PackageManifest{pub name:String,pub version:String,pub entry:String,pub metadata:HashMap<String,String>}
impl PackageManifest{
 pub fn parse(source:&str)->VxnResult<Self>{let mut m=HashMap::new();for raw in source.lines(){let l=raw.trim();if l.is_empty()||l.starts_with('#'){continue}let(k,v)=l.split_once('=').ok_or_else(||VxnError::Package(format!("invalid manifest line `{l}`")))?;m.insert(k.trim().into(),v.trim().trim_matches('"').into());}let name=m.remove("name").ok_or_else(||VxnError::Package("manifest missing name".into()))?;let version=m.remove("version").ok_or_else(||VxnError::Package("manifest missing version".into()))?;let entry=m.remove("entry").ok_or_else(||VxnError::Package("manifest missing entry".into()))?;Ok(Self{name,version,entry,metadata:m})}
 pub fn load(path:&Path)->VxnResult<Self>{Self::parse(&fs::read_to_string(path).map_err(|e|VxnError::Package(e.to_string()))?)}
}
