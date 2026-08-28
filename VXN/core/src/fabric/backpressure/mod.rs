#[derive(Debug, Clone)]
pub struct BackpressureBudget {
    pub max_hops: u32,
    pub max_branches: u32,
    pub max_events: u64,
    pub max_time_ms: u64,
    pub max_memory_bytes: u64,
}
