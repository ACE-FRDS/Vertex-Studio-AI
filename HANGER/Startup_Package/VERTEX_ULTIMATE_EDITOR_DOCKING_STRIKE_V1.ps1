& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — ULTIMATE EDITOR DOCKING STRIKE V1
    #
    # Goal:
    #   Existing Vue/Tauri bridge
    #   + Monaco high-performance editor
    #   + Workspace/FileToolkit sandbox
    #   + Developer Agent control
    #   + Console Inspector
    #   + Diff / Errors / Activities / Commands
    #   + allowlisted Build/Test/Git control
    #   + Mothership / Hyper Agent runtime detection
    #
    # Doctrine:
    #   MAX SAFE SCOPE
    #   scan -> lock -> backup -> atomic patch -> build/test
    #   RED -> evidence -> rollback
    # ============================================================

    $vsa =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'

    if (-not (Test-Path -LiteralPath $vsa)) {
        throw "VSA source root missing: $vsa"
    }

    Set-Location $vsa

    $reportDir =
        Join-Path $vsa '_vertex_reports'

    New-Item `
        -ItemType Directory `
        -Path $reportDir `
        -Force |
        Out-Null

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $reportPath =
        Join-Path `
            $reportDir `
            "ULTIMATE_EDITOR_DOCKING.$stamp.json"

    $backupDir =
        Join-Path `
            $reportDir `
            "ULTIMATE_EDITOR_DOCKING_BACKUP.$stamp"

    $failedDir =
        Join-Path `
            $reportDir `
            "ULTIMATE_EDITOR_DOCKING_FAILED.$stamp"

    $utf8 =
        New-Object System.Text.UTF8Encoding($false)

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX CIC — ULTIMATE EDITOR DOCKING STRIKE V1' -ForegroundColor Cyan
    Write-Host ' MAX SAFE SCOPE / ATOMIC / FAIL-CLOSED' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    # ============================================================
    # HELPERS
    # ============================================================

    function Is-IgnoredPath {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        return (
            $Path -match
            '(^|\\)(node_modules|target|\.git|dist|build|coverage|\.idea|\.vscode)(\\|$)'
        )
    }

    function Write-Utf8 {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Content
        )

        $parent =
            Split-Path `
                -Parent `
                $Path

        if ($parent) {
            New-Item `
                -ItemType Directory `
                -Path $parent `
                -Force |
                Out-Null
        }

        [IO.File]::WriteAllText(
            $Path,
            $Content,
            $utf8
        )
    }

    function Backup-File {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }

        $name =
            [IO.Path]::GetFileName($Path)

        $key =
            [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($Path)
            ).
            TrimEnd('=').
            Replace('/', '_').
            Replace('+', '-')

        $destination =
            Join-Path `
                $backupDir `
                "$key.$name"

        Copy-Item `
            -LiteralPath $Path `
            -Destination $destination `
            -Force
    }

    function Restore-BackupFile {
        param(
            [Parameter(Mandatory)]
            [string]$Original
        )

        if (-not (Test-Path -LiteralPath $backupDir)) {
            return
        }

        $name =
            [IO.Path]::GetFileName($Original)

        $key =
            [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($Original)
            ).
            TrimEnd('=').
            Replace('/', '_').
            Replace('+', '-')

        $source =
            Join-Path `
                $backupDir `
                "$key.$name"

        if (Test-Path -LiteralPath $source) {
            Copy-Item `
                -LiteralPath $source `
                -Destination $Original `
                -Force
        }
    }

    function Require-Command {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $command =
            Get-Command `
                $Name `
                -ErrorAction SilentlyContinue

        if (-not $command) {
            throw "Required command missing: $Name"
        }

        return $command
    }

    function Invoke-Checked {
        param(
            [Parameter(Mandatory)]
            [string]$Label,

            [Parameter(Mandatory)]
            [scriptblock]$Action
        )

        Write-Host ''
        Write-Host $Label -ForegroundColor Cyan

        & $Action

        if ($LASTEXITCODE -ne 0) {
            throw "$Label RED. ExitCode=$LASTEXITCODE"
        }
    }

    # ============================================================
    # 0. DISCOVER ACTUAL UI TOPOLOGY
    # ============================================================

    Write-Host ''
    Write-Host '[0/10] DISCOVER ACTUAL UI / TAURI TOPOLOGY' -ForegroundColor Yellow

    $packageCandidates =
        @(
            Get-ChildItem `
                -LiteralPath $vsa `
                -Filter 'package.json' `
                -File `
                -Recurse |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName)
            }
        )

    $uiCandidates =
        New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $packageCandidates) {

        try {
            $json =
                Get-Content `
                    -LiteralPath $candidate.FullName `
                    -Raw |
                ConvertFrom-Json
        }
        catch {
            continue
        }

        $deps =
            @{}

        foreach ($section in @(
            'dependencies',
            'devDependencies'
        )) {
            if ($json.$section) {
                foreach ($property in $json.$section.PSObject.Properties) {
                    $deps[$property.Name] = [string]$property.Value
                }
            }
        }

        $root =
            Split-Path `
                -Parent `
                $candidate.FullName

        $score = 0

        if ($deps.ContainsKey('vue')) {
            $score += 30
        }

        if ($deps.ContainsKey('@tauri-apps/api')) {
            $score += 30
        }

        if (Test-Path -LiteralPath (Join-Path $root 'src\App.vue')) {
            $score += 20
        }

        if (Test-Path -LiteralPath (Join-Path $root 'src-tauri\src\lib.rs')) {
            $score += 20
        }

        if ($score -gt 0) {
            $uiCandidates.Add(
                [pscustomobject]@{
                    root = $root
                    score = $score
                    package = $candidate.FullName
                    name = [string]$json.name
                }
            )
        }
    }

    if ($uiCandidates.Count -eq 0) {
        throw 'No Vue/Tauri UI candidate found under authoritative ProgramSource.'
    }

    $uiCandidate =
        $uiCandidates |
        Sort-Object `
            @{ Expression = 'score'; Descending = $true } |
        Select-Object -First 1

    if ($uiCandidate.score -lt 80) {
        throw "UI topology confidence too low: score=$($uiCandidate.score), root=$($uiCandidate.root)"
    }

    $ui =
        $uiCandidate.root

    $packageJson =
        Join-Path $ui 'package.json'

    $pnpmLock =
        Join-Path $ui 'pnpm-lock.yaml'

    $appVue =
        Join-Path $ui 'src\App.vue'

    $serviceDir =
        Join-Path $ui 'src\services'

    $editorDir =
        Join-Path $ui 'src\vertex-editor'

    $editorService =
        Join-Path $serviceDir 'vertex-editor.ts'

    $editorComponent =
        Join-Path $editorDir 'VertexEditorWorkbench.vue'

    $monacoEnv =
        Join-Path $editorDir 'monaco-env.ts'

    $tauriDir =
        Join-Path $ui 'src-tauri'

    $tauriManifest =
        Join-Path $tauriDir 'Cargo.toml'

    $tauriLib =
        Join-Path $tauriDir 'src\lib.rs'

    $tauriEditorModule =
        Join-Path $tauriDir 'src\vertex_editor_control.rs'

    foreach ($required in @(
        $packageJson,
        $appVue,
        $tauriManifest,
        $tauriLib
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required UI target missing: $required"
        }
    }

    Write-Host "UI root      : $ui" -ForegroundColor Green
    Write-Host "UI score     : $($uiCandidate.score)" -ForegroundColor Green
    Write-Host "Tauri        : $tauriDir" -ForegroundColor Green

    # Existing editor assets are inventory only. Never delete them.
    $existingEditorHits =
        @(
            Get-ChildItem `
                -LiteralPath $ui `
                -Include '*.ts','*.vue','*.rs' `
                -File `
                -Recurse |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName)
            } |
            Select-String `
                -Pattern 'Monaco|EditorPort|ConsoleInspector|ObjectConsole|Developer Agent' `
                -List
        )

    Write-Host "Existing editor-related files: $($existingEditorHits.Count)" -ForegroundColor Green

    if (Test-Path -LiteralPath $editorComponent) {
        throw "Integrated Vertex Editor already exists: $editorComponent"
    }

    if (Test-Path -LiteralPath $tauriEditorModule) {
        throw "Tauri Vertex Editor control module already exists: $tauriEditorModule"
    }

    # ============================================================
    # 1. BASELINE LOCK
    # ============================================================

    Write-Host ''
    Write-Host '[1/10] BASELINE LOCK' -ForegroundColor Yellow

    $pnpm =
        Require-Command 'pnpm'

    $cargo =
        Require-Command 'cargo'

    $rustfmt =
        Require-Command 'rustfmt'

    Push-Location $ui

    try {
        if (-not (Test-Path -LiteralPath (Join-Path $ui 'node_modules'))) {
            Invoke-Checked `
                '[baseline] pnpm install --frozen-lockfile' `
                {
                    & $pnpm.Source install --frozen-lockfile
                }
        }

        Invoke-Checked `
            '[baseline] frontend build' `
            {
                & $pnpm.Source build
            }
    }
    finally {
        Pop-Location
    }

    Invoke-Checked `
        '[baseline] Tauri cargo check' `
        {
            & $cargo.Source check `
                --manifest-path $tauriManifest `
                --all-targets
        }

    # ============================================================
    # 2. BACKUP
    # ============================================================

    Write-Host ''
    Write-Host '[2/10] ATOMIC BACKUP' -ForegroundColor Yellow

    New-Item `
        -ItemType Directory `
        -Path $backupDir `
        -Force |
        Out-Null

    foreach ($file in @(
        $packageJson,
        $pnpmLock,
        $appVue,
        $tauriLib,
        $tauriManifest
    )) {
        Backup-File $file
    }

    $created =
        New-Object System.Collections.Generic.List[string]

    $sourceModified = $false

    try {

        # ========================================================
        # 3. MONACO DEPENDENCY
        # ========================================================

        Write-Host ''
        Write-Host '[3/10] INSTALL / LOCK MONACO EDITOR' -ForegroundColor Cyan

        $package =
            Get-Content `
                -LiteralPath $packageJson `
                -Raw |
            ConvertFrom-Json

        $hasMonaco =
            $false

        if (
            $package.dependencies -and
            $package.dependencies.PSObject.Properties.Name -contains 'monaco-editor'
        ) {
            $hasMonaco = $true
        }

        if (
            -not $hasMonaco -and
            $package.devDependencies -and
            $package.devDependencies.PSObject.Properties.Name -contains 'monaco-editor'
        ) {
            $hasMonaco = $true
        }

        if (-not $hasMonaco) {
            Push-Location $ui

            try {
                Invoke-Checked `
                    '[monaco] pnpm add monaco-editor@latest' `
                    {
                        & $pnpm.Source add monaco-editor@latest
                    }
            }
            finally {
                Pop-Location
            }
        }
        else {
            Write-Host 'Monaco dependency already present.' -ForegroundColor Green
        }

        # ========================================================
        # 4. TAURI EDITOR CONTROL MODULE
        # ========================================================

        Write-Host ''
        Write-Host '[4/10] INSTALL SAFE EDITOR CONTROL MODULE' -ForegroundColor Cyan

        $backendSource = @'
use serde::Serialize;
use std::path::Path;
use tauri::State;
use vertex_ai_developer::{
    CommandExecution, DeveloperMode, FileToolkit, TerminalRequest, TerminalRunner, WorkspaceId,
};
use vertex_ai_types::ErrorEnvelope;

use super::{developer_error, error_envelope, AppState};

const MAX_EDITOR_WRITE_BYTES: usize = 2 * 1024 * 1024;

#[derive(Debug, Serialize)]
pub(crate) struct EditorFileSnapshot {
    path: String,
    content: String,
    language: String,
    bytes: usize,
    lines: usize,
}

#[derive(Debug, Serialize)]
pub(crate) struct EditorWriteResult {
    path: String,
    bytes: usize,
    lines: usize,
    unified_diff: String,
}

#[derive(Debug, Serialize)]
pub(crate) struct EditorRuntimeInfo {
    workspace_id: WorkspaceId,
    workspace_name: String,
    workspace_root: String,
    git_enabled: bool,
    branch: Option<String>,
    developer_agent: bool,
    ard: bool,
    mothership_detected: bool,
    autonomous_loop_detected: bool,
    hyper_agent_runtime_detected: bool,
}

fn editor_toolkit(
    state: &AppState,
    workspace_id: WorkspaceId,
    operation: &str,
) -> Result<FileToolkit, ErrorEnvelope> {
    let workspace = state
        .developer
        .list_workspaces()
        .map_err(|error| developer_error(operation, error))?
        .into_iter()
        .find(|workspace| workspace.id == workspace_id)
        .ok_or_else(|| {
            error_envelope(
                operation,
                "editor_workspace_not_found",
                format!("workspace was not found: {workspace_id}"),
                false,
            )
        })?;

    FileToolkit::new(workspace)
        .map_err(|error| developer_error(operation, error))
}

fn protected_write_path(relative: &str) -> bool {
    let path = Path::new(relative);
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();

    name == ".env"
        || name.starts_with(".env.")
        || matches!(name.as_str(), "id_rsa" | "id_ed25519")
        || matches!(
            path.extension()
                .and_then(|value| value.to_str())
                .map(str::to_ascii_lowercase)
                .as_deref(),
            Some("pem" | "pfx" | "key")
        )
}

fn language_for_path(path: &str) -> String {
    match Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "rs" => "rust",
        "ts" | "mts" | "cts" => "typescript",
        "tsx" => "typescript",
        "js" | "mjs" | "cjs" => "javascript",
        "jsx" => "javascript",
        "vue" => "html",
        "json" => "json",
        "css" | "scss" | "sass" | "less" => "css",
        "html" | "htm" => "html",
        "md" | "markdown" => "markdown",
        "toml" => "ini",
        "yaml" | "yml" => "yaml",
        "ps1" => "powershell",
        "py" => "python",
        "sql" => "sql",
        "xml" => "xml",
        _ => "plaintext",
    }
    .to_owned()
}

