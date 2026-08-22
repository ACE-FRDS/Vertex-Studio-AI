use crate::{DurableImpact,ImpactKey};
use async_trait::async_trait;
use std::{collections::HashMap,sync::Arc};
use tokio::sync::RwLock;

#[async_trait]
pub trait DurableImpactRepository:Send+Sync{
 async fn get(&self,key:&ImpactKey)->Result<Option<DurableImpact>,String>;
 async fn put(&self,value:DurableImpact)->Result<(),String>;
 async fn seeds(&self,limit:usize)->Result<Vec<DurableImpact>,String>;
}
#[derive(Default)]
pub struct InMemoryDurableImpactRepository{values:RwLock<HashMap<ImpactKey,DurableImpact>>}
impl InMemoryDurableImpactRepository{pub fn shared()->Arc<Self>{Arc::new(Self::default())}}
#[async_trait]
impl DurableImpactRepository for InMemoryDurableImpactRepository{
 async fn get(&self,key:&ImpactKey)->Result<Option<DurableImpact>,String>{Ok(self.values.read().await.get(key).cloned())}
 async fn put(&self,v:DurableImpact)->Result<(),String>{self.values.write().await.insert(v.key.clone(),v);Ok(())}
 async fn seeds(&self,limit:usize)->Result<Vec<DurableImpact>,String>{Ok(self.values.read().await.values().take(limit).cloned().collect())}
}
