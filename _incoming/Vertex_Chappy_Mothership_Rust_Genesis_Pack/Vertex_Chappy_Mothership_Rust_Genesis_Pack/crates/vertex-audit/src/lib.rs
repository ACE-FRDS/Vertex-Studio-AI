use anyhow::Result;
use chrono::Utc;
use parking_lot::Mutex;
use serde::Serialize;
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::Arc,
};

#[derive(Clone)]
pub struct AuditLog {
    path: PathBuf,
    lock: Arc<Mutex<()>>,
}
impl AuditLog {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self {
            path: path.into(),
            lock: Arc::new(Mutex::new(())),
        }
    }
    pub fn append<T: Serialize>(&self, event: &str, body: &T) -> Result<()> {
        let _g = self.lock.lock();
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let record = serde_json::json!({"at":Utc::now(),"event":event,"body":body});
        let mut f = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        serde_json::to_writer(&mut f, &record)?;
        f.write_all(b"\n")?;
        f.flush()?;
        Ok(())
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
}
