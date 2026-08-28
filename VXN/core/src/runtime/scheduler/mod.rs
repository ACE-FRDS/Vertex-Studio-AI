#[derive(Debug, Clone)]
pub struct SchedulerPolicy {
    pub max_parallel_agents: usize,
    pub max_parallel_models: usize,
    pub event_loop_budget_ms: u64,
}
