use std::collections::HashMap;
use vsa_foundation::Id;

#[derive(Debug, Clone)]
pub struct MissionMetric {
    pub mission_id:Id,
    pub worker:String,
    pub model:String,
    pub language:String,
    pub duration_ms:u64,
    pub prompt_units:u64,
    pub pass:bool,
    pub retries:u32,
    pub scope_violations:u32,
    pub human_interventions:u32,
    pub vram_mb:Option<u64>,
}
#[derive(Debug,Default)]
pub struct Observatory { pub records:Vec<MissionMetric> }
impl Observatory {
    pub fn record(&mut self,m:MissionMetric){self.records.push(m);}
    pub fn pass_rate_by_model(&self)->HashMap<String,f64>{
        let mut t:HashMap<String,(u64,u64)>=HashMap::new();
        for r in &self.records { let e=t.entry(r.model.clone()).or_default(); e.1+=1; if r.pass{e.0+=1;} }
        t.into_iter().map(|(k,(p,n))|(k,p as f64/n as f64)).collect()
    }
}
