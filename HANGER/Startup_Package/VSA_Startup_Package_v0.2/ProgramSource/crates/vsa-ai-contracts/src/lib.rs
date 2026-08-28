use vsa_foundation::{ExecutionTarget, Id};
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderDescriptor {
    pub id: String,
    pub local: bool,
    pub capabilities: Vec<String>,
    pub health: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelDescriptor {
    pub id: String,
    pub family: String,
    pub parameter_class: String,
    pub context_size: u64,
    pub provider: String,
    pub preferred_roles: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoleAssignment {
    pub role: String,
    pub model_id: String,
    pub evidence_refs: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityPlacement {
    pub capability: String,
    pub selected: ExecutionTarget,
    pub reason: String,
    pub human_locked: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContextCapsule {
    pub id: Id,
    pub mission_id: Id,
    pub entries: Vec<String>,
    pub provenance: Vec<String>,
}
