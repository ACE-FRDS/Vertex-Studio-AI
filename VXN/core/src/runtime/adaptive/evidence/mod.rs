use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeEvidence {
    pub model_class: String,
    pub mission_id: String,
    pub preferred_variant: String,
    pub samples: u64,
    pub prompt_tokens: Option<f64>,
    pub latency_ms: Option<f64>,
    pub tokens_per_second: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeEvidenceStore {
    pub entries: Vec<RuntimeEvidence>,
}

impl RuntimeEvidenceStore {
    pub fn recommend(&self, model_class: &str, mission_id: &str) -> Option<&RuntimeEvidence> {
        self.entries
            .iter()
            .filter(|e| e.model_class == model_class && e.mission_id == mission_id)
            .max_by_key(|e| e.samples)
    }
}
