use anyhow::{Context, Result};
use serde::Deserialize;
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};
use vertex_core::{Capability, VertexError};

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub paths: PathsConfig,
    pub policy: PolicyConfig,
}
#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub bind_host: String,
    pub bind_port: u16,
    pub token_env: String,
}
#[derive(Debug, Clone, Deserialize)]
pub struct PathsConfig {
    pub mothership_root: PathBuf,
    pub state_file: PathBuf,
    pub delta_file: PathBuf,
    pub vur_registry: PathBuf,
    pub vve_root: PathBuf,
    pub real_repository: PathBuf,
    pub audit_file: PathBuf,
}
#[derive(Debug, Clone, Deserialize)]
pub struct PolicyConfig {
    pub active_profile: String,
    pub direct_real_repository_write: bool,
    pub human_gate_required: bool,
    pub profiles: HashMap<String, Profile>,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Profile {
    pub allowed_capabilities: Vec<String>,
    pub allowed_programs: Vec<String>,
    pub allowed_roots: Vec<PathBuf>,
    pub max_command_seconds: u64,
}

impl Config {
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let text = fs::read_to_string(path.as_ref())
            .with_context(|| format!("read config {}", path.as_ref().display()))?;
        Ok(toml::from_str(&text)?)
    }
    pub fn profile(&self) -> Result<&Profile> {
        self.policy
            .profiles
            .get(&self.policy.active_profile)
            .with_context(|| format!("missing active profile {}", self.policy.active_profile))
    }
}

pub fn require_capability(cfg: &Config, cap: &Capability) -> Result<(), VertexError> {
    let p = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;
    if p.allowed_capabilities
        .iter()
        .any(|x| x == "*" || x == cap.as_str())
    {
        Ok(())
    } else {
        Err(VertexError::CapabilityDenied(cap.as_str().into()))
    }
}

pub fn require_program(cfg: &Config, program: &str) -> Result<(), VertexError> {
    let p = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;
    let file = Path::new(program)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(program);
    if p.allowed_programs
        .iter()
        .any(|x| x == "*" || x.eq_ignore_ascii_case(file))
    {
        Ok(())
    } else {
        Err(VertexError::CapabilityDenied(format!("program:{file}")))
    }
}

pub fn require_cwd(cfg: &Config, cwd: &Path) -> Result<(), VertexError> {
    let p = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;
    let normalized = cwd.canonicalize().unwrap_or_else(|_| cwd.to_path_buf());
    if p.allowed_roots.iter().any(|r| {
        let rr = r.canonicalize().unwrap_or_else(|_| r.clone());
        normalized.starts_with(rr)
    }) {
        Ok(())
    } else {
        Err(VertexError::CapabilityDenied(format!(
            "cwd:{}",
            cwd.display()
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn wildcard_program_allows_anything() {
        let mut profiles = HashMap::new();
        profiles.insert(
            "x".into(),
            Profile {
                allowed_capabilities: vec!["*".into()],
                allowed_programs: vec!["*".into()],
                allowed_roots: vec![],
                max_command_seconds: 1,
            },
        );
        let cfg = Config {
            server: ServerConfig {
                bind_host: "127.0.0.1".into(),
                bind_port: 1,
                token_env: "X".into(),
            },
            paths: PathsConfig {
                mothership_root: ".".into(),
                state_file: "a".into(),
                delta_file: "b".into(),
                vur_registry: "c".into(),
                vve_root: "d".into(),
                real_repository: "e".into(),
                audit_file: "f".into(),
            },
            policy: PolicyConfig {
                active_profile: "x".into(),
                direct_real_repository_write: false,
                human_gate_required: true,
                profiles,
            },
        };
        assert!(require_program(&cfg, "anything.exe").is_ok());
    }
}
