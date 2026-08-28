use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Component, Path, PathBuf},
    process::Stdio,
    time::{Duration, Instant},
};
use tokio::{process::Command, time::timeout};

const MAX_FILE: u64 = 4 * 1024 * 1024;
const MAX_TREE: usize = 20000;

#[derive(Serialize)]
struct RuntimeInfo {
    core_root: String,
    cargo_workspace: bool,
    mothership: bool,
    autonomous_loop: bool,
    real_hyper_agent: bool,
    bridge: bool,
    recent_reports: Vec<String>,
}
#[derive(Serialize)]
struct FileSnapshot {
    path: String,
    content: String,
    language: String,
    bytes: usize,
    lines: usize,
}
#[derive(Serialize)]
struct WriteResult {
    path: String,
    bytes: usize,
    lines: usize,
}
#[derive(Serialize)]
struct ActionResult {
    action: String,
    executable: String,
    args: Vec<String>,
    success: bool,
    timed_out: bool,
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    duration_ms: u128,
}
#[derive(Deserialize)]
struct WriteInput {
    path: String,
    content: String,
}

fn norm(p: &Path) -> String {
    p.to_string_lossy().replace('\\', "/")
}
fn root() -> Result<PathBuf, String> {
    let m = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let b = m.ancestors().nth(3).ok_or("cannot resolve v0.2 root")?;
    let c = fs::canonicalize(b.join("ProgramSource")).map_err(|e| e.to_string())?;
    if !c.join("Cargo.toml").is_file() {
        return Err("ProgramSource Cargo.toml missing".into());
    }
    Ok(c)
}
fn secret(p: &Path) -> bool {
    let n = p
        .file_name()
        .and_then(|x| x.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    n == ".env"
        || n.starts_with(".env.")
        || matches!(n.as_str(), "id_rsa" | "id_ed25519")
        || matches!(
            p.extension()
                .and_then(|x| x.to_str())
                .map(str::to_ascii_lowercase)
                .as_deref(),
            Some("pem" | "pfx" | "key")
        )
}
fn rel(s: &str) -> Result<PathBuf, String> {
    let p = Path::new(s);
    if s.trim().is_empty()
        || p.is_absolute()
        || p.components().any(|c| {
            matches!(
                c,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err("absolute/parent traversal denied".into());
    }
    if secret(p) {
        return Err("secret-like path denied".into());
    }
    Ok(p.to_path_buf())
}
fn existing(r: &Path, s: &str) -> Result<PathBuf, String> {
    let p = fs::canonicalize(r.join(rel(s)?)).map_err(|e| e.to_string())?;
    if !p.starts_with(r) {
        return Err("workspace escape denied".into());
    }
    if secret(&p) {
        return Err("secret-like path denied".into());
    }
    Ok(p)
}
fn writable(r: &Path, s: &str) -> Result<PathBuf, String> {
    let p = r.join(rel(s)?);
    let mut a = p.as_path();
    while !a.exists() {
        a = a.parent().ok_or("no workspace ancestor")?
    }
    let a = fs::canonicalize(a).map_err(|e| e.to_string())?;
    if !a.starts_with(r) {
        return Err("workspace escape denied".into());
    }
    Ok(p)
}
fn ignored(n: &str) -> bool {
    matches!(
        n,
        ".git" | "target" | "node_modules" | "dist" | "build" | ".idea" | ".vscode"
    )
}
fn tree(r: &Path, c: &Path, d: usize, max: usize, out: &mut Vec<String>) -> Result<(), String> {
    if d > max || out.len() >= MAX_TREE {
        return Ok(());
    }
    let mut es = fs::read_dir(c)
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .collect::<Vec<_>>();
    es.sort_by_key(|e| e.file_name().to_string_lossy().to_ascii_lowercase());
    for e in es {
        if out.len() >= MAX_TREE {
            break;
        }
        let p = e.path();
        let md = e.metadata().map_err(|x| x.to_string())?;
        let n = e.file_name().to_string_lossy().into_owned();
        if md.is_dir() && ignored(&n) {
            continue;
        }
        let rr = p.strip_prefix(r).unwrap_or(&p);
        let k = if md.is_dir() { "D" } else { "F" };
        out.push(format!("{}[{}] {}", "  ".repeat(d), k, norm(rr)));
        if md.is_dir() {
            tree(r, &p, d + 1, max, out)?
        }
    }
    Ok(())
}
fn has_named(r: &Path, target: &str, max: usize) -> bool {
    fn go(c: &Path, t: &str, d: usize, m: usize) -> bool {
        if d > m {
            return false;
        }
        let Ok(es) = fs::read_dir(c) else {
            return false;
        };
        for e in es.filter_map(Result::ok) {
            let p = e.path();
            let Ok(md) = e.metadata() else { continue };
            if md.is_dir() {
                let n = e.file_name().to_string_lossy().into_owned();
                if ignored(&n) {
                    continue;
                }
                if go(&p, t, d + 1, m) {
                    return true;
                }
            } else if e
                .file_name()
                .to_str()
                .is_some_and(|x| x.eq_ignore_ascii_case(t))
            {
                return true;
            }
        }
        false
    }
    go(r, target, 0, max)
}
fn lang(p: &str) -> String {
    let e = Path::new(p)
        .extension()
        .and_then(|x| x.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    match e.as_str() {
        "rs" => "rust",
        "ts" | "tsx" => "typescript",
        "js" | "jsx" | "mjs" | "cjs" => "javascript",
        "json" => "json",
        "css" | "scss" => "css",
        "vue" | "html" => "html",
        "md" => "markdown",
        "toml" => "ini",
        "yaml" | "yml" => "yaml",
        "ps1" => "powershell",
        "py" => "python",
        "sql" => "sql",
        "xml" => "xml",
        _ => "plaintext",
    }
    .into()
}
#[tauri::command]
fn vertex_runtime_info() -> Result<RuntimeInfo, String> {
    let r = root()?;
    let crates = r.join("crates");
    let reports = r.join("_vertex_reports");
    let names = fs::read_dir(&crates)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.file_name().to_string_lossy().to_ascii_lowercase())
        .collect::<Vec<_>>();
    let mut rep = fs::read_dir(&reports)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| {
            p.extension()
                .and_then(|x| x.to_str())
                .is_some_and(|x| x.eq_ignore_ascii_case("json"))
        })
        .collect::<Vec<_>>();
    rep.sort_by_key(|p| std::cmp::Reverse(fs::metadata(p).and_then(|m| m.modified()).ok()));
    rep.truncate(30);
    Ok(RuntimeInfo {
        core_root: norm(&r),
        cargo_workspace: r.join("Cargo.toml").is_file(),
        mothership: names.iter().any(|n| n.contains("mothership")),
        autonomous_loop: has_named(&crates, "autonomous_mission_loop.rs", 5),
        real_hyper_agent: has_named(&crates, "real_hyper_agent_runtime.rs", 5),
        bridge: names.iter().any(|n| n.contains("bridge")),
        recent_reports: rep.iter().map(|p| norm(p)).collect(),
    })
}
#[tauri::command]
fn vertex_project_tree(depth: Option<usize>) -> Result<String, String> {
    let r = root()?;
    let mut out = Vec::new();
    tree(&r, &r, 0, depth.unwrap_or(5).clamp(1, 8), &mut out)?;
    Ok(out.join("\n"))
}
#[tauri::command]
fn vertex_read_file(path: String) -> Result<FileSnapshot, String> {
    let r = root()?;
    let p = existing(&r, &path)?;
    let md = fs::metadata(&p).map_err(|e| e.to_string())?;
    if !md.is_file() {
        return Err("not a file".into());
    }
    if md.len() > MAX_FILE {
        return Err("file exceeds 4MiB".into());
    }
    let b = fs::read(&p).map_err(|e| e.to_string())?;
    let c = String::from_utf8(b).map_err(|_| "not UTF-8".to_string())?;
    Ok(FileSnapshot {
        path: path.clone(),
        language: lang(&path),
        bytes: c.len(),
        lines: c.lines().count().max(1),
        content: c,
    })
}
#[tauri::command]
fn vertex_write_file(input: WriteInput) -> Result<WriteResult, String> {
    let r = root()?;
    if input.content.len() as u64 > MAX_FILE {
        return Err("file exceeds 4MiB".into());
    }
    let p = writable(&r, &input.path)?;
    if let Some(d) = p.parent() {
        fs::create_dir_all(d).map_err(|e| e.to_string())?
    }
    fs::write(&p, input.content.as_bytes()).map_err(|e| e.to_string())?;
    Ok(WriteResult {
        path: input.path,
        bytes: input.content.len(),
        lines: input.content.lines().count().max(1),
    })
}
#[tauri::command]
async fn vertex_run_action(action: String) -> Result<ActionResult, String> {
    let r = root()?;
    let (exe, args, ms) = match action.as_str() {
        "cargo_fmt" => ("cargo", vec!["fmt", "--all"], 120000),
        "cargo_check" => (
            "cargo",
            vec!["check", "--workspace", "--all-targets"],
            600000,
        ),
        "cargo_test" => ("cargo", vec!["test", "--workspace"], 900000),
        "git_status" => ("git", vec!["status", "--short", "--branch"], 60000),
        "git_diff" => ("git", vec!["diff", "--"], 60000),
        _ => return Err("unsupported fixed control action".into()),
    };
    let start = Instant::now();
    let mut c = Command::new(exe);
    c.args(&args)
        .current_dir(&r)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    match timeout(Duration::from_millis(ms), c.output()).await {
        Ok(Ok(o)) => Ok(ActionResult {
            action,
            executable: exe.into(),
            args: args.iter().map(|x| x.to_string()).collect(),
            success: o.status.success(),
            timed_out: false,
            exit_code: o.status.code(),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
            duration_ms: start.elapsed().as_millis(),
        }),
        Ok(Err(e)) => Err(e.to_string()),
        Err(_) => Ok(ActionResult {
            action,
            executable: exe.into(),
            args: args.iter().map(|x| x.to_string()).collect(),
            success: false,
            timed_out: true,
            exit_code: None,
            stdout: String::new(),
            stderr: format!("timeout after {ms}ms"),
            duration_ms: start.elapsed().as_millis(),
        }),
    }
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]

// VERTEX LIVE SESSION IPC V1
fn vertex_runtime_directory() -> Result<std::path::PathBuf, String> {
    Ok(root()?.join("_vertex_runtime"))
}

#[tauri::command]
fn vertex_live_session_latest() -> Result<String, String> {
    let path = vertex_runtime_directory()?.join("live_session_latest.json");

    if !path.is_file() {
        return Ok(String::new());
    }

    std::fs::read_to_string(&path)
        .map_err(|error| format!("cannot read live session latest: {error}"))
}

#[tauri::command]
fn vertex_live_session_tail(limit: Option<usize>) -> Result<Vec<String>, String> {
    let path = vertex_runtime_directory()?.join("live_session.ndjson");

    if !path.is_file() {
        return Ok(Vec::new());
    }

    let content = std::fs::read_to_string(&path)
        .map_err(|error| format!("cannot read live session timeline: {error}"))?;

    let limit = limit.unwrap_or(40).clamp(1, 500);
    let lines = content.lines().collect::<Vec<_>>();
    let start = lines.len().saturating_sub(limit);

    Ok(lines[start..]
        .iter()
        .map(|line| (*line).to_owned())
        .collect())
}
// END VERTEX LIVE SESSION IPC V1

// VERTEX HUB IPC V1
#[tauri::command]
fn vertex_hub_registry() -> Result<String, String> {
    let hub = root()?.join("vertex-hub");

    vsa_vertex_hub::validate_registry(&hub)?;

    std::fs::read_to_string(hub.join("registry.json"))
        .map_err(|error| format!("cannot read validated Hub registry: {error}"))
}
// END VERTEX HUB IPC V1

// VERTEX HUB HOT INSTALL IPC V1
fn vertex_hub_runtime_root() -> Result<std::path::PathBuf, String> {
    Ok(root()?.join("_vertex_hub_runtime"))
}

fn vertex_hub_source_root() -> Result<std::path::PathBuf, String> {
    Ok(root()?.join("vertex-hub"))
}

#[tauri::command]
fn vertex_hub_runtime_state() -> Result<String, String> {
    let state = vsa_vertex_hub::load_hub_runtime_state(&vertex_hub_runtime_root()?)?;

    serde_json::to_string(&state)
        .map_err(|error| format!("cannot serialize Hub runtime state: {error}"))
}

#[tauri::command]
fn vertex_hub_install(package_id: String, version: String) -> Result<String, String> {
    let mutation = vsa_vertex_hub::hub_runtime_install(
        &vertex_hub_source_root()?,
        &vertex_hub_runtime_root()?,
        &package_id,
        &version,
    )?;

    serde_json::to_string(&mutation)
        .map_err(|error| format!("cannot serialize Hub install result: {error}"))
}

#[tauri::command]
fn vertex_hub_set_enabled(
    package_id: String,
    version: String,
    enabled: bool,
) -> Result<String, String> {
    let mutation = vsa_vertex_hub::hub_runtime_set_enabled(
        &vertex_hub_runtime_root()?,
        &package_id,
        &version,
        enabled,
    )?;

    serde_json::to_string(&mutation)
        .map_err(|error| format!("cannot serialize Hub enable result: {error}"))
}

#[tauri::command]
fn vertex_hub_uninstall(package_id: String, version: String) -> Result<String, String> {
    let mutation =
        vsa_vertex_hub::hub_runtime_uninstall(&vertex_hub_runtime_root()?, &package_id, &version)?;

    serde_json::to_string(&mutation)
        .map_err(|error| format!("cannot serialize Hub uninstall result: {error}"))
}
// END VERTEX HUB HOT INSTALL IPC V1
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            vertex_hub_runtime_state,
            vertex_hub_install,
            vertex_hub_set_enabled,
            vertex_hub_uninstall,
            vertex_hub_registry,
            vertex_live_session_latest,
            vertex_live_session_tail,
            vertex_runtime_info,
            vertex_project_tree,
            vertex_read_file,
            vertex_write_file,
            vertex_run_action
        ])
        .run(tauri::generate_context!())
        .expect("failed to run VSA desktop shell")
}
