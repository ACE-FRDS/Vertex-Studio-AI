use anyhow::{Context, Result};
use serde_json::Value;
use std::{fs, path::Path};

fn read_json(path: &Path) -> Result<Value> {
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    Ok(serde_json::from_str(text.trim_start_matches('\u{feff}'))?)
}
pub fn read_mothership_state(path: &Path) -> Result<Value> {
    read_json(path)
}
pub fn read_vur_registry(path: &Path) -> Result<Value> {
    read_json(path)
}
pub fn read_json_file(path: &Path) -> Result<Value> {
    read_json(path)
}
