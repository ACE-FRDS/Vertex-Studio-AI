/*
 * VERTEX MOTHERSHIP REAL HYPER AGENT RUNTIME V2
 *
 * Ollama REST Provider
 * -> controlled Workspace write
 * -> existing autonomous mission loop.
 */

use std::fs::{self, File};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use vsa_vertex_bridge::FleetControllerSession;

use crate::{
    AutonomousMissionConfig, AutonomousMissionReport, MissionRunResolver,
    run_autonomous_mission_loop,
};

pub const REAL_HYPER_AGENT_RUNTIME_SCHEMA: &str = "vertex.mothership.real-hyper-agent-runtime.v2";

const FILE_BEGIN: &str = "VERTEX_FILE_BEGIN";
const FILE_END: &str = "VERTEX_FILE_END";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OllamaProviderSpec {
    pub endpoint: String,
    pub model: String,
    pub timeout_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyperAgentWorkspace {
    pub root: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyperAgentMission {
    pub mission_id: String,
    pub instruction: String,
    pub target_relative_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyperAgentProviderResult {
    pub exit_code: Option<i32>,
    pub success: bool,
    pub timed_out: bool,
    pub response: String,
    pub stderr: String,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyperAgentWorkspaceWrite {
    pub mission_id: String,
    pub target_path: String,
    pub bytes_written: usize,
    pub original_existed: bool,
}

#[derive(Debug)]
pub struct RealHyperAgentPipelineReport {
    pub schema: &'static str,
    pub provider: HyperAgentProviderResult,
    pub write: HyperAgentWorkspaceWrite,
    pub voyage: AutonomousMissionReport,
}

fn validate_relative_path(relative: &str) -> Result<PathBuf, String> {
    if relative.trim().is_empty() {
        return Err("target path is empty".into());
    }

    let path = Path::new(relative);

    if path.is_absolute() {
        return Err("absolute target path denied".into());
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}

            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err("workspace escape denied".into());
            }
        }
    }

    Ok(path.to_path_buf())
}

fn resolve_workspace_target(
    workspace: &HyperAgentWorkspace,
    relative: &str,
) -> Result<PathBuf, String> {
    let relative = validate_relative_path(relative)?;

    let root = fs::canonicalize(&workspace.root)
        .map_err(|error| format!("workspace root resolve failed: {}", error))?;

    let target = root.join(relative);

    let parent = target
        .parent()
        .ok_or_else(|| "target parent missing".to_string())?;

    let parent = fs::canonicalize(parent)
        .map_err(|error| format!("target parent resolve failed: {}", error))?;

    if !parent.starts_with(&root) {
        return Err("workspace boundary violation".into());
    }

    Ok(target)
}

fn provider_prompt(mission: &HyperAgentMission) -> String {
    format!(
        r#"You are a Vertex Hyper Agent operating inside a controlled workspace.

MISSION:
{}

TARGET FILE:
{}

INSTRUCTION:
{}

Return the COMPLETE target file using exactly:

VERTEX_FILE_BEGIN
<complete file contents>
VERTEX_FILE_END

Do not output shell commands.
Do not modify other files.
Do not explain the answer.
"#,
        mission.mission_id, mission.target_relative_path, mission.instruction,
    )
}

fn unique_temp_path(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    std::env::temp_dir().join(format!(
        "vertex-{}-{}-{}.tmp",
        label,
        std::process::id(),
        nanos
    ))
}

pub fn execute_ollama_provider(
    provider: &OllamaProviderSpec,
    mission: &HyperAgentMission,
) -> Result<HyperAgentProviderResult, String> {
    if provider.endpoint.trim().is_empty() {
        return Err("provider endpoint empty".into());
    }

    if provider.model.trim().is_empty() {
        return Err("provider model empty".into());
    }

    if provider.timeout_ms == 0 {
        return Err("provider timeout invalid".into());
    }

    let prompt = provider_prompt(mission);

    let body = json!({
        "model": provider.model,
        "prompt": prompt,
        "stream": false
    })
    .to_string();

    let stdout_path = unique_temp_path("ollama-stdout");

    let stderr_path = unique_temp_path("ollama-stderr");

    let stdout_file =
        File::create(&stdout_path).map_err(|e| format!("stdout temp create failed: {}", e))?;

    let stderr_file =
        File::create(&stderr_path).map_err(|e| format!("stderr temp create failed: {}", e))?;

    let seconds = ((provider.timeout_ms + 999) / 1000).max(1);

    let started = Instant::now();

    let mut child = Command::new("curl.exe")
        .args([
            "-sS",
            "--fail-with-body",
            "--max-time",
            &seconds.to_string(),
            "-X",
            "POST",
            &provider.endpoint,
            "-H",
            "Content-Type: application/json",
            "-d",
            &body,
        ])
        .stdout(Stdio::from(stdout_file))
        .stderr(Stdio::from(stderr_file))
        .spawn()
        .map_err(|e| format!("Ollama REST transport start failed: {}", e))?;

    let timeout = Duration::from_millis(provider.timeout_ms);

    let mut timed_out = false;

    let exit_code = loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                break status.code();
            }

            Ok(None) => {
                if started.elapsed() >= timeout {
                    timed_out = true;
                    let _ = child.kill();

                    let status = child
                        .wait()
                        .map_err(|e| format!("provider kill/wait failed: {}", e))?;

                    break status.code();
                }

                thread::sleep(Duration::from_millis(25));
            }

            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();

                return Err(format!("provider polling failed: {}", e));
            }
        }
    };

    let duration_ms = started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64;

    let raw_stdout = fs::read_to_string(&stdout_path).unwrap_or_default();

    let stderr = fs::read_to_string(&stderr_path).unwrap_or_default();

    let _ = fs::remove_file(&stdout_path);

    let _ = fs::remove_file(&stderr_path);

    if timed_out {
        return Ok(HyperAgentProviderResult {
            exit_code,
            success: false,
            timed_out: true,
            response: String::new(),
            stderr,
            duration_ms,
        });
    }

    let json_value: Value = serde_json::from_str(&raw_stdout)
        .map_err(|e| format!("Ollama JSON decode failed: {}; body={}", e, raw_stdout))?;

    let response = json_value
        .get("response")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("Ollama response field missing: {}", raw_stdout))?
        .to_string();

    Ok(HyperAgentProviderResult {
        exit_code,
        success: exit_code == Some(0),
        timed_out: false,
        response,
        stderr,
        duration_ms,
    })
}

