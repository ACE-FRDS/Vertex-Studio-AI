#[derive(Debug, Clone)]
pub struct CognitiveBudget {
    pub token_budget: u64,
    pub time_budget_ms: u64,
    pub branch_budget: u32,
    pub recall_budget: u32,
}
