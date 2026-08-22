use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SemanticRevision {
    pub id: Uuid,
    pub parents: Vec<Uuid>,
    pub mutations: Vec<Uuid>,
    pub rationale_vcc: Vec<String>,
    pub evidence: Vec<String>,
    pub affected_entities: Vec<String>,
    pub projections: Vec<String>,
}

impl SemanticRevision {
    pub fn preserves_reason(&self) -> bool {
        !self.rationale_vcc.is_empty() && !self.evidence.is_empty()
    }
}