pub fn extract_hyper_agent_file(provider_response: &str) -> Result<String, String> {
    let begin = provider_response
        .find(FILE_BEGIN)
        .ok_or_else(|| "VERTEX_FILE_BEGIN missing".to_string())?
        + FILE_BEGIN.len();

    let remainder = &provider_response[begin..];

    let end = remainder
        .find(FILE_END)
        .ok_or_else(|| "VERTEX_FILE_END missing".to_string())?;

    let mut payload = remainder[..end].trim().to_string();

    if payload.starts_with("```") {
        let mut lines = payload.lines().collect::<Vec<_>>();

        if !lines.is_empty() {
            lines.remove(0);
        }

        if !lines.is_empty() && lines.last().unwrap().trim().starts_with("```") {
            lines.pop();
        }

        payload = lines.join("\n").trim().to_string();
    }

    if payload.is_empty() {
        return Err("provider returned empty file".into());
    }

    Ok(payload)
}

fn restore_file(target: &Path, original: &Option<Vec<u8>>) {
    match original {
        Some(bytes) => {
            let _ = fs::write(target, bytes);
        }

        None => {
            let _ = fs::remove_file(target);
        }
    }
}

pub fn execute_real_hyper_agent_pipeline(
    session: FleetControllerSession,
    resolver: &mut dyn MissionRunResolver,
    config: AutonomousMissionConfig,
    provider: &OllamaProviderSpec,
    workspace: &HyperAgentWorkspace,
    mission: &HyperAgentMission,
) -> Result<RealHyperAgentPipelineReport, String> {
    let target = resolve_workspace_target(workspace, &mission.target_relative_path)?;

    let original = if target.exists() {
        Some(fs::read(&target).map_err(|e| format!("workspace snapshot failed: {}", e))?)
    } else {
        None
    };

    let provider_result = execute_ollama_provider(provider, mission)?;

    if !provider_result.success {
        return Err(format!(
            "provider RED exit={:?} timeout={} stderr={}",
            provider_result.exit_code, provider_result.timed_out, provider_result.stderr
        ));
    }

    let generated = extract_hyper_agent_file(&provider_result.response)?;

    fs::write(&target, generated.as_bytes())
        .map_err(|e| format!("workspace write failed: {}", e))?;

    let write = HyperAgentWorkspaceWrite {
        mission_id: mission.mission_id.clone(),

        target_path: target.to_string_lossy().into_owned(),

        bytes_written: generated.len(),

        original_existed: original.is_some(),
    };

    let voyage = match run_autonomous_mission_loop(session, resolver, config) {
        Ok(report) => report,

        Err(e) => {
            restore_file(&target, &original);

            return Err(format!("voyage RED; workspace restored: {}", e));
        }
    };

    Ok(RealHyperAgentPipelineReport {
        schema: REAL_HYPER_AGENT_RUNTIME_SCHEMA,
        provider: provider_result,
        write,
        voyage,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schema_locked() {
        assert_eq!(
            REAL_HYPER_AGENT_RUNTIME_SCHEMA,
            "vertex.mothership.real-hyper-agent-runtime.v2"
        );
    }

    #[test]
    fn workspace_escape_denied() {
        assert!(validate_relative_path("../outside.rs").is_err());

        assert!(validate_relative_path(r"C:\outside.rs").is_err());
    }

    #[test]
    fn file_contract_extracts() {
        let source =
            extract_hyper_agent_file("x\nVERTEX_FILE_BEGIN\nfn x() {}\nVERTEX_FILE_END").unwrap();

        assert_eq!(source, "fn x() {}");
    }
}
