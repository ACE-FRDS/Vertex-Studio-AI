#[derive(Debug, Clone)]
pub struct TracePoint {
    pub stage: String,
    pub latency_ms: u64,
    pub token_count: Option<u64>,
    pub model_id: Option<String>,
    pub impact_nodes: usize,
}
