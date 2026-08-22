use crate::*;
use chrono::Utc;
use std::{collections::HashMap,sync::Arc};
use tokio::sync::RwLock;

#[derive(Debug,Clone,Copy)]
pub struct DynamicIndexConfig{
 pub context_weight:f32,pub activation_weight:f32,pub relation_weight:f32,
 pub durable_weight:f32,pub feedback_rate:f32,pub candidate_floor:f32
}
impl Default for DynamicIndexConfig{fn default()->Self{Self{context_weight:.30,activation_weight:.18,relation_weight:.18,durable_weight:.34,feedback_rate:.16,candidate_floor:.08}}}

pub struct DynamicImpactIndex{
 durable:Arc<dyn DurableImpactRepository>,
 active:RwLock<HashMap<ImpactKey,DynamicImpact>>,
 cfg:DynamicIndexConfig,
}
impl DynamicImpactIndex{
 pub fn new(durable:Arc<dyn DurableImpactRepository>,cfg:DynamicIndexConfig)->Self{Self{durable,active:RwLock::new(HashMap::new()),cfg}}
 pub async fn hydrate(&self,limit:usize)->Result<usize,String>{
   let seeds=self.durable.seeds(limit).await?; let n=seeds.len(); let mut a=self.active.write().await;
   for d in seeds{a.entry(d.key.clone()).or_insert_with(||DynamicImpact::seeded(&d));} Ok(n)
 }
 pub async fn register(&self,d:DurableImpact)->Result<(),String>{
   let dynv=DynamicImpact::seeded(&d); self.durable.put(d).await?; self.active.write().await.insert(dynv.key.clone(),dynv); Ok(())
 }
 /// Front-door operation: external input changes the index before factual retrieval.
 pub async fn ingest(&self,stimulus:&InputStimulus)->Vec<ImpactCandidate>{
   let now=Utc::now(); let tokens=tokenize(&stimulus.text); let contexts=stimulus.context_keys.iter().flat_map(|x|tokenize(x)).collect::<Vec<_>>();
   let mut active=self.active.write().await; let mut out=Vec::new();
   for v in active.values_mut(){
     decay(v,now);
     // v0.2 deliberately has no truth-content dependency. Context affinity is supplied/learned externally.
     // Activation is therefore a bounded global pulse until VMB relation metadata is attached.
     let lexical_signal=((tokens.len()+contexts.len()) as f32/32.0).min(1.0)*stimulus.strength.clamp(0.,1.);
     v.context_impact=(v.context_impact*.65+lexical_signal*.35).clamp(0.,1.);
     v.activation_heat=(v.activation_heat*.82+stimulus.strength*.18).clamp(0.,1.);
     v.current_impact=effective(v,self.cfg);
     v.updated_at=now;
     if v.current_impact>=self.cfg.candidate_floor{out.push(ImpactCandidate{key:v.key.clone(),effective_impact:v.current_impact,confidence:v.confidence});}
   }
   out.sort_by(|a,b|b.effective_impact.total_cmp(&a.effective_impact)); out
 }
 pub async fn reinforce_relation(&self,key:&ImpactKey,strength:f32){
   if let Some(v)=self.active.write().await.get_mut(key){v.relation_impact=(v.relation_impact*.7+strength.clamp(0.,1.)*.3).clamp(0.,1.);v.current_impact=effective(v,self.cfg);}
 }
 pub async fn feedback(&self,key:&ImpactKey,fb:RecallFeedback)->Result<(),String>{
   let mut active=self.active.write().await; let Some(v)=active.get_mut(key) else{return Ok(())};
   let target=match fb{RecallFeedback::Useful=>1.,RecallFeedback::Irrelevant=>0.,RecallFeedback::SurprisingUseful=>1.};
   v.activation_heat=lerp(v.activation_heat,target,self.cfg.feedback_rate);
   v.confidence=(v.confidence+.06).min(1.);
   if matches!(fb,RecallFeedback::SurprisingUseful){v.relation_impact=(v.relation_impact+.15).min(1.);}
   v.current_impact=effective(v,self.cfg);
   let mut d=self.durable.get(key).await?.unwrap_or_else(||DurableImpact::new(key.0));
   d.historical_impact=lerp(d.historical_impact,v.current_impact,self.cfg.feedback_rate);
   d.max_observed_impact=d.max_observed_impact.max(v.current_impact); d.last_impact_at=Utc::now();
   self.durable.put(d).await
 }
 pub async fn snapshot(&self)->Vec<DynamicImpact>{self.active.read().await.values().cloned().collect()}
}
fn effective(v:&DynamicImpact,c:DynamicIndexConfig)->f32{(v.current_impact*c.durable_weight+v.context_impact*c.context_weight+v.activation_heat*c.activation_weight+v.relation_impact*c.relation_weight).clamp(0.,1.)}
fn lerp(a:f32,b:f32,r:f32)->f32{(a+(b-a)*r).clamp(0.,1.)}
fn decay(v:&mut DynamicImpact,now:chrono::DateTime<Utc>){let d=(now-v.updated_at).num_seconds().max(0)as f32/86400.;let f=(-v.decay_rate*d).exp();v.context_impact*=f;v.activation_heat*=f;v.relation_impact*=f;}
fn tokenize(s:&str)->Vec<String>{s.split(|c:char|!c.is_alphanumeric()&&c!='_'&&c!='-').filter(|x|x.chars().count()>1).map(|x|x.to_lowercase()).collect()}
