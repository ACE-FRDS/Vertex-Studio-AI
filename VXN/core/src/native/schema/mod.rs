use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnSchemaVersion {
    pub major: u16,
    pub minor: u16,
    pub patch: u16,
}

pub trait VersionNegotiation {
    fn compatible_with(&self, other: &VxnSchemaVersion) -> bool;
}
