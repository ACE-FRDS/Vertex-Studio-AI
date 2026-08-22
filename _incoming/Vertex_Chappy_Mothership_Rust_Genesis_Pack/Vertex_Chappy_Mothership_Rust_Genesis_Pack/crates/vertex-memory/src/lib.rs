use anyhow::Result;
use serde::Serialize;
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
};
#[derive(Debug, Serialize)]
pub struct BootDocument {
    pub name: String,
    pub path: String,
    pub exists: bool,
    pub value: Option<Value>,
}
pub fn load_boot_documents(items: &[(String, PathBuf)]) -> Vec<BootDocument> {
    items
        .iter()
        .map(|(name, path)| {
            let value = fs::read_to_string(path)
                .ok()
                .and_then(|s| serde_json::from_str(s.trim_start_matches('\u{feff}')).ok());
            BootDocument {
                name: name.clone(),
                path: path.display().to_string(),
                exists: path.exists(),
                value,
            }
        })
        .collect()
}
pub fn read_text(path: &Path) -> Result<String> {
    Ok(fs::read_to_string(path)?)
}