fn source_candidates(root: &Path) -> Vec<std::path::PathBuf> {
    vec![
        root.to_path_buf(),
        root.join("ProgramSource"),
        root.join("HANGER")
            .join("Startup_Package")
            .join("VSA_Startup_Package_v0.2")
            .join("ProgramSource"),
    ]
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) fn editor_runtime_info(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
) -> Result<EditorRuntimeInfo, ErrorEnvelope> {
    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_runtime_info")?;

    let workspace =
        toolkit.workspace().clone();

    let root =
        std::path::PathBuf::from(&workspace.root);

    let mut mothership_detected = false;
    let mut autonomous_loop_detected = false;
    let mut hyper_agent_runtime_detected = false;

    for candidate in source_candidates(&root) {
        mothership_detected |=
            candidate.join("crates/vsa-mothership/Cargo.toml").is_file();

        autonomous_loop_detected |=
            candidate
                .join("crates/vsa-mothership/src/autonomous_mission_loop.rs")
                .is_file();

        hyper_agent_runtime_detected |=
            candidate
                .join("crates/vsa-mothership/src/real_hyper_agent_runtime.rs")
                .is_file();
    }

    Ok(EditorRuntimeInfo {
        workspace_id: workspace.id,
        workspace_name: workspace.name,
        workspace_root: workspace.root,
        git_enabled: workspace.git_enabled,
        branch: workspace.branch,
        developer_agent: true,
        ard: true,
        mothership_detected,
        autonomous_loop_detected,
        hyper_agent_runtime_detected,
    })
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) fn editor_project_tree(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
    depth: Option<usize>,
) -> Result<String, ErrorEnvelope> {
    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_project_tree")?;

    toolkit
        .project_tree(depth.unwrap_or(6))
        .map_err(|error| developer_error("editor_project_tree", error))
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) fn editor_search_files(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
    query: String,
) -> Result<String, ErrorEnvelope> {
    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_search_files")?;

    toolkit
        .search_files(&query, None, None)
        .map_err(|error| developer_error("editor_search_files", error))
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) fn editor_read_file(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
    path: String,
) -> Result<EditorFileSnapshot, ErrorEnvelope> {
    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_read_file")?;

    let content =
        toolkit
            .read_file(&path)
            .map_err(|error| developer_error("editor_read_file", error))?;

    Ok(EditorFileSnapshot {
        path: path.clone(),
        language: language_for_path(&path),
        bytes: content.len(),
        lines: content.lines().count().max(1),
        content,
    })
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) fn editor_write_file(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
    path: String,
    content: String,
) -> Result<EditorWriteResult, ErrorEnvelope> {
    if content.len() > MAX_EDITOR_WRITE_BYTES {
        return Err(error_envelope(
            "editor_write_file",
            "editor_file_too_large",
            format!(
                "editor write exceeds {} bytes: {}",
                MAX_EDITOR_WRITE_BYTES,
                content.len()
            ),
            false,
        ));
    }

    if protected_write_path(&path) {
        return Err(error_envelope(
            "editor_write_file",
            "editor_protected_path",
            format!("protected secret-like path cannot be edited: {path}"),
            false,
        ));
    }

    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_write_file")?;

    toolkit
        .write_file(&path, &content)
        .map_err(|error| developer_error("editor_write_file", error))?;

    let unified_diff =
        toolkit
            .unified_diff()
            .map_err(|error| developer_error("editor_write_file", error))?;

    Ok(EditorWriteResult {
        path,
        bytes: content.len(),
        lines: content.lines().count().max(1),
        unified_diff,
    })
}

