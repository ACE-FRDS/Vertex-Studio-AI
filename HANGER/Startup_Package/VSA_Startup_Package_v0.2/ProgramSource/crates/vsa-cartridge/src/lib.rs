use std::collections::HashMap;
use vsa_foundation::{VsaError, VsaResult};
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CartridgeKind {
    Rcc,
    Ui,
    Character,
    Tool,
    Runtime,
    Provider,
    Drone,
    Theme,
    Font,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CartridgeManifest {
    pub id: String,
    pub version: String,
    pub kind: CartridgeKind,
    pub permissions: Vec<String>,
    pub entry: String,
    pub signature: Option<String>,
    pub sandbox_required: bool,
}
#[derive(Debug, Default)]
pub struct CartridgeRegistry {
    entries: HashMap<String, CartridgeManifest>,
}
impl CartridgeRegistry {
    pub fn install(&mut self, m: CartridgeManifest) -> VsaResult<()> {
        if self.entries.contains_key(&m.id) {
            return Err(VsaError::Conflict(m.id));
        }
        self.entries.insert(m.id.clone(), m);
        Ok(())
    }
    pub fn get(&self, id: &str) -> Option<&CartridgeManifest> {
        self.entries.get(id)
    }
}
