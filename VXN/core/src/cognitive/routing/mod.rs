#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CognitiveTier {
    Deterministic,
    Tier38B,
    Tier8B,
    Tier20B,
    CloudLarge,
    Human,
}

#[derive(Debug, Clone)]
pub struct RoutingDecision {
    pub tier: CognitiveTier,
    pub reason: String,
    pub estimated_cost: f64,
    pub estimated_latency_ms: u64,
}
