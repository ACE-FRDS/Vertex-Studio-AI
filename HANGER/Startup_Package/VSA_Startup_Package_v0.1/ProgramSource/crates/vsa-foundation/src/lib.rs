use std::{collections::HashMap, fmt::{Display, Formatter}, sync::atomic::{AtomicU64, Ordering}};

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Id(pub String);

impl Id {
    pub fn new(prefix: &str) -> Self {
        let n = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        Self(format!("{prefix}-{n:016x}"))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VsaError {
    Invalid(String),
    NotFound(String),
    Permission(String),
    Conflict(String),
    Io(String),
    Unsupported(String),
}

impl Display for VsaError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Invalid(v) => write!(f, "invalid: {v}"),
            Self::NotFound(v) => write!(f, "not found: {v}"),
            Self::Permission(v) => write!(f, "permission: {v}"),
            Self::Conflict(v) => write!(f, "conflict: {v}"),
            Self::Io(v) => write!(f, "io: {v}"),
            Self::Unsupported(v) => write!(f, "unsupported: {v}"),
        }
    }
}
impl std::error::Error for VsaError {}
pub type VsaResult<T> = Result<T, VsaError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Permission {
    Read,
    Edit,
    Execute,
    Auto,
    Publish,
    InstallCartridge,
    ChangeArchitecture,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HumanGate {
    pub required: bool,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ExecutionTarget {
    Browser,
    Desktop,
    Server,
    Edge,
    LocalAiRuntime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Capability {
    pub id: String,
    pub targets: Vec<ExecutionTarget>,
    pub permissions: Vec<Permission>,
}

#[derive(Debug, Default)]
pub struct CapabilityRegistry {
    entries: HashMap<String, Capability>,
}
impl CapabilityRegistry {
    pub fn register(&mut self, capability: Capability) -> VsaResult<()> {
        if self.entries.contains_key(&capability.id) {
            return Err(VsaError::Conflict(capability.id));
        }
        self.entries.insert(capability.id.clone(), capability);
        Ok(())
    }
    pub fn get(&self, id: &str) -> Option<&Capability> { self.entries.get(id) }
    pub fn ids(&self) -> Vec<String> {
        let mut v: Vec<_> = self.entries.keys().cloned().collect();
        v.sort(); v
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceRef {
    pub source: String,
    pub locator: String,
    pub observed_at: String,
    pub content_hash: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub severity: String,
    pub code: String,
    pub message: String,
    pub locator: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn registry_rejects_duplicate() {
        let mut r = CapabilityRegistry::default();
        let c = Capability{ id:"x".into(), targets:vec![ExecutionTarget::Desktop], permissions:vec![Permission::Execute]};
        r.register(c.clone()).unwrap();
        assert!(r.register(c).is_err());
    }
}