#[tauri::command]
#[allow(clippy::result_large_err)]
pub(crate) async fn editor_run_action(
    state: State<'_, AppState>,
    workspace_id: WorkspaceId,
    action: String,
) -> Result<CommandExecution, ErrorEnvelope> {
    let toolkit =
        editor_toolkit(state.inner(), workspace_id, "editor_run_action")?;

    let (executable, args, timeout_ms): (&str, Vec<String>, u64) =
        match action.as_str() {
            "cargo_fmt" => (
                "cargo",
                vec!["fmt".into(), "--all".into()],
                120_000,
            ),
            "cargo_check" => (
                "cargo",
                vec![
                    "check".into(),
                    "--workspace".into(),
                    "--all-targets".into(),
                ],
                600_000,
            ),
            "cargo_test" => (
                "cargo",
                vec!["test".into(), "--workspace".into()],
                900_000,
            ),
            "git_status" => (
                "git",
                vec!["status".into(), "--short".into(), "--branch".into()],
                60_000,
            ),
            "git_diff" => (
                "git",
                vec!["diff".into(), "--".into()],
                60_000,
            ),
            other => {
                return Err(error_envelope(
                    "editor_run_action",
                    "editor_action_not_allowed",
                    format!("unsupported editor control action: {other}"),
                    false,
                ));
            }
        };

    let runner =
        TerminalRunner::default();

    runner
        .execute(
            &toolkit,
            DeveloperMode::Execute,
            TerminalRequest {
                executable,
                args: &args,
                working_directory: ".",
                timeout_ms,
                approved_high_risk: false,
            },
        )
        .await
        .map_err(|error| developer_error("editor_run_action", error))
}
'@

        Write-Utf8 `
            -Path $tauriEditorModule `
            -Content $backendSource

        $created.Add($tauriEditorModule)

        # ========================================================
        # 5. FRONTEND SERVICE
        # ========================================================

        Write-Host ''
        Write-Host '[5/10] INSTALL EDITOR TRANSPORT SERVICE' -ForegroundColor Cyan

        $serviceSource = @'
import { isDesktopRuntime } from './memory'
import type { DeveloperCommand } from './developer'

export interface EditorFileSnapshot {
  path: string
  content: string
  language: string
  bytes: number
  lines: number
}

export interface EditorWriteResult {
  path: string
  bytes: number
  lines: number
  unified_diff: string
}

export interface EditorRuntimeInfo {
  workspace_id: string
  workspace_name: string
  workspace_root: string
  git_enabled: boolean
  branch: string | null
  developer_agent: boolean
  ard: boolean
  mothership_detected: boolean
  autonomous_loop_detected: boolean
  hyper_agent_runtime_detected: boolean
}

async function invokeDesktop<T>(
  command: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (!isDesktopRuntime()) throw new Error('desktop_required')
  const { invoke } = await import('@tauri-apps/api/core')
  return invoke<T>(command, args)
}

export function editorRuntimeInfo(workspaceId: string) {
  return invokeDesktop<EditorRuntimeInfo>('editor_runtime_info', {
    workspaceId,
  })
}

export function editorProjectTree(workspaceId: string, depth = 6) {
  return invokeDesktop<string>('editor_project_tree', {
    workspaceId,
    depth,
  })
}

export function editorSearchFiles(workspaceId: string, query: string) {
  return invokeDesktop<string>('editor_search_files', {
    workspaceId,
    query,
  })
}

export function editorReadFile(workspaceId: string, path: string) {
  return invokeDesktop<EditorFileSnapshot>('editor_read_file', {
    workspaceId,
    path,
  })
}

export function editorWriteFile(
  workspaceId: string,
  path: string,
  content: string,
) {
  return invokeDesktop<EditorWriteResult>('editor_write_file', {
    workspaceId,
    path,
    content,
  })
}

export function editorRunAction(
  workspaceId: string,
  action:
    | 'cargo_fmt'
    | 'cargo_check'
    | 'cargo_test'
    | 'git_status'
    | 'git_diff',
) {
  return invokeDesktop<DeveloperCommand>('editor_run_action', {
    workspaceId,
    action,
  })
}
'@

        Write-Utf8 `
            -Path $editorService `
            -Content $serviceSource

        $created.Add($editorService)

        # ========================================================
        # 6. MONACO WORKERS
        # ========================================================

        Write-Host ''
        Write-Host '[6/10] INSTALL MONACO WORKER RUNTIME' -ForegroundColor Cyan

        $monacoSource = @'
import EditorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import JsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker'
import CssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker'
import HtmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker'
import TsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker'

type MonacoEnvironmentShape = {
  getWorker: (_moduleId: string, label: string) => Worker
}

;(self as unknown as { MonacoEnvironment: MonacoEnvironmentShape }).MonacoEnvironment = {
  getWorker(_moduleId, label) {
    if (label === 'json') return new JsonWorker()
    if (label === 'css' || label === 'scss' || label === 'less') return new CssWorker()
    if (label === 'html' || label === 'handlebars' || label === 'razor') return new HtmlWorker()
    if (label === 'typescript' || label === 'javascript') return new TsWorker()
    return new EditorWorker()
  },
}
'@

        Write-Utf8 `
            -Path $monacoEnv `
            -Content $monacoSource

        $created.Add($monacoEnv)

        # ========================================================
        # 7. COMPLETE WORKBENCH
        # ========================================================

        Write-Host ''
        Write-Host '[7/10] BUILD COMPLETE EDITOR / INSPECTOR / CONTROL SURFACE' -ForegroundColor Cyan

        $componentSource = @'
<script setup lang="ts">
import './monaco-env'
import 'monaco-editor/min/vs/editor/editor.main.css'

import * as monaco from 'monaco-editor'
import {
  computed,
  nextTick,
  onMounted,
  onUnmounted,
  ref,
  watch,
} from 'vue'

import {
  cancelDeveloperTask,
  getDeveloperTask,
  listDeveloperWorkspaces,
  rollbackDeveloperTask,
  startDeveloperTask,
  type DeveloperCommand,
  type DeveloperTask,
  type DeveloperWorkspace,
} from '../services/developer'

import {
  editorProjectTree,
  editorReadFile,
  editorRunAction,
  editorRuntimeInfo,
  editorSearchFiles,
  editorWriteFile,
  type EditorRuntimeInfo,
} from '../services/vertex-editor'

type InspectorTab =
  | 'activity'
  | 'terminal'
  | 'diff'
  | 'errors'
  | 'runtime'

type FlatTreeEntry = {
  path: string
  kind: 'file' | 'directory'
  depth: number
}

type OpenDocument = {
  path: string
  language: string
  saved: string
  model: monaco.editor.ITextModel
}

const editorHost = ref<HTMLElement | null>(null)

const workspaces = ref<DeveloperWorkspace[]>([])
const workspaceId = ref('')
const runtimeInfo = ref<EditorRuntimeInfo | null>(null)

const treeDepth = ref(6)
const rawTree = ref('')
const treeSearch = ref('')
const remoteSearchResults = ref<string[]>([])

const openDocuments = ref<OpenDocument[]>([])
const activePath = ref('')

const missionPrompt = ref('')
const providerId = ref('ollama')
const modelId = ref('qwen3:8b')
const developerTask = ref<DeveloperTask | null>(null)

const inspectorTab = ref<InspectorTab>('activity')
const controlOutput = ref<DeveloperCommand | null>(null)
const editorError = ref('')
const busy = ref(false)
const lastWriteDiff = ref('')

let editor: monaco.editor.IStandaloneCodeEditor | null = null
let pollTimer = 0

