#[derive(Debug, Clone)]
pub struct EscalationPolicy {
    pub max_retries_per_tier: u32,
    pub allow_cloud: bool,
    pub require_human_for_high_risk: bool,
}
