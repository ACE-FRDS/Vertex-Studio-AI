use std::collections::HashMap;
use vsa_foundation::Id;
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct SkillStat { pub name:String,pub score:u32,pub evidence_count:u32 }
#[derive(Debug,Clone)]
pub struct DeveloperProfile {
    pub id:Id,pub display_name:String,pub bio:String,pub skills:Vec<SkillStat>,
    pub achievements:Vec<String>,pub portfolio:Vec<PortfolioItem>,pub level:u32,pub exp:u64
}
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct PortfolioItem {
    pub id:Id,pub title:String,pub summary:String,pub artifact_ref:String,pub tags:Vec<String>,pub public:bool
}
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Quest {
    pub id:Id,pub title:String,pub description:String,pub assigned_to:Option<Id>,pub public_reward_points:Option<u64>,
    pub private_compensation_ref:Option<String>
}
impl DeveloperProfile {
    pub fn gain_exp(&mut self,n:u64){self.exp+=n; self.level=1+(self.exp/1000) as u32;}
}
#[derive(Debug,Default)]
pub struct PortfolioIndex { pub by_tag:HashMap<String,Vec<Id>> }