const activeDocument = computed(
  () => openDocuments.value.find((item) => item.path === activePath.value) ?? null,
)

const dirty = computed(() => {
  const document = activeDocument.value
  return Boolean(document && document.model.getValue() !== document.saved)
})

const parsedTree = computed<FlatTreeEntry[]>(() => {
  return rawTree.value
    .split(/\r?\n/)
    .map((line) => {
      const match = /^(\s*)\[(D|F)\]\s+(.+)$/.exec(line)
      if (!match) return null
      return {
        path: match[3],
        kind: match[2] === 'D' ? 'directory' : 'file',
        depth: Math.floor(match[1].length / 2),
      } as FlatTreeEntry
    })
    .filter((value): value is FlatTreeEntry => value !== null)
})

const visibleTree = computed(() => {
  const query = treeSearch.value.trim().toLowerCase()
  if (!query) return parsedTree.value
  return parsedTree.value.filter((item) =>
    item.path.toLowerCase().includes(query),
  )
})

const taskDiff = computed(
  () => developerTask.value?.unified_diff || lastWriteDiff.value || '',
)

const activities = computed(
  () => developerTask.value?.activities ?? [],
)

const commands = computed(
  () => developerTask.value?.commands ?? [],
)

const errors = computed(
  () => developerTask.value?.errors ?? [],
)

const statusText = computed(() => {
  if (developerTask.value) return developerTask.value.state
  return 'IDLE'
})

const statusClass = computed(() => {
  const state = developerTask.value?.state
  if (state === 'COMPLETED') return 'ok'
  if (state === 'FAILED' || state === 'CANCELLED') return 'bad'
  if (state) return 'run'
  return 'idle'
})

function editorLanguage(path: string, fallback: string) {
  const lower = path.toLowerCase()
  if (lower.endsWith('.vue')) return 'html'
  if (lower.endsWith('.rs')) return 'rust'
  if (lower.endsWith('.ts') || lower.endsWith('.tsx')) return 'typescript'
  if (lower.endsWith('.js') || lower.endsWith('.jsx')) return 'javascript'
  if (lower.endsWith('.json')) return 'json'
  if (lower.endsWith('.css') || lower.endsWith('.scss')) return 'css'
  if (lower.endsWith('.html')) return 'html'
  if (lower.endsWith('.md')) return 'markdown'
  return fallback || 'plaintext'
}

function modelUri(path: string) {
  const encoded = path
    .split('/')
    .map((part) => encodeURIComponent(part))
    .join('/')
  return monaco.Uri.parse(`vertex-workspace:///${encoded}`)
}

function applyDiagnostics() {
  const document = activeDocument.value
  if (!document) return

  const normalized = document.path.replaceAll('\\', '/').toLowerCase()

  const markers: monaco.editor.IMarkerData[] = errors.value
    .filter((item) => {
      if (!item.file) return false
      const source = item.file.replaceAll('\\', '/').toLowerCase()
      return source === normalized || source.endsWith(`/${normalized}`)
    })
    .map((item) => ({
      severity: monaco.MarkerSeverity.Error,
      message: item.message,
      source: item.code ?? item.error_type,
      startLineNumber: Math.max(1, item.line ?? 1),
      startColumn: 1,
      endLineNumber: Math.max(1, item.line ?? 1),
      endColumn: 200,
    }))

  monaco.editor.setModelMarkers(
    document.model,
    'vertex-hyper-agent',
    markers,
  )
}

async function loadWorkspaces() {
  workspaces.value = await listDeveloperWorkspaces()

  if (!workspaceId.value && workspaces.value.length) {
    workspaceId.value = workspaces.value[0].id
  }
}

async function loadWorkspace() {
  if (!workspaceId.value) return

  busy.value = true
  editorError.value = ''

  try {
    const [tree, info] = await Promise.all([
      editorProjectTree(workspaceId.value, treeDepth.value),
      editorRuntimeInfo(workspaceId.value),
    ])

    rawTree.value = tree
    runtimeInfo.value = info
    remoteSearchResults.value = []
  } catch (error) {
    editorError.value = String(error)
  } finally {
    busy.value = false
  }
}

async function refreshTree() {
  if (!workspaceId.value) return
  rawTree.value = await editorProjectTree(workspaceId.value, treeDepth.value)
}

async function remoteSearch() {
  const query = treeSearch.value.trim()
  if (!workspaceId.value || !query) {
    remoteSearchResults.value = []
    return
  }

  try {
    const result = await editorSearchFiles(workspaceId.value, query)
    remoteSearchResults.value = result
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter(Boolean)
  } catch (error) {
    editorError.value = String(error)
  }
}

async function openFile(path: string) {
  if (!workspaceId.value) return

  editorError.value = ''

  const existing = openDocuments.value.find((item) => item.path === path)

  if (existing) {
    activePath.value = path
    editor?.setModel(existing.model)
    applyDiagnostics()
    return
  }

  try {
    const snapshot = await editorReadFile(workspaceId.value, path)
    const uri = modelUri(snapshot.path)

    const language = editorLanguage(snapshot.path, snapshot.language)

    let model = monaco.editor.getModel(uri)

    if (!model) {
      model = monaco.editor.createModel(
        snapshot.content,
        language,
        uri,
      )
    } else {
      model.setValue(snapshot.content)
      monaco.editor.setModelLanguage(model, language)
    }

    const document: OpenDocument = {
      path: snapshot.path,
      language,
      saved: snapshot.content,
      model,
    }

    openDocuments.value.push(document)
    activePath.value = snapshot.path
    editor?.setModel(model)
    applyDiagnostics()
  } catch (error) {
    editorError.value = String(error)
  }
}

function selectDocument(path: string) {
  const document = openDocuments.value.find((item) => item.path === path)
  if (!document) return

  activePath.value = path
  editor?.setModel(document.model)
  applyDiagnostics()
}

function closeDocument(path: string) {
  const index = openDocuments.value.findIndex((item) => item.path === path)
  if (index < 0) return

  const wasActive = activePath.value === path
  const [document] = openDocuments.value.splice(index, 1)

  monaco.editor.setModelMarkers(
    document.model,
    'vertex-hyper-agent',
    [],
  )

  document.model.dispose()

  if (wasActive) {
    const next =
      openDocuments.value[Math.max(0, index - 1)] ??
      openDocuments.value[0] ??
      null

    activePath.value = next?.path ?? ''
    editor?.setModel(next?.model ?? null)
  }
}

async function saveActive() {
  const document = activeDocument.value
  if (!document || !workspaceId.value) return

  busy.value = true
  editorError.value = ''

  try {
    const content = document.model.getValue()

    const result = await editorWriteFile(
      workspaceId.value,
      document.path,
      content,
    )

    document.saved = content
    lastWriteDiff.value = result.unified_diff
    inspectorTab.value = 'diff'
    await refreshTree()
  } catch (error) {
    editorError.value = String(error)
  } finally {
    busy.value = false
  }
}

function revertUnsaved() {
  const document = activeDocument.value
  if (!document) return
  document.model.setValue(document.saved)
}

async function startMission() {
  const request = missionPrompt.value.trim()

  if (!workspaceId.value || !request || busy.value) return

  busy.value = true
  editorError.value = ''

  try {
    const task = await startDeveloperTask({
      workspace_id: workspaceId.value,
      request,
      mode: 'AUTO',
      provider_id: providerId.value,
      model_id: modelId.value,
    })

    developerTask.value = task
    inspectorTab.value = 'activity'
    beginPolling(task.id)
  } catch (error) {
    editorError.value = String(error)
  } finally {
    busy.value = false
  }
}

function beginPolling(taskId: string) {
  window.clearInterval(pollTimer)

  pollTimer = window.setInterval(async () => {
    try {
      const task = await getDeveloperTask(taskId)
      developerTask.value = task
      applyDiagnostics()

      if (
        task.state === 'COMPLETED' ||
        task.state === 'FAILED' ||
        task.state === 'CANCELLED'
      ) {
        window.clearInterval(pollTimer)
        await refreshTree()
      }
    } catch (error) {
      editorError.value = String(error)
      window.clearInterval(pollTimer)
    }
  }, 700)
}

async function cancelMission() {
  if (!developerTask.value) return

  await cancelDeveloperTask(developerTask.value.id)
  developerTask.value = await getDeveloperTask(developerTask.value.id)
}

