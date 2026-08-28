#[derive(Debug, Clone)]
pub struct ActivationPolicy {
    pub threshold: f32,
    pub hop_limit: u32,
    pub branch_limit: u32,
    pub time_budget_ms: u64,
}
