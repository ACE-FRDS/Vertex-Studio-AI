use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SignalKind {
    Native,
    Impact,
    Memory,
    Lock,
    State,
    Failure,
    Model,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnSignal {
    pub kind: SignalKind,
    pub source: String,
    pub target: Option<String>,
    pub priority: f32,
    pub payload_ref: Option<String>,
}