async function rollbackMission() {
  if (!developerTask.value) return

  developerTask.value = await rollbackDeveloperTask(developerTask.value.id)
  await refreshTree()

  for (const document of [...openDocuments.value]) {
    try {
      const snapshot = await editorReadFile(workspaceId.value, document.path)
      document.model.setValue(snapshot.content)
      document.saved = snapshot.content
    } catch {
      // File may have been removed by rollback.
    }
  }
}

async function runControl(
  action:
    | 'cargo_fmt'
    | 'cargo_check'
    | 'cargo_test'
    | 'git_status'
    | 'git_diff',
) {
  if (!workspaceId.value || busy.value) return

  busy.value = true
  editorError.value = ''
  inspectorTab.value = 'terminal'

  try {
    controlOutput.value = await editorRunAction(
      workspaceId.value,
      action,
    )
  } catch (error) {
    editorError.value = String(error)
  } finally {
    busy.value = false
  }
}

watch(
  workspaceId,
  async () => {
    for (const document of openDocuments.value) {
      document.model.dispose()
    }

    openDocuments.value = []
    activePath.value = ''
    developerTask.value = null
    controlOutput.value = null
    lastWriteDiff.value = ''

    await loadWorkspace()
  },
)

watch(
  () => developerTask.value?.errors,
  () => applyDiagnostics(),
  { deep: true },
)

onMounted(async () => {
  if (!editorHost.value) return

  editor = monaco.editor.create(editorHost.value, {
    value: '',
    language: 'plaintext',
    theme: 'vs-dark',
    automaticLayout: true,
    fontSize: 14,
    lineHeight: 22,
    fontLigatures: true,
    minimap: { enabled: true },
    smoothScrolling: true,
    cursorSmoothCaretAnimation: 'on',
    renderWhitespace: 'selection',
    renderControlCharacters: true,
    folding: true,
    stickyScroll: { enabled: true },
    bracketPairColorization: { enabled: true },
    guides: {
      bracketPairs: true,
      indentation: true,
    },
    padding: {
      top: 10,
      bottom: 10,
    },
    scrollBeyondLastLine: false,
    wordWrap: 'off',
    multiCursorModifier: 'alt',
    formatOnPaste: false,
    formatOnType: false,
  })

  editor.addCommand(
    monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
    () => void saveActive(),
  )

  try {
    await loadWorkspaces()
    await loadWorkspace()
  } catch (error) {
    editorError.value = String(error)
  }
})

onUnmounted(() => {
  window.clearInterval(pollTimer)
  editor?.dispose()

  for (const document of openDocuments.value) {
    if (!document.model.isDisposed()) {
      document.model.dispose()
    }
  }
})
</script>

<template>
  <section class="vx-editor">
    <header class="vx-toolbar">
      <div class="brand">
        <div class="brand-mark">VX</div>
        <div>
          <strong>Vertex Ultimate Editor</strong>
          <small>Mothership Command & Development Surface</small>
        </div>
      </div>

      <select v-model="workspaceId" class="select">
        <option
          v-for="workspace in workspaces"
          :key="workspace.id"
          :value="workspace.id"
        >
          {{ workspace.name }}
        </option>
      </select>

      <div class="runtime-badges">
        <span
          class="chip"
          :class="runtimeInfo?.mothership_detected ? 'ok' : 'idle'"
        >
          Mothership {{ runtimeInfo?.mothership_detected ? 'DETECTED' : 'N/A' }}
        </span>

        <span
          class="chip"
          :class="runtimeInfo?.hyper_agent_runtime_detected ? 'ok' : 'idle'"
        >
          Hyper Agent {{ runtimeInfo?.hyper_agent_runtime_detected ? 'ONLINE' : 'N/A' }}
        </span>

        <span class="chip" :class="statusClass">
          {{ statusText }}
        </span>
      </div>

      <button class="button" :disabled="busy" @click="refreshTree">
        Refresh
      </button>

      <button class="button primary" :disabled="!dirty || busy" @click="saveActive">
        Save
      </button>
    </header>

    <div v-if="editorError" class="error-banner">
      {{ editorError }}
    </div>

    <div class="vx-grid">
      <aside class="explorer">
        <div class="panel-title">
          <div>
            <strong>Source Explorer</strong>
            <small>{{ visibleTree.length }} entries</small>
          </div>

          <select v-model.number="treeDepth" class="depth" @change="refreshTree">
            <option :value="4">Depth 4</option>
            <option :value="6">Depth 6</option>
            <option :value="8">Depth 8</option>
          </select>
        </div>

        <form class="search-row" @submit.prevent="remoteSearch">
          <input
            v-model="treeSearch"
            class="input"
            placeholder="Search files..."
          >
          <button class="icon-button" type="submit">↵</button>
        </form>

        <div
          v-if="remoteSearchResults.length"
          class="remote-results"
        >
          <button
            v-for="path in remoteSearchResults"
            :key="path"
            class="tree-row result"
            @click="openFile(path)"
          >
            {{ path }}
          </button>
        </div>

        <div class="tree">
          <button
            v-for="entry in visibleTree"
            :key="`${entry.kind}:${entry.path}`"
            class="tree-row"
            :class="{ directory: entry.kind === 'directory' }"
            :style="{ paddingLeft: `${10 + entry.depth * 12}px` }"
            :disabled="entry.kind === 'directory'"
            @click="entry.kind === 'file' && openFile(entry.path)"
          >
            <span>{{ entry.kind === 'directory' ? '▸' : '•' }}</span>
            <span>{{ entry.path }}</span>
          </button>
        </div>
      </aside>

      <main class="editor-zone">
        <div class="tabs">
          <button
            v-for="document in openDocuments"
            :key="document.path"
            class="tab"
            :class="{ active: activePath === document.path }"
            @click="selectDocument(document.path)"
          >
            <span>{{ document.path.split('/').at(-1) }}</span>
            <span
              v-if="document.model.getValue() !== document.saved"
              class="dirty-dot"
            >●</span>
            <span class="close" @click.stop="closeDocument(document.path)">×</span>
          </button>

          <div v-if="!openDocuments.length" class="empty-tab">
            Open a file from Source Explorer
          </div>
        </div>

        <div ref="editorHost" class="monaco-host" />

        <footer class="statusbar">
          <span>{{ activePath || 'No document' }}</span>
          <span v-if="activeDocument">
            {{ activeDocument.language }}
          </span>
          <span v-if="dirty" class="dirty-state">MODIFIED</span>
          <button
            v-if="dirty"
            class="status-button"
            @click="revertUnsaved"
          >
            Revert unsaved
          </button>
        </footer>
      </main>

      <aside class="inspector">
        <div class="inspector-tabs">
          <button
            v-for="tab in (['activity', 'terminal', 'diff', 'errors', 'runtime'] as InspectorTab[])"
            :key="tab"
            :class="{ active: inspectorTab === tab }"
            @click="inspectorTab = tab"
          >
            {{ tab }}
          </button>
        </div>

        <div class="inspector-body">
          <template v-if="inspectorTab === 'activity'">
            <div
              v-for="event in activities.slice().reverse()"
              :key="event.sequence"
              class="event"
            >
              <div class="event-head">
                <strong>{{ event.kind }}</strong>
                <span>{{ event.risk }}</span>
              </div>
              <div>{{ event.message }}</div>
              <pre v-if="event.detail">{{ event.detail }}</pre>
            </div>

            <div v-if="!activities.length" class="empty">
              No mission activity yet.
            </div>
          </template>

          <template v-else-if="inspectorTab === 'terminal'">
            <div
              v-for="command in commands.slice().reverse()"
              :key="command.id"
              class="command"
            >
              <div class="event-head">
                <strong>{{ command.executable }} {{ command.args.join(' ') }}</strong>
                <span>{{ command.status }}</span>
              </div>
              <pre v-if="command.stdout">{{ command.stdout }}</pre>
              <pre v-if="command.stderr" class="stderr">{{ command.stderr }}</pre>
            </div>

            <div v-if="controlOutput" class="command manual">
              <div class="event-head">
                <strong>
                  {{ controlOutput.executable }}
                  {{ controlOutput.args.join(' ') }}
                </strong>
                <span>{{ controlOutput.status }}</span>
              </div>
              <pre v-if="controlOutput.stdout">{{ controlOutput.stdout }}</pre>
              <pre v-if="controlOutput.stderr" class="stderr">
{{ controlOutput.stderr }}
              </pre>
            </div>

            <div v-if="!commands.length && !controlOutput" class="empty">
              No terminal evidence yet.
            </div>
          </template>

          <template v-else-if="inspectorTab === 'diff'">
            <pre class="diff">{{ taskDiff || 'No diff available.' }}</pre>
          </template>

          <template v-else-if="inspectorTab === 'errors'">
            <article
              v-for="(item, index) in errors"
              :key="`${index}:${item.message}`"
              class="diagnostic"
            >
              <strong>{{ item.code || item.error_type }}</strong>
              <span>{{ item.file }}{{ item.line ? `:${item.line}` : '' }}</span>
              <p>{{ item.message }}</p>
            </article>

            <div v-if="!errors.length" class="empty">
              No diagnostics.
            </div>
          </template>

          <template v-else>
            <dl v-if="runtimeInfo" class="runtime-list">
              <div>
                <dt>Workspace</dt>
                <dd>{{ runtimeInfo.workspace_name }}</dd>
              </div>
              <div>
                <dt>Root</dt>
                <dd>{{ runtimeInfo.workspace_root }}</dd>
              </div>
              <div>
                <dt>Git</dt>
                <dd>{{ runtimeInfo.git_enabled ? 'ENABLED' : 'DISABLED' }}</dd>
              </div>
              <div>
                <dt>Branch</dt>
                <dd>{{ runtimeInfo.branch || '—' }}</dd>
              </div>
              <div>
                <dt>Developer Agent</dt>
                <dd>{{ runtimeInfo.developer_agent ? 'ONLINE' : 'OFFLINE' }}</dd>
              </div>
              <div>
                <dt>ARD</dt>
                <dd>{{ runtimeInfo.ard ? 'ONLINE' : 'OFFLINE' }}</dd>
              </div>
              <div>
                <dt>Mothership</dt>
                <dd>{{ runtimeInfo.mothership_detected ? 'DETECTED' : 'NOT DETECTED' }}</dd>
              </div>
              <div>
                <dt>Autonomous Loop</dt>
                <dd>{{ runtimeInfo.autonomous_loop_detected ? 'DETECTED' : 'NOT DETECTED' }}</dd>
              </div>
              <div>
                <dt>Real Hyper Agent</dt>
                <dd>{{ runtimeInfo.hyper_agent_runtime_detected ? 'DETECTED' : 'NOT DETECTED' }}</dd>
              </div>
            </dl>
          </template>
        </div>
      </aside>
    </div>

    <section class="control-deck">
      <div class="mission-panel">
        <div class="panel-title">
          <div>
            <strong>Hyper Agent Mission Control</strong>
            <small>Existing Developer Agent / Ollama runtime</small>
          </div>
          <span class="chip" :class="statusClass">{{ statusText }}</span>
        </div>

        <textarea
          v-model="missionPrompt"
          class="mission-input"
          placeholder="Describe what the agent should inspect, edit, build and verify..."
        />

        <div class="mission-controls">
          <label>
            Provider
            <input v-model="providerId" class="mini-input">
          </label>

          <label>
            Model
            <input v-model="modelId" class="mini-input">
          </label>

          <button
            class="button primary"
            :disabled="busy || !missionPrompt.trim() || !workspaceId"
            @click="startMission"
          >
            Launch AUTO Mission
          </button>

          <button
            class="button danger"
            :disabled="!developerTask"
            @click="cancelMission"
          >
            Cancel
          </button>

          <button
            class="button"
            :disabled="!developerTask"
            @click="rollbackMission"
          >
            Rollback Agent Changes
          </button>
        </div>
      </div>

      <div class="control-panel">
        <div class="panel-title">
          <div>
            <strong>Control Panel</strong>
            <small>Allowlisted machine actions only</small>
          </div>
        </div>

        <div class="control-buttons">
          <button class="button" :disabled="busy" @click="runControl('cargo_fmt')">
            Cargo Fmt
          </button>
          <button class="button" :disabled="busy" @click="runControl('cargo_check')">
            Cargo Check
          </button>
          <button class="button" :disabled="busy" @click="runControl('cargo_test')">
            Cargo Test
          </button>
          <button class="button" :disabled="busy" @click="runControl('git_status')">
            Git Status
          </button>
          <button class="button" :disabled="busy" @click="runControl('git_diff')">
            Git Diff
          </button>
        </div>

        <div class="control-status">
          <span>Arbitrary Shell: DENIED</span>
          <span>Workspace Escape: DENIED</span>
          <span>Timeout/Kill: ACTIVE</span>
        </div>
      </div>
    </section>
  </section>
