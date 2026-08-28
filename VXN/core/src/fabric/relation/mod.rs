use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelationEdge {
    pub from: String,
    pub to: String,
    pub relation_type: String,
    pub weight: f32,
    pub confidence: f32,
}
