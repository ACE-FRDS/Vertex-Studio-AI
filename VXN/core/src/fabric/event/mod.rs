use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnEvent {
    pub event_id: String,
    pub kind: String,
    pub at_unix_ms: u64,
    pub source: String,
    pub data_ref: Option<String>,
}