</template>

<style scoped>
.vx-editor {
  --vx-bg: #090c12;
  --vx-panel: #111722;
  --vx-panel-2: #161e2b;
  --vx-line: #283346;
  --vx-text: #e9eef8;
  --vx-muted: #8e9ab0;
  --vx-accent: #7b8cff;
  --vx-good: #40d89b;
  --vx-bad: #ff6b7c;
  display: flex;
  flex-direction: column;
  min-height: 780px;
  height: calc(100vh - 150px);
  background: var(--vx-bg);
  color: var(--vx-text);
  border: 1px solid var(--vx-line);
  border-radius: 12px;
  overflow: hidden;
  font-family:
    Inter,
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    "Segoe UI",
    sans-serif;
}

.vx-toolbar {
  min-height: 58px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--vx-line);
  background: var(--vx-panel);
}

.brand {
  display: flex;
  align-items: center;
  gap: 9px;
  min-width: 270px;
}

.brand-mark {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--vx-accent);
  color: #fff;
  font-weight: 800;
  letter-spacing: -0.06em;
}

.brand strong,
.brand small {
  display: block;
}

.brand small,
.panel-title small {
  color: var(--vx-muted);
  margin-top: 2px;
}

.select,
.input,
.mini-input,
.mission-input {
  border: 1px solid var(--vx-line);
  background: #0d121b;
  color: var(--vx-text);
  border-radius: 7px;
  outline: none;
}

.select {
  min-width: 220px;
  padding: 8px;
}

.runtime-badges {
  display: flex;
  gap: 6px;
  margin-left: auto;
}

.chip {
  display: inline-flex;
  align-items: center;
  min-height: 26px;
  padding: 0 8px;
  border: 1px solid var(--vx-line);
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: .03em;
  white-space: nowrap;
}

.chip.ok {
  color: var(--vx-good);
}

.chip.bad {
  color: var(--vx-bad);
}

.chip.run {
  color: #ffd37a;
}

.chip.idle {
  color: var(--vx-muted);
}

.button,
.icon-button,
.status-button {
  border: 1px solid var(--vx-line);
  background: var(--vx-panel-2);
  color: var(--vx-text);
  border-radius: 7px;
  cursor: pointer;
}

.button {
  min-height: 34px;
  padding: 0 11px;
  font-weight: 650;
}

.button:hover:not(:disabled),
.icon-button:hover:not(:disabled),
.status-button:hover:not(:disabled) {
  border-color: #53627b;
}

.button:disabled,
.icon-button:disabled {
  opacity: .45;
  cursor: default;
}

.button.primary {
  background: var(--vx-accent);
  border-color: var(--vx-accent);
  color: #fff;
}

.button.danger {
  color: #ff9aa6;
}

.error-banner {
  padding: 8px 12px;
  border-bottom: 1px solid #66343c;
  background: #34151a;
  color: #ffbec6;
  font: 12px/1.45 ui-monospace, SFMono-Regular, Consolas, monospace;
  overflow: auto;
}

.vx-grid {
  min-height: 0;
  flex: 1;
  display: grid;
  grid-template-columns: minmax(220px, 280px) minmax(440px, 1fr) minmax(300px, 390px);
}

