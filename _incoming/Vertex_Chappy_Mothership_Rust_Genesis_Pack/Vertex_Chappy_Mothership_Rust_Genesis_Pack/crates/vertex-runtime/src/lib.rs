use serde::{Deserialize, Serialize};
use std::{
    path::{Component, Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{process::Command, time::timeout};
use vertex_core::VertexError;
use vertex_policy::{require_cwd, require_program, Config};

#[derive(Debug, Clone, Deserialize)]
pub struct RunSpec {
    pub program: String,
    #[serde(default)]
    pub args: Vec<String>,
    pub cwd: PathBuf,
    #[serde(default)]
    pub timeout_seconds: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RunResult {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PowerShellSafeAction {
    TestPath,
    ListDirectory,
    ReadText,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PowerShellSafeSpec {
    pub action: PowerShellSafeAction,
    pub path: PathBuf,
    #[serde(default)]
    pub timeout_seconds: Option<u64>,
}

fn validate_safe_path(cfg: &Config, path: &Path) -> Result<PathBuf, VertexError> {
    if path.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err(VertexError::InvalidRequest(
            "parent traversal is not allowed".into(),
        ));
    }

    let normalized = if path.exists() {
        path.canonicalize()
            .map_err(|e| VertexError::Io(e.to_string()))?
    } else {
        let parent = path
            .parent()
            .ok_or_else(|| VertexError::InvalidRequest("path has no parent".into()))?;

        let canonical_parent = parent
            .canonicalize()
            .map_err(|e| VertexError::Io(e.to_string()))?;

        let name = path
            .file_name()
            .ok_or_else(|| VertexError::InvalidRequest("path has no file name".into()))?;

        canonical_parent.join(name)
    };

    let profile = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;

    let allowed = profile.allowed_roots.iter().any(|root| {
        let normalized_root = root.canonicalize().unwrap_or_else(|_| root.clone());

        normalized.starts_with(normalized_root)
    });

    if !allowed {
        return Err(VertexError::CapabilityDenied(format!(
            "path:{}",
            path.display()
        )));
    }

    Ok(normalized)
}

pub async fn run(cfg: &Config, spec: RunSpec) -> Result<RunResult, VertexError> {
    require_program(cfg, &spec.program)?;
    require_cwd(cfg, &spec.cwd)?;

    let max = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?
        .max_command_seconds;

    let secs = spec.timeout_seconds.unwrap_or(max).min(max);

    let program = spec.program.clone();
    let args = spec.args.clone();
    let cwd = spec.cwd.clone();

    let mut cmd = Command::new(&spec.program);
    cmd.args(&spec.args)
        .current_dir(&spec.cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let child = cmd
        .spawn()
        .map_err(|e| VertexError::Execution(e.to_string()))?;

    match timeout(Duration::from_secs(secs), child.wait_with_output()).await {
        Ok(Ok(out)) => Ok(RunResult {
            program: program.clone(),
            args: args.clone(),
            cwd: cwd.clone(),
            exit_code: out.status.code(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
            timed_out: false,
        }),
        Ok(Err(e)) => Err(VertexError::Execution(e.to_string())),
        Err(_) => Ok(RunResult {
            program,
            args,
            cwd,
            exit_code: None,
            stdout: String::new(),
            stderr: "command timed out".into(),
            timed_out: true,
        }),
    }
}

pub async fn run_powershell_safe(
    cfg: &Config,
    spec: PowerShellSafeSpec,
) -> Result<RunResult, VertexError> {
    require_program(cfg, "powershell.exe")?;

    let safe_path = validate_safe_path(cfg, &spec.path)?;

    let script = match spec.action {
        PowerShellSafeAction::TestPath => {
            "if (Test-Path -LiteralPath $env:VERTEX_SAFE_PATH) { 'true' } else { 'false' }"
        }
        PowerShellSafeAction::ListDirectory => {
            "Get-ChildItem -LiteralPath $env:VERTEX_SAFE_PATH -Force | Select-Object Name,FullName,Length,Mode | ConvertTo-Json -Depth 4 -Compress"
        }
        PowerShellSafeAction::ReadText => {
            "Get-Content -LiteralPath $env:VERTEX_SAFE_PATH -Raw -Encoding UTF8"
        }
    };

    let max = cfg
        .profile()
        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?
        .max_command_seconds;

    let secs = spec.timeout_seconds.unwrap_or(max).min(max);

    let program = "powershell.exe".to_owned();
    let args = vec![
        "-NoLogo".to_owned(),
        "-NoProfile".to_owned(),
        "-NonInteractive".to_owned(),
        "-ExecutionPolicy".to_owned(),
        "Bypass".to_owned(),
        "-Command".to_owned(),
        script.to_owned(),
    ];
    let cwd = cfg.paths.mothership_root.clone();

    let mut cmd = Command::new("powershell.exe");

    cmd.args([
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        script,
    ])
    .env("VERTEX_SAFE_PATH", safe_path.as_os_str())
    .current_dir(&cfg.paths.mothership_root)
    .stdin(Stdio::null())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());

    let child = cmd
        .spawn()
        .map_err(|e| VertexError::Execution(e.to_string()))?;

    match timeout(Duration::from_secs(secs), child.wait_with_output()).await {
        Ok(Ok(out)) => Ok(RunResult {
            program: program.clone(),
            args: args.clone(),
            cwd: cwd.clone(),
            exit_code: out.status.code(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
            timed_out: false,
        }),
        Ok(Err(e)) => Err(VertexError::Execution(e.to_string())),
        Err(_) => Ok(RunResult {
            program,
            args,
            cwd,
            exit_code: None,
            stdout: String::new(),
            stderr: "PowerShell safe action timed out".into(),
            timed_out: true,
        }),
    }
}
