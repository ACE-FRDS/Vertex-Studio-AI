#[derive(Debug, Clone, Copy)]
pub enum RecoveryAction {
    Retry,
    EscalateModel,
    DegradeCapability,
    Rollback,
    Hold,
    HumanGate,
}
