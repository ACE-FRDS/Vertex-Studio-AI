use std::collections::HashSet;
use crate::error::{VxnError,VxnResult};
#[derive(Debug,Clone,Copy,PartialEq,Eq,Hash)] pub enum Permission{ReadState,WriteState,ExecuteCapability,ActivateReinforcement}
#[derive(Debug,Clone)] pub struct ExecutionPolicy{allowed:HashSet<Permission>}
impl ExecutionPolicy{
    pub fn local_safe_default()->Self{Self{allowed:[Permission::ReadState,Permission::WriteState].into_iter().collect()}}
    pub fn permissive_for_tests()->Self{Self{allowed:[Permission::ReadState,Permission::WriteState,Permission::ExecuteCapability,Permission::ActivateReinforcement].into_iter().collect()}}
    pub fn require(&self,p:Permission)->VxnResult<()> {if self.allowed.contains(&p){Ok(())}else{Err(VxnError::Security(format!("permission denied: {p:?}")))}}
}
