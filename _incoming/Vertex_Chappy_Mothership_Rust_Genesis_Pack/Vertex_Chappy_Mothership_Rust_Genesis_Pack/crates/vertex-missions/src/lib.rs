use anyhow::Result;
use std::{
    fs,
    path::{Path, PathBuf},
};
use vertex_core::MissionEnvelope;
#[derive(Clone)]
pub struct MissionStore {
    root: PathBuf,
}
impl MissionStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
    pub fn save(&self, m: &MissionEnvelope) -> Result<PathBuf> {
        fs::create_dir_all(&self.root)?;
        let safe = m.mission_id.replace("://", "__").replace('/', "_");
        let p = self.root.join(format!("{safe}.json"));
        fs::write(&p, serde_json::to_vec_pretty(m)?)?;
        Ok(p)
    }
    pub fn root(&self) -> &Path {
        &self.root
    }
}
