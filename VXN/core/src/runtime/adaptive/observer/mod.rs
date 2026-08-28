use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeObservation {
    pub model_id: String,
    pub model_class: String,
    pub mission_class: String,
    pub runtime_variant: String,
    pub prompt_tokens: Option<u64>,
    pub completion_tokens: Option<u64>,
    pub tokens_per_second: Option<f64>,
    pub latency_ms: Option<u64>,
    pub json_valid: bool,
    pub schema_completeness: f64,
    pub lock_awareness: f64,
    pub scope_awareness: f64,
    pub authority_awareness: f64,
    pub uncertainty_awareness: f64,
    pub retry_count: u32,
    pub rollback_count: u32,
    pub hot_swap_count: u32,
    pub ram_bytes: Option<u64>,
    pub vram_bytes: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RuntimeDiagnosis {
    Healthy,
    PromptBloat,
    ModelTooSmall,
    ModelTooLarge,
    MissingToolboxComponent,
    UnneededToolboxComponent,
    ReasoningLoop,
    SchemaDrift,
    LockScopeFailure,
    AuthorityFailure,
    MemoryRecallFailure,
    ResourcePressure,
}
