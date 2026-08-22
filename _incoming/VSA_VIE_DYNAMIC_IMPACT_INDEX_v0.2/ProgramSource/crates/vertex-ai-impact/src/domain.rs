use chrono::{DateTime,Utc};
use serde::{Deserialize,Serialize};
use uuid::Uuid;

#[derive(Debug,Clone,PartialEq,Eq,Hash,Serialize,Deserialize)]
pub struct ImpactKey(pub Uuid);

#[derive(Debug,Clone,Serialize,Deserialize)]
pub struct DurableImpact {
    pub key:ImpactKey,
    pub base_impact:f32,
    pub historical_impact:f32,
    pub human_fixed_impact:Option<f32>,
    pub max_observed_impact:f32,
    pub last_impact_at:DateTime<Utc>,
}
impl DurableImpact {
    pub fn new(id:Uuid)->Self{Self{key:ImpactKey(id),base_impact:.20,historical_impact:.20,human_fixed_impact:None,max_observed_impact:.20,last_impact_at:Utc::now()}}
}

#[derive(Debug,Clone,Serialize,Deserialize)]
pub struct DynamicImpact {
    pub key:ImpactKey,
    pub current_impact:f32,
    pub context_impact:f32,
    pub activation_heat:f32,
    pub relation_impact:f32,
    pub confidence:f32,
    pub decay_rate:f32,
    pub updated_at:DateTime<Utc>,
}
impl DynamicImpact {
    pub fn seeded(d:&DurableImpact)->Self{
        let seed=d.human_fixed_impact.unwrap_or(d.base_impact.max(d.historical_impact));
        Self{key:d.key.clone(),current_impact:seed,context_impact:0.,activation_heat:0.,relation_impact:0.,confidence:.25,decay_rate:.04,updated_at:Utc::now()}
    }
}

#[derive(Debug,Clone,Serialize,Deserialize)]
pub struct InputStimulus {
    pub text:String,
    pub context_keys:Vec<String>,
    pub strength:f32,
}
#[derive(Debug,Clone,Serialize,Deserialize)]
pub struct ImpactCandidate {
    pub key:ImpactKey,
    pub effective_impact:f32,
    pub confidence:f32,
}
#[derive(Debug,Clone,Copy,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum RecallFeedback { Useful, Irrelevant, SurprisingUseful }
