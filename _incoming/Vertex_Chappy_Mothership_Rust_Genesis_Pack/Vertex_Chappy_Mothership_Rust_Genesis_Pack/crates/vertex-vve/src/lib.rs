use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Component, Path, PathBuf},
};
use uuid::Uuid;
use vertex_core::VertexError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChangeSet {
    pub changeset_id: String,
    pub created_at: String,
    pub state: String,
    pub overlay_root: PathBuf,
    pub files: Vec<VveFile>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VveFile {
    pub path: String,
    pub bytes: u64,
    pub sha256: String,
}

fn safe_relative(path: &Path) -> Result<(), VertexError> {
    if path.is_absolute()
        || path.components().any(|c| {
            matches!(
                c,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(VertexError::InvalidRequest(format!(
            "unsafe VVE path: {}",
            path.display()
        )));
    }
    Ok(())
}

pub fn create(vve_root: &Path) -> Result<ChangeSet> {
    let id = Uuid::new_v4();
    let overlay = vve_root.join("changesets").join(id.to_string());
    fs::create_dir_all(&overlay)?;
    let cs = ChangeSet {
        changeset_id: format!("changeset://vertex/{id}"),
        created_at: Utc::now().to_rfc3339(),
        state: "DRAFT".into(),
        overlay_root: overlay.clone(),
        files: vec![],
    };
    save(&cs)?;
    Ok(cs)
}
pub fn write_file(mut cs: ChangeSet, rel: &Path, content: &[u8]) -> Result<ChangeSet, VertexError> {
    safe_relative(rel)?;
    let path = cs.overlay_root.join(rel);
    if let Some(p) = path.parent() {
        fs::create_dir_all(p).map_err(|e| VertexError::Io(e.to_string()))?;
    }
    fs::write(&path, content).map_err(|e| VertexError::Io(e.to_string()))?;
    let hash = hex::encode(Sha256::digest(content));
    cs.files.retain(|f| f.path != rel.to_string_lossy());
    cs.files.push(VveFile {
        path: rel.to_string_lossy().replace('\\', "/"),
        bytes: content.len() as u64,
        sha256: hash,
    });
    save(&cs).map_err(|e| VertexError::Io(e.to_string()))?;
    Ok(cs)
}
pub fn load(manifest: &Path) -> Result<ChangeSet> {
    Ok(serde_json::from_str(&fs::read_to_string(manifest)?)?)
}
fn save(cs: &ChangeSet) -> Result<()> {
    let p = cs.overlay_root.join("CHANGESET.json");
    fs::write(
        p,
        serde_json::to_vec_pretty(cs).context("serialize changeset")?,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_parent_escape() {
        let td = std::env::temp_dir().join(format!("vve-{}", Uuid::new_v4()));
        let cs = create(&td).unwrap();
        assert!(write_file(cs, Path::new("../escape.txt"), b"x").is_err());
        let _ = fs::remove_dir_all(td);
    }
}
