#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineageState {
    ActiveNonTerminal,
    CanonicalCommitted,
    SupersededByCommittedExecution,
    Rejected,
    RolledBack,
}