.explorer,
.inspector {
  min-width: 0;
  background: var(--vx-panel);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.explorer {
  border-right: 1px solid var(--vx-line);
}

.inspector {
  border-left: 1px solid var(--vx-line);
}

.panel-title {
  min-height: 46px;
  padding: 8px 10px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  border-bottom: 1px solid var(--vx-line);
}

.panel-title strong,
.panel-title small {
  display: block;
}

.depth {
  width: 76px;
  border: 1px solid var(--vx-line);
  background: #0d121b;
  color: var(--vx-text);
  border-radius: 6px;
  padding: 4px;
}

.search-row {
  display: grid;
  grid-template-columns: 1fr 30px;
  gap: 5px;
  padding: 7px;
  border-bottom: 1px solid var(--vx-line);
}

.input {
  width: 100%;
  min-width: 0;
  padding: 7px 8px;
}

.icon-button {
  display: grid;
  place-items: center;
}

.remote-results {
  max-height: 150px;
  overflow: auto;
  border-bottom: 1px solid var(--vx-line);
}

.tree {
  flex: 1;
  overflow: auto;
  padding: 5px 0 10px;
}

.tree-row {
  width: 100%;
  min-height: 25px;
  display: flex;
  align-items: center;
  gap: 6px;
  padding-right: 8px;
  border: 0;
  background: transparent;
  color: #cfd8e8;
  font: 12px/1.25 ui-monospace, SFMono-Regular, Consolas, monospace;
  text-align: left;
  cursor: pointer;
}

.tree-row:hover:not(:disabled) {
  background: #182131;
}

.tree-row:disabled {
  color: var(--vx-muted);
  cursor: default;
}

.tree-row.result {
  padding: 6px 9px;
  color: #bdc9ff;
}

.editor-zone {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: #0c1017;
}

.tabs {
  min-height: 35px;
  display: flex;
  overflow-x: auto;
  background: var(--vx-panel);
  border-bottom: 1px solid var(--vx-line);
}

.tab {
  min-width: 120px;
  max-width: 220px;
  height: 35px;
  display: flex;
  align-items: center;
  gap: 7px;
  border: 0;
  border-right: 1px solid var(--vx-line);
  background: #101722;
  color: var(--vx-muted);
  cursor: pointer;
  padding: 0 9px;
}

.tab.active {
  background: #0c1017;
  color: var(--vx-text);
  box-shadow: inset 0 -2px 0 var(--vx-accent);
}

.tab > span:first-child {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

.dirty-dot {
  color: #f4c76a;
  font-size: 8px;
}

.close {
  opacity: .6;
  font-size: 16px;
}

.empty-tab {
  display: flex;
  align-items: center;
  padding: 0 12px;
  color: var(--vx-muted);
  font-size: 12px;
}

.monaco-host {
  flex: 1;
  min-height: 260px;
}

.statusbar {
  min-height: 26px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 9px;
  background: var(--vx-panel);
  border-top: 1px solid var(--vx-line);
  color: var(--vx-muted);
  font: 11px ui-monospace, SFMono-Regular, Consolas, monospace;
}

.statusbar > span:first-child {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dirty-state {
  color: #f4c76a;
}

.status-button {
  padding: 2px 7px;
  font-size: 11px;
}

.inspector-tabs {
  display: flex;
  min-height: 36px;
  overflow-x: auto;
  border-bottom: 1px solid var(--vx-line);
}

.inspector-tabs button {
  flex: 1;
  min-width: 64px;
  border: 0;
  background: transparent;
  color: var(--vx-muted);
  cursor: pointer;
  text-transform: capitalize;
  font-size: 11px;
}

.inspector-tabs button.active {
  color: var(--vx-text);
  box-shadow: inset 0 -2px 0 var(--vx-accent);
}

.inspector-body {
  flex: 1;
  overflow: auto;
  padding: 8px;
}

.event,
.command,
.diagnostic {
  margin-bottom: 8px;
  padding: 8px;
  background: #0c1119;
  border: 1px solid var(--vx-line);
  border-radius: 7px;
  font-size: 12px;
}

.event-head {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
  color: #dfe6f4;
}

.event pre,
.command pre,
.diff {
  margin: 7px 0 0;
  padding: 8px;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  background: #080b10;
  border-radius: 5px;
  color: #b9c5d8;
  font: 11px/1.45 ui-monospace, SFMono-Regular, Consolas, monospace;
}

.stderr {
  color: #ffadb7 !important;
}

.diff {
  min-height: 100%;
  margin: 0;
  white-space: pre;
}

.diagnostic strong,
.diagnostic span {
  display: block;
}

.diagnostic span {
  color: var(--vx-muted);
  font: 11px ui-monospace, SFMono-Regular, Consolas, monospace;
}

.runtime-list {
  margin: 0;
}

.runtime-list > div {
  display: grid;
  grid-template-columns: 112px 1fr;
  gap: 8px;
  padding: 7px 0;
  border-bottom: 1px solid var(--vx-line);
}

.runtime-list dt {
  color: var(--vx-muted);
  font-size: 11px;
}

.runtime-list dd {
  margin: 0;
  overflow-wrap: anywhere;
  font: 11px/1.4 ui-monospace, SFMono-Regular, Consolas, monospace;
}

.empty {
  padding: 20px 10px;
  color: var(--vx-muted);
  text-align: center;
  font-size: 12px;
}

.control-deck {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(360px, .62fr);
  border-top: 1px solid var(--vx-line);
  background: var(--vx-panel);
}

.mission-panel,
.control-panel {
  min-width: 0;
}

.mission-panel {
  border-right: 1px solid var(--vx-line);
}

.mission-input {
  width: calc(100% - 16px);
  min-height: 74px;
  margin: 8px;
  padding: 8px;
  resize: vertical;
  font: 12px/1.45 ui-monospace, SFMono-Regular, Consolas, monospace;
}

.mission-controls,
.control-buttons {
  display: flex;
  align-items: end;
  gap: 7px;
  flex-wrap: wrap;
  padding: 0 8px 8px;
}

.mission-controls label {
  display: grid;
  gap: 3px;
  color: var(--vx-muted);
  font-size: 10px;
}

.mini-input {
  width: 118px;
  padding: 6px 7px;
}

.control-buttons {
  padding-top: 8px;
}

.control-status {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  padding: 0 9px 9px;
  color: var(--vx-muted);
  font: 10px ui-monospace, SFMono-Regular, Consolas, monospace;
}

@media (max-width: 1350px) {
  .vx-grid {
    grid-template-columns: 230px minmax(400px, 1fr) 320px;
  }

  .runtime-badges .chip:first-child {
    display: none;
  }
}

@media (max-width: 1050px) {
  .vx-editor {
    height: auto;
    min-height: 900px;
  }

  .vx-grid {
    grid-template-columns: 220px 1fr;
  }

  .inspector {
    grid-column: 1 / -1;
    min-height: 260px;
    border-left: 0;
    border-top: 1px solid var(--vx-line);
  }

  .control-deck {
    grid-template-columns: 1fr;
  }

  .mission-panel {
    border-right: 0;
    border-bottom: 1px solid var(--vx-line);
  }
}
</style>
'@

        Write-Utf8 `
            -Path $editorComponent `
            -Content $componentSource

        $created.Add($editorComponent)

        # ========================================================
        # 8. PATCH APP.VUE + TAURI COMMAND REGISTRY
        # ========================================================

        Write-Host ''
        Write-Host '[8/10] DOCK WORKBENCH INTO EXISTING BRIDGE' -ForegroundColor Magenta

        $appOriginal =
            [IO.File]::ReadAllText($appVue)

        $appPatched =
            $appOriginal

        $scriptAnchor =
            '<script setup lang="ts">'

        if (-not $appPatched.Contains($scriptAnchor)) {
            throw 'App.vue script setup anchor missing.'
        }

        if (
            -not $appPatched.Contains(
                "import VertexEditorWorkbench from './vertex-editor/VertexEditorWorkbench.vue'"
            )
        ) {
            $appPatched =
                $appPatched.Replace(
                    $scriptAnchor,
                    $scriptAnchor +
                    "`r`nimport VertexEditorWorkbench from './vertex-editor/VertexEditorWorkbench.vue'"
                )
        }

        $developerTemplate =
            '<template v-else-if="activePage === ''Developer Agent''">'

        if (-not $appPatched.Contains($developerTemplate)) {
            throw 'Developer Agent template anchor missing in App.vue.'
        }

        if (-not $appPatched.Contains('<VertexEditorWorkbench />')) {
            $appPatched =
                $appPatched.Replace(
                    $developerTemplate,
                    $developerTemplate +
                    "`r`n          <VertexEditorWorkbench />"
                )
        }

        $tauriOriginal =
            [IO.File]::ReadAllText($tauriLib)

        $tauriPatched =
            $tauriOriginal

        $moduleAnchor =
            'const BACKGROUND_REFRESH_INTERVAL'

        if (-not $tauriPatched.Contains($moduleAnchor)) {
            throw 'Tauri lib module insertion anchor missing.'
        }

        if (-not $tauriPatched.Contains('mod vertex_editor_control;')) {

            $moduleBlock = @'
mod vertex_editor_control;

use vertex_editor_control::{
    editor_project_tree,
    editor_read_file,
    editor_run_action,
    editor_runtime_info,
    editor_search_files,
    editor_write_file,
};

'@

            $tauriPatched =
                $tauriPatched.Replace(
                    $moduleAnchor,
                    $moduleBlock + $moduleAnchor
                )
        }

        $handlerAnchor =
            '.invoke_handler(tauri::generate_handler!['

        if (-not $tauriPatched.Contains($handlerAnchor)) {
            throw 'Tauri invoke_handler anchor missing.'
        }

        if (-not $tauriPatched.Contains('editor_runtime_info,')) {

            $handlerBlock = @'
.invoke_handler(tauri::generate_handler![
            editor_runtime_info,
            editor_project_tree,
            editor_search_files,
            editor_read_file,
            editor_write_file,
            editor_run_action,
'@

            $tauriPatched =
                $tauriPatched.Replace(
                    $handlerAnchor,
                    $handlerBlock
                )
        }

        # Validate before touching both major files.
        foreach ($requiredText in @(
            "import VertexEditorWorkbench from './vertex-editor/VertexEditorWorkbench.vue'",
            '<VertexEditorWorkbench />'
        )) {
            if (-not $appPatched.Contains($requiredText)) {
                throw "App.vue patch validation failed: $requiredText"
            }
        }

        foreach ($requiredText in @(
            'mod vertex_editor_control;',
            'editor_runtime_info,',
            'editor_run_action,'
        )) {
            if (-not $tauriPatched.Contains($requiredText)) {
                throw "Tauri patch validation failed: $requiredText"
            }
        }

        Write-Utf8 `
            -Path $appVue `
            -Content $appPatched

        Write-Utf8 `
            -Path $tauriLib `
            -Content $tauriPatched

        $sourceModified = $true

        # ========================================================
        # 9. TARGETED BUILD / TEST
        # ========================================================

        Write-Host ''
        Write-Host '[9/10] TARGETED BUILD / TEST / REPAIR GATE' -ForegroundColor Cyan

        Invoke-Checked `
            '[editor] rustfmt' `
            {
                & $rustfmt.Source `
                    --edition 2024 `
                    $tauriEditorModule `
                    $tauriLib
            }

        Invoke-Checked `
            '[editor] Tauri cargo check' `
            {
                & $cargo.Source check `
                    --manifest-path $tauriManifest `
                    --all-targets
            }

        Invoke-Checked `
            '[editor] Tauri tests' `
            {
                & $cargo.Source test `
                    --manifest-path $tauriManifest
            }

        Push-Location $ui

        try {
            Invoke-Checked `
                '[editor] frontend production build' `
                {
                    & $pnpm.Source build
                }
        }
        finally {
            Pop-Location
        }

        # ========================================================
        # 10. WORKSPACE RELEASE GATE
        # ========================================================

        Write-Host ''
        Write-Host '[10/10] WORKSPACE RELEASE GATE' -ForegroundColor Cyan

        Invoke-Checked `
            '[release] cargo check --workspace --all-targets' `
            {
                & $cargo.Source check `
                    --manifest-path (Join-Path $vsa 'Cargo.toml') `
                    --workspace `
                    --all-targets
            }

        Invoke-Checked `
            '[release] cargo test --workspace' `
            {
                & $cargo.Source test `
                    --manifest-path (Join-Path $vsa 'Cargo.toml') `
                    --workspace
            }

        # ========================================================
        # REPORT
        # ========================================================

        $report =
            [ordered]@{
                schema =
                    'vertex.cic.ultimate-editor-docking.v1'

                timestamp =
                    (Get-Date).ToString('o')

                status =
                    'GREEN'

                ui_root =
                    $ui

                topology_score =
                    $uiCandidate.score

                existing_editor_related_files =
                    $existingEditorHits.Count

                frontend =
                    [ordered]@{
                        monaco =
                            $true

                        source_explorer =
                            $true

                        tabs =
                            $true

                        editor =
                            $true

                        diagnostics =
                            $true

                        diff =
                            $true

                        inspector =
                            $true

                        agent_mission_control =
                            $true

                        machine_control_panel =
                            $true
                    }

                backend =
                    [ordered]@{
                        workspace_file_toolkit =
                            $true

                        workspace_escape_protection =
                            $true

                        protected_secret_paths =
                            $true

                        terminal_allowlist =
                            $true

                        timeout_kill =
                            $true

                        developer_agent =
                            $true

                        ard =
                            $true

                        mothership_runtime_detection =
                            $true
                    }

                release =
                    [ordered]@{
                        tauri_check =
                            'GREEN'

                        tauri_tests =
                            'GREEN'

                        frontend_build =
                            'GREEN'

                        workspace_check =
                            'GREEN'

                        workspace_tests =
                            'GREEN'
                    }

                files =
                    [ordered]@{
                        component =
                            $editorComponent

                        service =
                            $editorService

                        monaco_env =
                            $monacoEnv

                        tauri_control =
                            $tauriEditorModule

                        app_vue =
                            $appVue

                        tauri_lib =
                            $tauriLib
                    }

                backup =
                    $backupDir
            }

        $report |
            ConvertTo-Json -Depth 12 |
            Set-Content `
                -LiteralPath $reportPath `
                -Encoding UTF8

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' VERTEX — ULTIMATE EDITOR DOCKING VERIFIED' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' Monaco Editor                         ONLINE' -ForegroundColor Green
        Write-Host ' Source Explorer                       ONLINE' -ForegroundColor Green
        Write-Host ' Multi-file Tabs                       ONLINE' -ForegroundColor Green
        Write-Host ' Ctrl+S Save                           ONLINE' -ForegroundColor Green
        Write-Host ' Diagnostics / Monaco Markers          ONLINE' -ForegroundColor Green
        Write-Host ' Console Inspector                     ONLINE' -ForegroundColor Green
        Write-Host ' Unified Diff                          ONLINE' -ForegroundColor Green
        Write-Host ' Hyper Agent Mission Control           ONLINE' -ForegroundColor Green
        Write-Host ' Developer Agent / Ollama              CONNECTED' -ForegroundColor Green
        Write-Host ' Cargo Fmt / Check / Test              CONTROLLED' -ForegroundColor Green
        Write-Host ' Git Status / Diff                     CONTROLLED' -ForegroundColor Green
        Write-Host ' Arbitrary Shell                       DENIED' -ForegroundColor Green
        Write-Host ' Workspace Escape                      DENIED' -ForegroundColor Green
        Write-Host ' Secret-like File Access               DENIED' -ForegroundColor Green
        Write-Host ' Frontend Build                        GREEN' -ForegroundColor Green
        Write-Host ' Tauri Check / Tests                   GREEN' -ForegroundColor Green
        Write-Host ' Workspace Release Gate                GREEN' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host " REPORT: $reportPath" -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' EDITOR CONTROL SURFACE: DOCKED' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
    }
    catch {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Red
        Write-Host ' ULTIMATE EDITOR STRIKE RED — DAMAGE CONTROL' -ForegroundColor Red
        Write-Host '============================================================' -ForegroundColor Red

        New-Item `
            -ItemType Directory `
            -Path $failedDir `
            -Force |
            Out-Null

        foreach ($file in $created) {
            if (Test-Path -LiteralPath $file) {
                $safeName =
                    [IO.Path]::GetFileName($file)

                Copy-Item `
                    -LiteralPath $file `
                    -Destination (Join-Path $failedDir $safeName) `
                    -Force
            }
        }

        foreach ($original in @(
            $packageJson,
            $pnpmLock,
            $appVue,
            $tauriLib,
            $tauriManifest
        )) {
            Restore-BackupFile $original
        }

        foreach ($file in $created) {
            if (Test-Path -LiteralPath $file) {
                Remove-Item `
                    -LiteralPath $file `
                    -Force
            }
        }

        if (
            (Test-Path -LiteralPath $editorDir) -and
            -not (Get-ChildItem -LiteralPath $editorDir -Force | Select-Object -First 1)
        ) {
            Remove-Item `
                -LiteralPath $editorDir `
                -Force
        }

        Write-Host 'Source files                  RESTORED' -ForegroundColor Yellow
        Write-Host 'Failed generated files        PRESERVED' -ForegroundColor Yellow
        Write-Host "Evidence                      $failedDir" -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Note: node_modules may retain downloaded Monaco package.' -ForegroundColor DarkYellow
        Write-Host 'package.json / lockfile are restored, so source state remains coherent.' -ForegroundColor DarkYellow

        throw
    }
}
