#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockKind {
    Hard,
    Structure,
    Layout,
    Style,
    Behavior,
    FreezeRegion,
}

#[derive(Debug, Clone)]
pub struct LockRule {
    pub target: String,
    pub kind: LockKind,
    pub owner: String,
}
