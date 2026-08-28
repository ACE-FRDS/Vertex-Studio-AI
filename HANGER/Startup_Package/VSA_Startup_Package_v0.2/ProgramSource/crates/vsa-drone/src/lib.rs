use vsa_ard::WorkUnit;
use vsa_foundation::Id;
#[derive(Debug, Clone)]
pub struct MissionCapsule {
    pub id: Id,
    pub unit: WorkUnit,
    pub context_capsule: Vec<String>,
    pub rcc: String,
    pub permissions: Vec<String>,
    pub tools: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DroneReturn {
    pub capsule_id: Id,
    pub artifacts: Vec<String>,
    pub evidence: Vec<String>,
    pub experience: Vec<String>,
    pub failures: Vec<String>,
}
