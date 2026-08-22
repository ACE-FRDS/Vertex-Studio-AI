use anyhow::{Context, Result};
use serde::Serialize;
use std::path::Path;
use tokio::process::Command;

#[derive(Debug, Serialize)]
pub struct GitInspection {
    pub root: String,
    pub branch: String,
    pub commit: String,
    pub remote: String,
    pub dirty: bool,
    pub porcelain: String,
}
async fn git(root: &Path, args: &[&str]) -> Result<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .await
        .context("execute git")?;
    if !out.status.success() {
        anyhow::bail!("git {:?}: {}", args, String::from_utf8_lossy(&out.stderr));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
pub async fn inspect(root: &Path) -> Result<GitInspection> {
    let porcelain = git(root, &["status", "--porcelain"]).await?;
    Ok(GitInspection {
        root: git(root, &["rev-parse", "--show-toplevel"]).await?,
        branch: git(root, &["branch", "--show-current"]).await?,
        commit: git(root, &["rev-parse", "--short", "HEAD"]).await?,
        remote: git(root, &["remote", "get-url", "origin"])
            .await
            .unwrap_or_default(),
        dirty: !porcelain.is_empty(),
        porcelain,
    })
}
