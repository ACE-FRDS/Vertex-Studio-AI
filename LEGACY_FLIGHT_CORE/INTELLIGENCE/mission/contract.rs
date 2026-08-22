use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Header {
    pub mission_id: Uuid,
    pub task_id: Uuid,
    pub role: String,
    pub current_position: String,
    pub scope: Vec<String>,
    pub authority: String,
    pub available_evidence: Vec<String>,
    pub required_inputs: Vec<String>,
    pub forbidden_actions: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Footer {
    pub acceptance: Vec<String>,
    pub required_evidence: Vec<String>,
    pub output_contract: Vec<String>,
    pub stop_conditions: Vec<String>,
    pub relay_requirements: Vec<String>,
    pub vcc_update: String,
    pub vsp_update: String,
}
