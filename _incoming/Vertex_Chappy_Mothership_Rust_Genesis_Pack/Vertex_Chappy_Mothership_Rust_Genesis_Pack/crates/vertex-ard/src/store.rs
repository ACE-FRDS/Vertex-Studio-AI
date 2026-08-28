use crate::{model::ArdDocument, relay::recover_interrupted_sessions};
use anyhow::{Context, Result};
use chrono::Utc;
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone)]
pub struct ArdStore {
    path: PathBuf,
}

impl ArdStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn load(&self) -> Result<ArdDocument> {
        if !self.path.exists() {
            return Ok(ArdDocument::default());
        }

        let text = fs::read_to_string(&self.path)
            .with_context(|| format!("read ARD store {}", self.path.display()))?;

        serde_json::from_str(text.trim_start_matches('\u{feff}'))
            .with_context(|| format!("parse ARD store {}", self.path.display()))
    }

    pub fn load_with_recovery(&self) -> Result<ArdDocument> {
        let mut document = self.load()?;

        if recover_interrupted_sessions(&mut document) > 0 {
            self.save(&document)?;
        }

        Ok(document)
    }

    pub fn save(&self, document: &ArdDocument) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create ARD store directory {}", parent.display()))?;
        }

        let mut snapshot = document.clone();
        snapshot.updated_at = Utc::now();

        let bytes = serde_json::to_vec_pretty(&snapshot).context("serialize ARD document")?;

        let temp = self.path.with_extension("json.tmp");
        let backup = self.path.with_extension("json.bak");

        fs::write(&temp, bytes).with_context(|| format!("write ARD temp {}", temp.display()))?;

        if self.path.exists() {
            fs::copy(&self.path, &backup).with_context(|| {
                format!(
                    "backup ARD store {} -> {}",
                    self.path.display(),
                    backup.display()
                )
            })?;

            fs::remove_file(&self.path)
                .with_context(|| format!("remove old ARD store {}", self.path.display()))?;
        }

        if let Err(error) = fs::rename(&temp, &self.path) {
            if backup.exists() && !self.path.exists() {
                let _ = fs::copy(&backup, &self.path);
            }

            return Err(error)
                .with_context(|| format!("replace ARD store {}", self.path.display()));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn store_roundtrip() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ard.json");

        let store = ArdStore::new(&path);
        let document = ArdDocument::default();

        store.save(&document).unwrap();

        let restored = store.load().unwrap();

        assert_eq!(restored.schema, "VERTEX_ARD");
        assert_eq!(restored.version, "2.0.0-genesis");
    }
}
