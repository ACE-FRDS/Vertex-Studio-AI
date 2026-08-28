use std::{collections::HashMap,sync::Arc}; use crate::{error::{VxnError,VxnResult},ir::Value};
pub trait Capability:Send+Sync{fn id(&self)->&str;fn invoke(&self,args:&[Value])->VxnResult<Value>;}
#[derive(Default)] pub struct CapabilityRegistry{entries:HashMap<String,Arc<dyn Capability>>}
impl CapabilityRegistry{
 pub fn register(&mut self,c:Arc<dyn Capability>)->VxnResult<()>{let id=c.id().to_string();if self.entries.contains_key(&id){return Err(VxnError::Capability(format!("duplicate capability `{id}`")))}self.entries.insert(id,c);Ok(())}
 pub fn get(&self,id:&str)->VxnResult<Arc<dyn Capability>>{self.entries.get(id).cloned().ok_or_else(||VxnError::Capability(format!("capability `{id}` not installed")))}
 pub fn ids(&self)->Vec<String>{let mut v:Vec<_>=self.entries.keys().cloned().collect();v.sort();v}
}
pub struct AddCapability; impl Capability for AddCapability{fn id(&self)->&str{"math.add"}fn invoke(&self,args:&[Value])->VxnResult<Value>{match args{[Value::Int(a),Value::Int(b)]=>Ok(Value::Int(a+b)),_=>Err(VxnError::Capability("math.add expects two integers".into()))}}}
