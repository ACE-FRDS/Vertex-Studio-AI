use uuid::Uuid;
use vertex_ai_impact::*;
#[tokio::main]
async fn main()->Result<(),Box<dyn std::error::Error>>{
 let repo=InMemoryDurableImpactRepository::shared();
 let idx=DynamicImpactIndex::new(repo,DynamicIndexConfig::default());
 let a=DurableImpact::new(Uuid::new_v4());
 let mut b=DurableImpact::new(Uuid::new_v4()); b.base_impact=.72;b.historical_impact=.80;
 idx.register(a).await?;idx.register(b).await?;
 let c=idx.ingest(&InputStimulus{text:"VMB Gateway 403 memory bridge".into(),context_keys:vec!["VSA".into(),"memory".into()],strength:.95}).await;
 println!("front-door candidates:");
 for x in c{println!("{} impact={:.3} confidence={:.3}",x.key.0,x.effective_impact,x.confidence);}
 Ok(())
}
