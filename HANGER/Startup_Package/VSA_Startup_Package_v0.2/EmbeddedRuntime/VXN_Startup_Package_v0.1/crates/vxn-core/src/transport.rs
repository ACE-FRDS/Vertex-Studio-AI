use std::sync::{Arc,Mutex}; use crate::error::{VxnError,VxnResult};
#[derive(Debug,Clone,PartialEq,Eq)] pub struct InterfaceEnvelope{pub schema:String,pub payload:Vec<u8>,pub permissions:Vec<String>}
pub trait InterfaceTransport:Send+Sync{fn send(&self,e:InterfaceEnvelope)->VxnResult<()>;fn receive(&self)->VxnResult<Option<InterfaceEnvelope>>;}
#[derive(Clone,Default)] pub struct InProcessTransport{queue:Arc<Mutex<Vec<InterfaceEnvelope>>>}
impl InterfaceTransport for InProcessTransport{
 fn send(&self,e:InterfaceEnvelope)->VxnResult<()>{self.queue.lock().map_err(|_|VxnError::Transport("queue lock poisoned".into()))?.push(e);Ok(())}
 fn receive(&self)->VxnResult<Option<InterfaceEnvelope>>{let mut q=self.queue.lock().map_err(|_|VxnError::Transport("queue lock poisoned".into()))?;if q.is_empty(){Ok(None)}else{Ok(Some(q.remove(0)))}}
}
