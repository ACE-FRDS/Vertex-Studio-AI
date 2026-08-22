use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum AuthorityLevel { Observe, Operate, Admin, Root }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Authority {
    pub subject: Uuid,
    pub level: AuthorityLevel,
    pub scopes: Vec<String>,
    pub human_delegated: bool,
}

impl Authority {
    pub fn permits(&self, scope: &str, required: &AuthorityLevel) -> bool {
        self.human_delegated
            && &self.level >= required
            && self.scopes.iter().any(|s| s == "*" || s == scope)
    }
    pub fn self_promote_root(&mut self) -> Result<(), &'static str> {
        Err("machine self-promotion to Root is forbidden")
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Evidence {
    pub id: Uuid,
    pub kind: String,
    pub subject: String,
    pub digest: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SemanticMutation {
    pub id: Uuid,
    pub actor: Uuid,
    pub target: String,
    pub operation: String,
    pub before: serde_json::Value,
    pub after: serde_json::Value,
    pub scope: String,
    pub evidence: Vec<Evidence>,
}
