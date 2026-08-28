use std::collections::HashMap; use crate::{error::{VxnError,VxnResult},security::{ExecutionPolicy,Permission}};
#[derive(Debug,Clone,PartialEq,Eq)] pub struct ReinforcementPackage{pub id:String,pub version:String,pub checksum:String,pub capabilities:Vec<String>}
#[derive(Debug,Clone,Copy,PartialEq,Eq)] pub enum ReinforcementState{Staged,Active}
#[derive(Default)] pub struct ReinforcementManager{packages:HashMap<String,(ReinforcementPackage,ReinforcementState)>}
impl ReinforcementManager{
 pub fn stage(&mut self,p:ReinforcementPackage)->VxnResult<()>{if p.id.trim().is_empty()||p.version.trim().is_empty(){return Err(VxnError::Package("reinforcement id/version required".into()))}self.packages.insert(p.id.clone(),(p,ReinforcementState::Staged));Ok(())}
 pub fn activate(&mut self,id:&str,policy:&ExecutionPolicy)->VxnResult<()>{policy.require(Permission::ActivateReinforcement)?;let(_,s)=self.packages.get_mut(id).ok_or_else(||VxnError::Package(format!("reinforcement `{id}` not staged")))?;*s=ReinforcementState::Active;Ok(())}
 pub fn state(&self,id:&str)->Option<ReinforcementState>{self.packages.get(id).map(|(_,s)|*s)}
}
