& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC — VERTEXHUB HOT INSTALL / PACKAGE BROWSER V1
# Windows PowerShell 5.1 compatible
#
# Mission:
#   Turn VertexHub into a real equipment dock with:
#     - premium Package Browser UI
#     - verified runtime install state
#     - INSTALL / ENABLE / DISABLE / UNINSTALL
#     - Rust-owned package state + integrity
#     - static catalog execution gate
#
# Honest boundary:
#   - Bundled + catalogued verified packages can hot-enable immediately.
#   - Unknown code packages may be installed/verified, but are NOT executed
#     until a trusted build/catalog step exists.
#   - No arbitrary remote import.
#
# Current target:
#   vertex.live-flight-panel@1.0.0
#
# Safety:
#   - current v0.2 only
#   - V3 GREEN baseline required
#   - VertexHub Registry remains package source of truth
#   - SHA-256 / path traversal gates remain mandatory
#   - controller state read-only
#   - no arbitrary shell
#   - package-scoped runtime install root
#   - rollback on RED
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'

$coreCargo=Join-Path $core 'Cargo.toml'
$hubRoot=Join-Path $core 'vertex-hub'
$hubRegistry=Join-Path $hubRoot 'registry.json'
$hubCrate=Join-Path $core 'crates\vsa-vertex-hub'
$hubCargo=Join-Path $hubCrate 'Cargo.toml'
$hubLib=Join-Path $hubCrate 'src\lib.rs'
$hubInstallerTest=Join-Path $hubCrate 'tests\installer.rs'
$hubRuntimeTest=Join-Path $hubCrate 'tests\runtime_state.rs'

$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriLib=Join-Path $ui 'src-tauri\src\lib.rs'

$loaderRoot=Join-Path $ui 'src\vertex-hub'
$catalogTs=Join-Path $loaderRoot 'catalog.ts'
$runtimeTs=Join-Path $loaderRoot 'runtime.ts'
$hubDockVue=Join-Path $loaderRoot 'VertexHubDock.vue'

$packageId='vertex.live-flight-panel'
$packageVersion='1.0.0'
$sourcePackage=Join-Path (Join-Path (Join-Path $hubRoot 'packages') $packageId) $packageVersion
$sourceManifest=Join-Path $sourcePackage 'manifest.json'
$bundledPackage=Join-Path (Join-Path (Join-Path $loaderRoot 'packages') $packageId) $packageVersion

$runtimeRoot=Join-Path $core '_vertex_hub_runtime'
$runtimeInstalled=Join-Path $runtimeRoot 'installed'
$runtimePackage=Join-Path (Join-Path $runtimeInstalled $packageId) $packageVersion
$runtimeState=Join-Path $runtimeRoot 'state.json'
$runtimeAudit=Join-Path $runtimeRoot 'audit.ndjson'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VERTEX_HUB_HOT_INSTALL_BROWSER_V1_BACKUP.$stamp"
$failed=Join-Path $reports "VERTEX_HUB_HOT_INSTALL_BROWSER_V1_FAILED.$stamp"
$report=Join-Path $reports "VERTEX_HUB_HOT_INSTALL_BROWSER_V1.$stamp.json"

$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}

function RequireCommand([string]$Name){
  $cmd=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $cmd){throw "Missing command: $Name"}
  return $cmd
}

function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}

function BackupFile([string]$Path,[string]$Name){
  if(Test-Path -LiteralPath $Path){
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $Name) -Force
  }
}

function Sha256([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Hash target missing: $Path"}
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function AssertSafeRelative([string]$Rel){
  if([string]::IsNullOrWhiteSpace($Rel)){throw 'Empty relative path denied.'}
  if([IO.Path]::IsPathRooted($Rel)){throw "Absolute path denied: $Rel"}
  foreach($segment in ($Rel -split '[\\/]')){
    if($segment -eq '..'){throw "Path traversal denied: $Rel"}
  }
}

function AssertIdentity([string]$Value,[string]$Label){
  if([string]::IsNullOrWhiteSpace($Value)){throw "$Label is empty."}
  if($Value -notmatch '^[A-Za-z0-9._-]+$'){
    throw "$Label contains unsafe characters: $Value"
  }
}

Write-Host @'
============================================================
 VERTEX — VERTEXHUB HOT INSTALL / PACKAGE BROWSER V1
 VERIFIED EQUIPMENT DOCK + PREMIUM UI
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$coreCargo,
  $hubRoot,$hubRegistry,$hubCrate,$hubCargo,$hubLib,
  $tauriCargo,$tauriLib,$loaderRoot,$catalogTs,$runtimeTs,$hubDockVue,
  $sourcePackage,$sourceManifest,$bundledPackage
)){
  if(-not(Test-Path -LiteralPath $required)){throw "Required V3 artifact missing: $required"}
}

AssertIdentity $packageId 'package_id'
AssertIdentity $packageVersion 'version'

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'
$rustfmt=RequireCommand 'rustfmt'

Write-Host "`n[0/13] VERTEXHUB V3 GREEN BASELINE LOCK" -ForegroundColor Yellow

$hubText=[IO.File]::ReadAllText($hubLib)
$tauriText=[IO.File]::ReadAllText($tauriLib)
$catalogText=[IO.File]::ReadAllText($catalogTs)
$runtimeText=[IO.File]::ReadAllText($runtimeTs)
$dockText=[IO.File]::ReadAllText($hubDockVue)

foreach($baseline in @(
  [pscustomobject]@{Name='Rust Hub installer';Pass=$hubText.Contains('pub fn install_registered_package')},
  [pscustomobject]@{Name='Tauri registry IPC';Pass=$tauriText.Contains('fn vertex_hub_registry')},
  [pscustomobject]@{Name='Generated catalog';Pass=$catalogText.Contains('vertexHubUiPackages')},
  [pscustomobject]@{Name='Hub runtime';Pass=$runtimeText.Contains('validatedHubRegistry')},
  [pscustomobject]@{Name='VertexHubDock';Pass=$dockText.Contains('VertexHub Equipment')}
)){
  if(-not $baseline.Pass){throw "V3 baseline missing: $($baseline.Name)"}
  Write-Host ("  {0,-30} GREEN" -f $baseline.Name) -ForegroundColor Green
}

$registryJson=Get-Content -LiteralPath $hubRegistry -Raw | ConvertFrom-Json
$manifestJson=Get-Content -LiteralPath $sourceManifest -Raw | ConvertFrom-Json

if([string]$registryJson.schema -ne 'vertex.hub.registry.v1'){throw 'Registry schema mismatch.'}
if([string]$manifestJson.schema -ne 'vertex.hub.package.v1'){throw 'Manifest schema mismatch.'}

$entry=@(
  $registryJson.packages |
  Where-Object {
    [string]$_.package_id -eq $packageId -and
    [string]$_.version -eq $packageVersion
  }
)

if($entry.Count -ne 1){throw "Expected exactly one Hub registry entry; found $($entry.Count)"}
if([string]$entry[0].status -ne 'registered'){throw "Package is not registered."}
if(([string]$entry[0].manifest_sha256).ToLowerInvariant() -ne (Sha256 $sourceManifest)){
  throw 'Registry -> manifest hash mismatch.'
}

RunChecked '[baseline] Hub integrity test' {
  & $cargo.Source test --manifest-path $hubCargo live_flight_package_is_registered_and_integrity_verified -- --exact
}

RunChecked '[baseline] workspace check' {
  & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
}

Push-Location $ui
try{
  RunChecked '[baseline] frontend build' {& $pnpm.Source build}
}finally{Pop-Location}

Write-Host "`n[1/13] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
BackupFile $hubLib 'vsa-vertex-hub.lib.rs'
BackupFile $tauriLib 'vsa-shell-desktop.lib.rs'
BackupFile $catalogTs 'catalog.ts'
BackupFile $runtimeTs 'runtime.ts'
BackupFile $hubDockVue 'VertexHubDock.vue'
if(Test-Path -LiteralPath $runtimeState){BackupFile $runtimeState 'runtime-state.json'}
if(Test-Path -LiteralPath $runtimeAudit){BackupFile $runtimeAudit 'runtime-audit.ndjson'}
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/13] EXTEND RUST HUB CORE — RUNTIME EQUIPMENT STATE" -ForegroundColor Yellow

  $hubText=[IO.File]::ReadAllText($hubLib)
  if($hubText.Contains('pub fn hub_runtime_install')){throw 'Hub runtime install contract already exists.'}

  if($hubText.Contains('use serde::Deserialize;')){
    $hubText=$hubText.Replace(
      'use serde::Deserialize;',
      'use serde::{Deserialize, Serialize};'
    )
  }elseif(-not $hubText.Contains('Serialize')){
    throw 'Cannot safely extend serde import in Hub core.'
  }

  $runtimeRust=@'

// VERTEX HUB RUNTIME EQUIPMENT V1
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HubRuntimePackage {
    pub package_id: String,
    pub version: String,
    pub enabled: bool,
    pub installed_at_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HubRuntimeState {
    pub schema: String,
    pub packages: Vec<HubRuntimePackage>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HubRuntimeMutation {
    pub package_id: String,
    pub version: String,
    pub installed: bool,
    pub enabled: bool,
}

fn hub_identity(value: &str, label: &str) -> Result<(), String> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "._-".contains(character))
    {
        return Err(format!("unsafe Hub {label}: {value}"));
    }

    Ok(())
}

fn hub_now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn hub_state_path(runtime_root: &Path) -> PathBuf {
    runtime_root.join("state.json")
}

fn hub_audit_path(runtime_root: &Path) -> PathBuf {
    runtime_root.join("audit.ndjson")
}

fn hub_installed_root(runtime_root: &Path) -> PathBuf {
    runtime_root.join("installed")
}

pub fn load_hub_runtime_state(runtime_root: &Path) -> Result<HubRuntimeState, String> {
    let path = hub_state_path(runtime_root);

    if !path.exists() {
        return Ok(HubRuntimeState {
            schema: "vertex.hub.runtime-state.v1".to_string(),
            packages: Vec::new(),
        });
    }

    let state: HubRuntimeState = serde_json::from_slice(
        &fs::read(&path)
            .map_err(|error| format!("cannot read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid Hub runtime state JSON: {error}"))?;

    if state.schema != "vertex.hub.runtime-state.v1" {
        return Err(format!("unsupported Hub runtime state schema: {}", state.schema));
    }

    Ok(state)
}

fn save_hub_runtime_state(runtime_root: &Path, state: &HubRuntimeState) -> Result<(), String> {
    fs::create_dir_all(runtime_root)
        .map_err(|error| format!("cannot create {}: {error}", runtime_root.display()))?;

    let path = hub_state_path(runtime_root);
    let temp = runtime_root.join("state.json.tmp");

    let bytes = serde_json::to_vec_pretty(state)
        .map_err(|error| format!("cannot serialize Hub runtime state: {error}"))?;

    fs::write(&temp, bytes)
        .map_err(|error| format!("cannot write {}: {error}", temp.display()))?;

    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("cannot replace {}: {error}", path.display()))?;
    }

    fs::rename(&temp, &path)
        .map_err(|error| format!("cannot commit {}: {error}", path.display()))
}

fn append_hub_audit(
    runtime_root: &Path,
    action: &str,
    package_id: &str,
    version: &str,
) -> Result<(), String> {
    use std::io::Write;

    fs::create_dir_all(runtime_root)
        .map_err(|error| format!("cannot create {}: {error}", runtime_root.display()))?;

    let path = hub_audit_path(runtime_root);
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|error| format!("cannot open {}: {error}", path.display()))?;

    let line = serde_json::json!({
        "schema": "vertex.hub.audit.v1",
        "timestamp_ms": hub_now_ms(),
        "action": action,
        "package_id": package_id,
        "version": version
    });

    writeln!(file, "{line}")
        .map_err(|error| format!("cannot append {}: {error}", path.display()))
}

fn hub_runtime_package_dir(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<PathBuf, String> {
    hub_identity(package_id, "package_id")?;
    hub_identity(version, "version")?;

    Ok(hub_installed_root(runtime_root)
        .join(package_id)
        .join(version))
}

fn runtime_mutation(
    state: &HubRuntimeState,
    package_id: &str,
    version: &str,
) -> HubRuntimeMutation {
    let package = state
        .packages
        .iter()
        .find(|package| package.package_id == package_id && package.version == version);

    HubRuntimeMutation {
        package_id: package_id.to_string(),
        version: version.to_string(),
        installed: package.is_some(),
        enabled: package.is_some_and(|package| package.enabled),
    }
}

pub fn hub_runtime_install(
    hub_root: &Path,
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<HubRuntimeMutation, String> {
    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;

    if destination.exists() {
        let validation = validate_package_dir(&destination)?;

        if validation.package_id != package_id || validation.version != version {
            return Err(format!(
                "installed Hub package identity mismatch: {}@{}",
                validation.package_id, validation.version
            ));
        }
    } else {
        install_registered_package(hub_root, &destination, package_id, version)?;
    }

    let mut state = load_hub_runtime_state(runtime_root)?;

    if !state
        .packages
        .iter()
        .any(|package| package.package_id == package_id && package.version == version)
    {
        state.packages.push(HubRuntimePackage {
            package_id: package_id.to_string(),
            version: version.to_string(),
            enabled: false,
            installed_at_ms: hub_now_ms(),
        });
    }

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(runtime_root, "INSTALL", package_id, version)?;

    Ok(runtime_mutation(&state, package_id, version))
}

pub fn hub_runtime_set_enabled(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
    enabled: bool,
) -> Result<HubRuntimeMutation, String> {
    hub_identity(package_id, "package_id")?;
    hub_identity(version, "version")?;

    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;
    validate_package_dir(&destination)?;

    let mut state = load_hub_runtime_state(runtime_root)?;
    let package = state
        .packages
        .iter_mut()
        .find(|package| package.package_id == package_id && package.version == version)
        .ok_or_else(|| format!("Hub package is not installed: {package_id}@{version}"))?;

    package.enabled = enabled;

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(
        runtime_root,
        if enabled { "ENABLE" } else { "DISABLE" },
        package_id,
        version,
    )?;

    Ok(runtime_mutation(&state, package_id, version))
}

pub fn hub_runtime_uninstall(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<HubRuntimeMutation, String> {
    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;

    if destination.exists() {
        validate_package_dir(&destination)?;

        fs::remove_dir_all(&destination)
            .map_err(|error| format!("cannot uninstall {}: {error}", destination.display()))?;
    }

    let mut state = load_hub_runtime_state(runtime_root)?;
    state
        .packages
        .retain(|package| !(package.package_id == package_id && package.version == version));

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(runtime_root, "UNINSTALL", package_id, version)?;

    Ok(runtime_mutation(&state, package_id, version))
}
// END VERTEX HUB RUNTIME EQUIPMENT V1
'@

  $hubText += $runtimeRust
  WriteUtf8 $hubLib $hubText

  $runtimeTest=@'
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use vsa_vertex_hub::{
    hub_runtime_install,
    hub_runtime_set_enabled,
    hub_runtime_uninstall,
    load_hub_runtime_state,
};

#[test]
fn hub_runtime_install_enable_disable_uninstall_cycle_is_verified() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..");

    let hub = workspace.join("vertex-hub");

    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();

    let runtime = std::env::temp_dir()
        .join(format!("vertex-hub-runtime-{stamp}"));

    let installed = hub_runtime_install(
        &hub,
        &runtime,
        "vertex.live-flight-panel",
        "1.0.0",
    )
    .expect("install");

    assert!(installed.installed);
    assert!(!installed.enabled);

    let enabled = hub_runtime_set_enabled(
        &runtime,
        "vertex.live-flight-panel",
        "1.0.0",
        true,
    )
    .expect("enable");

    assert!(enabled.installed);
    assert!(enabled.enabled);

    let disabled = hub_runtime_set_enabled(
        &runtime,
        "vertex.live-flight-panel",
        "1.0.0",
        false,
    )
    .expect("disable");

    assert!(disabled.installed);
    assert!(!disabled.enabled);

    let uninstalled = hub_runtime_uninstall(
        &runtime,
        "vertex.live-flight-panel",
        "1.0.0",
    )
    .expect("uninstall");

    assert!(!uninstalled.installed);
    assert!(!uninstalled.enabled);

    let state = load_hub_runtime_state(&runtime).expect("state");
    assert!(state.packages.is_empty());

    let _ = std::fs::remove_dir_all(runtime);
}
'@
  WriteUtf8 $hubRuntimeTest $runtimeTest

  RunChecked '[hub runtime] rustfmt' {
    & $rustfmt.Source --edition 2024 $hubLib $hubRuntimeTest
  }

  RunChecked '[hub runtime] cargo check' {
    & $cargo.Source check --manifest-path $hubCargo --all-targets
  }

  RunChecked '[hub runtime] lifecycle test' {
    & $cargo.Source test --manifest-path $hubCargo hub_runtime_install_enable_disable_uninstall_cycle_is_verified -- --exact
  }

  Write-Host 'Hub Runtime Equipment State: GREEN' -ForegroundColor Green

  Write-Host "`n[3/13] INSTALL TAURI HOT-INSTALL IPC" -ForegroundColor Yellow

  $tauri=[IO.File]::ReadAllText($tauriLib)
  if($tauri.Contains('fn vertex_hub_runtime_state')){throw 'Tauri hot-install IPC already exists.'}

  $ipc=@'

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
    let mutation = vsa_vertex_hub::hub_runtime_uninstall(
        &vertex_hub_runtime_root()?,
        &package_id,
        &version,
    )?;

    serde_json::to_string(&mutation)
        .map_err(|error| format!("cannot serialize Hub uninstall result: {error}"))
}
// END VERTEX HUB HOT INSTALL IPC V1

'@

  $runAnchor=$tauri.IndexOf('pub fn run()')
  if($runAnchor -lt 0){throw 'Tauri run() anchor missing.'}
  $tauri=$tauri.Insert($runAnchor,$ipc)

  $handler='tauri::generate_handler!['
  $handlerPos=$tauri.IndexOf($handler)
  if($handlerPos -lt 0){throw 'Tauri generate_handler anchor missing.'}
  $listStart=$handlerPos+$handler.Length

  $handlerInsert=@"
`n            vertex_hub_runtime_state,
            vertex_hub_install,
            vertex_hub_set_enabled,
            vertex_hub_uninstall,
"@
  $tauri=$tauri.Insert($listStart,$handlerInsert)

  WriteUtf8 $tauriLib $tauri

  RunChecked '[hub ipc] rustfmt' {
    & $rustfmt.Source --edition 2024 $tauriLib
  }

  RunChecked '[hub ipc] Tauri cargo check' {
    & $cargo.Source check --manifest-path $tauriCargo --all-targets
  }

  Write-Host 'Hub Hot Install IPC: ONLINE' -ForegroundColor Green

  Write-Host "`n[4/13] UPGRADE HUB RUNTIME CLIENT" -ForegroundColor Yellow

  $runtime=@'
import { invoke } from '@tauri-apps/api/core'

export interface HubRegistryEntry {
  package_id: string
  version: string
  kind: string
  status: string
  manifest: string
  manifest_sha256: string
}

export interface HubRegistry {
  schema: string
  generated_at?: string
  packages: HubRegistryEntry[]
}

export interface HubRuntimePackage {
  package_id: string
  version: string
  enabled: boolean
  installed_at_ms: number
}

export interface HubRuntimeState {
  schema: string
  packages: HubRuntimePackage[]
}

export interface HubRuntimeMutation {
  package_id: string
  version: string
  installed: boolean
  enabled: boolean
}

export async function validatedHubRegistry(): Promise<HubRegistry> {
  const raw = await invoke<string>('vertex_hub_registry')
  return JSON.parse(raw) as HubRegistry
}

export async function hubRuntimeState(): Promise<HubRuntimeState> {
  const raw = await invoke<string>('vertex_hub_runtime_state')
  return JSON.parse(raw) as HubRuntimeState
}

export async function installHubPackage(
  packageId: string,
  version: string,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_install', {
    packageId,
    version,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}

export async function setHubPackageEnabled(
  packageId: string,
  version: string,
  enabled: boolean,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_set_enabled', {
    packageId,
    version,
    enabled,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}

export async function uninstallHubPackage(
  packageId: string,
  version: string,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_uninstall', {
    packageId,
    version,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}
'@
  WriteUtf8 $runtimeTs $runtime

  Write-Host 'Hub Runtime Client: UPGRADED' -ForegroundColor Green

  Write-Host "`n[5/13] UPGRADE STATIC EXECUTION CATALOG" -ForegroundColor Yellow

  $manifestHash=Sha256 $sourceManifest

  $catalog=@"
import { markRaw, type Component } from 'vue'
import LiveFlightPanel from './packages/$packageId/$packageVersion/src/VertexLiveFlightPanel.vue'

export interface VertexHubUiPackage {
  packageId: string
  version: string
  displayName: string
  summary: string
  kind: 'ui.component'
  publisher: string
  channel: 'stable' | 'preview'
  manifestSha256: string
  component: Component
  capabilities: string[]
  runtime: string[]
  executionMode: 'bundled'
}

export const vertexHubUiPackages: VertexHubUiPackage[] = [
  {
    packageId: '$packageId',
    version: '$packageVersion',
    displayName: 'Live Flight Panel',
    summary: 'Real-time Mothership session, wave, dispatch, Genesis and VSP telemetry.',
    kind: 'ui.component',
    publisher: 'Vertex',
    channel: 'stable',
    manifestSha256: '$manifestHash',
    component: markRaw(LiveFlightPanel),
    capabilities: ['TELEMETRY', 'READ_ONLY', 'VSP'],
    runtime: ['VUE 3', 'TAURI 2'],
    executionMode: 'bundled',
  },
]
"@
  WriteUtf8 $catalogTs $catalog

  Write-Host 'Static execution catalog: GREEN' -ForegroundColor Green

  Write-Host "`n[6/13] BUILD PREMIUM VERTEXHUB PACKAGE BROWSER" -ForegroundColor Yellow

  $browser=@'
<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { vertexHubUiPackages } from './catalog'
import {
  hubRuntimeState,
  installHubPackage,
  setHubPackageEnabled,
  uninstallHubPackage,
  validatedHubRegistry,
  type HubRegistry,
  type HubRegistryEntry,
  type HubRuntimeState,
} from './runtime'

type Filter = 'ALL' | 'INSTALLED' | 'ENABLED' | 'AVAILABLE'

interface BrowserPackage {
  packageId: string
  version: string
  displayName: string
  summary: string
  publisher: string
  kind: string
  channel: string
  capabilities: string[]
  runtime: string[]
  manifestSha256: string
  bundled: boolean
  registered: boolean
  installed: boolean
  enabled: boolean
  compatible: boolean
  component?: unknown
}

const open = ref(false)
const registry = ref<HubRegistry | null>(null)
const state = ref<HubRuntimeState>({
  schema: 'vertex.hub.runtime-state.v1',
  packages: [],
})
const search = ref('')
const filter = ref<Filter>('ALL')
const busy = ref('')
const error = ref('')
const activity = ref<string[]>([])

function identity(packageId: string, version: string) {
  return `${packageId}@${version}`
}

function pushActivity(message: string) {
  activity.value = [
    `${new Date().toLocaleTimeString()}  ${message}`,
    ...activity.value,
  ].slice(0, 12)
}

function catalogPackage(packageId: string, version: string) {
  return vertexHubUiPackages.find(
    (pkg) => pkg.packageId === packageId && pkg.version === version,
  )
}

function runtimePackage(packageId: string, version: string) {
  return state.value.packages.find(
    (pkg) => pkg.package_id === packageId && pkg.version === version,
  )
}

function registryVerified(entry: HubRegistryEntry) {
  const catalog = catalogPackage(entry.package_id, entry.version)

  if (!catalog) {
    return entry.status === 'registered'
  }

  return (
    entry.status === 'registered'
    && entry.manifest_sha256 === catalog.manifestSha256
  )
}

const packages = computed<BrowserPackage[]>(() => {
  const registryPackages = registry.value?.packages ?? []

  return registryPackages.map((entry) => {
    const catalog = catalogPackage(entry.package_id, entry.version)
    const runtime = runtimePackage(entry.package_id, entry.version)

    return {
      packageId: entry.package_id,
      version: entry.version,
      displayName: catalog?.displayName ?? entry.package_id,
      summary:
        catalog?.summary
        ?? 'Verified VertexHub package. Runtime execution requires a trusted catalog binding.',
      publisher: catalog?.publisher ?? 'Unknown Publisher',
      kind: entry.kind,
      channel: catalog?.channel ?? 'stable',
      capabilities: catalog?.capabilities ?? ['PACKAGE'],
      runtime: catalog?.runtime ?? ['BUILD REQUIRED'],
      manifestSha256: entry.manifest_sha256,
      bundled: Boolean(catalog),
      registered: registryVerified(entry),
      installed: Boolean(runtime),
      enabled: Boolean(runtime?.enabled),
      compatible: Boolean(catalog),
      component: catalog?.component,
    }
  })
})

const visiblePackages = computed(() => {
  const query = search.value.trim().toLowerCase()

  return packages.value.filter((pkg) => {
    const matchesQuery =
      !query
      || pkg.displayName.toLowerCase().includes(query)
      || pkg.packageId.toLowerCase().includes(query)
      || pkg.publisher.toLowerCase().includes(query)
      || pkg.capabilities.some((item) => item.toLowerCase().includes(query))

    const matchesFilter =
      filter.value === 'ALL'
      || (filter.value === 'INSTALLED' && pkg.installed)
      || (filter.value === 'ENABLED' && pkg.enabled)
      || (filter.value === 'AVAILABLE' && !pkg.installed)

    return matchesQuery && matchesFilter
  })
})

const installedCount = computed(
  () => packages.value.filter((pkg) => pkg.installed).length,
)

const enabledCount = computed(
  () => packages.value.filter((pkg) => pkg.enabled).length,
)

const verifiedCount = computed(
  () => packages.value.filter((pkg) => pkg.registered).length,
)

const enabledComponents = computed(
  () => packages.value.filter(
    (pkg) => pkg.enabled && pkg.compatible && pkg.component,
  ),
)

const registryOnline = computed(
  () => registry.value?.schema === 'vertex.hub.registry.v1',
)

async function reload() {
  error.value = ''

  try {
    const [nextRegistry, nextState] = await Promise.all([
      validatedHubRegistry(),
      hubRuntimeState(),
    ])

    registry.value = nextRegistry
    state.value = nextState
  } catch (reason) {
    error.value = String(reason)
  }
}

async function perform(
  pkg: BrowserPackage,
  action: 'INSTALL' | 'ENABLE' | 'DISABLE' | 'UNINSTALL',
) {
  const key = identity(pkg.packageId, pkg.version)

  if (!pkg.registered) {
    error.value = `Package verification failed: ${key}`
    return
  }

  busy.value = `${key}:${action}`
  error.value = ''

  try {
    if (action === 'INSTALL') {
      await installHubPackage(pkg.packageId, pkg.version)
      pushActivity(`INSTALL  ${key}`)
    }

    if (action === 'ENABLE') {
      if (!pkg.compatible) {
        throw new Error(
          `${key} is verified and installed, but requires a trusted build/catalog binding before execution.`,
        )
      }

      await setHubPackageEnabled(pkg.packageId, pkg.version, true)
      pushActivity(`ENABLE   ${key}`)
    }

    if (action === 'DISABLE') {
      await setHubPackageEnabled(pkg.packageId, pkg.version, false)
      pushActivity(`DISABLE  ${key}`)
    }

    if (action === 'UNINSTALL') {
      if (pkg.enabled) {
        await setHubPackageEnabled(pkg.packageId, pkg.version, false)
      }

      await uninstallHubPackage(pkg.packageId, pkg.version)
      pushActivity(`UNINSTALL ${key}`)
    }

    await reload()
  } catch (reason) {
    error.value = String(reason)
    pushActivity(`RED      ${key} / ${action}`)
  } finally {
    busy.value = ''
  }
}

function isBusy(pkg: BrowserPackage) {
  return busy.value.startsWith(identity(pkg.packageId, pkg.version))
}

onMounted(async () => {
  await reload()
})
</script>

<template>
  <section class="vertex-hub-host">
    <button
      class="hub-launcher"
      :class="{ online: registryOnline }"
      title="Open VertexHub Equipment Dock"
      @click="open = true"
    >
      <span class="launcher-mark">
        <span />
        <span />
        <span />
      </span>

      <span class="launcher-copy">
        <strong>VERTEX HUB</strong>
        <small>{{ enabledCount }} ONLINE · {{ installedCount }} INSTALLED</small>
      </span>

      <span class="launcher-pulse" />
    </button>

    <Teleport to="body">
      <Transition name="hub-fade">
        <div
          v-if="open"
          class="hub-backdrop"
          @mousedown.self="open = false"
        >
          <section class="hub-shell">
            <div class="hub-grid-glow" />
            <div class="hub-noise" />

            <header class="hub-command">
              <div class="brand">
                <div class="brand-sigil">
                  <span class="sigil-core">V</span>
                  <span class="sigil-ring" />
                </div>

                <div>
                  <div class="eyebrow">VERTEX // EQUIPMENT NETWORK</div>
                  <h1>VertexHub</h1>
                  <p>Verified packages. Controlled docking. Zero blind execution.</p>
                </div>
              </div>

              <div class="command-status">
                <div class="status-block">
                  <span>REGISTRY</span>
                  <strong :class="{ green: registryOnline }">
                    {{ registryOnline ? 'VALIDATED' : 'OFFLINE' }}
                  </strong>
                </div>

                <div class="status-block">
                  <span>TRUST GATE</span>
                  <strong class="green">ENFORCED</strong>
                </div>

                <button
                  class="icon-button"
                  title="Reload Hub"
                  @click="reload"
                >
                  ↻
                </button>

                <button
                  class="close-button"
                  title="Close VertexHub"
                  @click="open = false"
                >
                  ×
                </button>
              </div>
            </header>

            <div class="hub-body">
              <aside class="hub-rail">
                <div class="rail-section">
                  <span class="rail-label">EQUIPMENT</span>

                  <button
                    v-for="item in (['ALL', 'INSTALLED', 'ENABLED', 'AVAILABLE'] as Filter[])"
                    :key="item"
                    class="rail-button"
                    :class="{ active: filter === item }"
                    @click="filter = item"
                  >
                    <span class="rail-dot" />
                    {{ item }}
                    <em v-if="item === 'ALL'">{{ packages.length }}</em>
                    <em v-else-if="item === 'INSTALLED'">{{ installedCount }}</em>
                    <em v-else-if="item === 'ENABLED'">{{ enabledCount }}</em>
                    <em v-else>{{ packages.length - installedCount }}</em>
                  </button>
                </div>

                <div class="rail-section rail-bottom">
                  <span class="rail-label">SYSTEM</span>

                  <div class="rail-meter">
                    <span>VERIFIED</span>
                    <strong>{{ verifiedCount }}/{{ packages.length }}</strong>
                  </div>

                  <div class="rail-meter">
                    <span>EXECUTION</span>
                    <strong>STATIC GATE</strong>
                  </div>

                  <div class="rail-meter">
                    <span>REMOTE CODE</span>
                    <strong class="denied">DENIED</strong>
                  </div>
                </div>
              </aside>

              <main class="hub-main">
                <section class="hub-hero">
                  <div>
                    <div class="eyebrow">MOTHERSHIP EQUIPMENT DOCK</div>
                    <h2>Build your control deck.</h2>
                    <p>
                      Install verified capabilities without surrendering the runtime boundary.
                      Packages dock only after Registry + SHA-256 validation.
                    </p>
                  </div>

                  <div class="hero-stats">
                    <article>
                      <span>AVAILABLE</span>
                      <strong>{{ packages.length }}</strong>
                    </article>

                    <article>
                      <span>INSTALLED</span>
                      <strong>{{ installedCount }}</strong>
                    </article>

                    <article>
                      <span>ACTIVE</span>
                      <strong>{{ enabledCount }}</strong>
                    </article>
                  </div>
                </section>

                <section class="toolbar">
                  <label class="search-box">
                    <span>⌕</span>
                    <input
                      v-model="search"
                      autocomplete="off"
                      spellcheck="false"
                      placeholder="Search packages, capabilities, publisher..."
                    >
                    <kbd>HUB</kbd>
                  </label>

                  <div class="toolbar-copy">
                    <span>{{ visiblePackages.length }} EQUIPMENT UNITS</span>
                    <span class="separator">/</span>
                    <span>CHANNEL STABLE</span>
                  </div>
                </section>

                <section class="package-stage">
                  <article
                    v-for="pkg in visiblePackages"
                    :key="identity(pkg.packageId, pkg.version)"
                    class="package-card"
                    :class="{
                      active: pkg.enabled,
                      installed: pkg.installed,
                      incompatible: pkg.installed && !pkg.compatible,
                    }"
                  >
                    <div class="card-topline">
                      <div class="package-icon">
                        <div class="icon-orbit" />
                        <span>{{ pkg.displayName.slice(0, 1).toUpperCase() }}</span>
                      </div>

                      <div class="package-title">
                        <div class="package-state">
                          <span
                            class="verified"
                            :class="{ bad: !pkg.registered }"
                          >
                            {{ pkg.registered ? '◆ VERIFIED' : '◇ UNVERIFIED' }}
                          </span>

                          <span v-if="pkg.enabled" class="live-state">
                            ● ONLINE
                          </span>
                          <span v-else-if="pkg.installed" class="installed-state">
                            INSTALLED
                          </span>
                          <span v-else class="available-state">
                            AVAILABLE
                          </span>
                        </div>

                        <h3>{{ pkg.displayName }}</h3>
                        <p class="package-id">
                          {{ pkg.packageId }} <span>@{{ pkg.version }}</span>
                        </p>
                      </div>

                      <div class="package-channel">
                        {{ pkg.channel.toUpperCase() }}
                      </div>
                    </div>

                    <p class="summary">{{ pkg.summary }}</p>

                    <div class="capability-row">
                      <span
                        v-for="capability in pkg.capabilities"
                        :key="capability"
                      >
                        {{ capability }}
                      </span>
                    </div>

                    <div class="runtime-row">
                      <div>
                        <span>PUBLISHER</span>
                        <strong>{{ pkg.publisher }}</strong>
                      </div>

                      <div>
                        <span>RUNTIME</span>
                        <strong>{{ pkg.runtime.join(' / ') }}</strong>
                      </div>

                      <div>
                        <span>DELIVERY</span>
                        <strong>
                          {{ pkg.bundled ? 'BUNDLED HOT' : 'BUILD REQUIRED' }}
                        </strong>
                      </div>
                    </div>

                    <div class="trust-row">
                      <span>MANIFEST</span>
                      <code>{{ pkg.manifestSha256.slice(0, 16) }}…</code>
                      <span class="trust-copy">SHA-256 LOCKED</span>
                    </div>

                    <footer class="package-actions">
                      <div class="compatibility">
                        <span
                          class="compat-dot"
                          :class="{ online: pkg.compatible }"
                        />
                        {{
                          pkg.compatible
                            ? 'RUNTIME COMPATIBLE'
                            : 'INSTALLABLE · EXECUTION GATED'
                        }}
                      </div>

                      <div class="actions">
                        <button
                          v-if="!pkg.installed"
                          class="primary-action"
                          :disabled="isBusy(pkg) || !pkg.registered"
                          @click="perform(pkg, 'INSTALL')"
                        >
                          {{ isBusy(pkg) ? 'DOCKING…' : 'INSTALL' }}
                        </button>

                        <button
                          v-else-if="pkg.compatible && !pkg.enabled"
                          class="primary-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'ENABLE')"
                        >
                          ENABLE
                        </button>

                        <button
                          v-else-if="pkg.enabled"
                          class="secondary-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'DISABLE')"
                        >
                          DISABLE
                        </button>

                        <button
                          v-if="pkg.installed && !pkg.enabled"
                          class="ghost-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'UNINSTALL')"
                        >
                          UNINSTALL
                        </button>
                      </div>
                    </footer>
                  </article>

                  <div
                    v-if="visiblePackages.length === 0"
                    class="empty-state"
                  >
                    <div class="empty-orbit">
                      <span>V</span>
                    </div>
                    <strong>No equipment matches this sector.</strong>
                    <p>Adjust the filter or search signature.</p>
                  </div>
                </section>
              </main>

              <aside class="hub-inspector">
                <div class="inspector-head">
                  <span class="rail-label">DOCK TELEMETRY</span>
                  <strong>{{ busy ? 'BUSY' : 'READY' }}</strong>
                </div>

                <div class="trust-stack">
                  <article>
                    <span>Registry integrity</span>
                    <strong>SHA-256</strong>
                    <em>LOCKED</em>
                  </article>

                  <article>
                    <span>Path traversal</span>
                    <strong>DENIED</strong>
                    <em>FAIL-CLOSED</em>
                  </article>

                  <article>
                    <span>Remote import</span>
                    <strong>DENIED</strong>
                    <em>STATIC GATE</em>
                  </article>

                  <article>
                    <span>Controller state</span>
                    <strong>READ ONLY</strong>
                    <em>BOUNDARY</em>
                  </article>
                </div>

                <div class="activity-panel">
                  <div class="activity-head">
                    <span>ACTIVITY</span>
                    <small>LOCAL AUDIT MIRROR</small>
                  </div>

                  <div class="activity-list">
                    <p v-if="activity.length === 0">
                      No docking actions this session.
                    </p>

                    <code
                      v-for="line in activity"
                      :key="line"
                    >
                      {{ line }}
                    </code>
                  </div>
                </div>

                <div v-if="error" class="error-panel">
                  <span>VERTEXHUB RED</span>
                  <pre>{{ error }}</pre>
                </div>

                <div class="inspector-footer">
                  <span class="signal" />
                  <div>
                    <strong>VERTEX EQUIPMENT NETWORK</strong>
                    <small>LOCAL / VERIFIED / CONTROLLED</small>
                  </div>
                </div>
              </aside>
            </div>
          </section>
        </div>
      </Transition>
    </Teleport>

    <component
      :is="pkg.component"
      v-for="pkg in enabledComponents"
      :key="identity(pkg.packageId, pkg.version)"
    />
  </section>
</template>

<style scoped>
.vertex-hub-host {
  position: relative;
  min-width: 0;
}

.hub-launcher {
  position: absolute;
  z-index: 12;
  top: 7px;
  right: 8px;
  display: flex;
  align-items: center;
  gap: 9px;
  height: 34px;
  padding: 0 10px 0 8px;
  border: 1px solid rgba(119, 135, 171, .28);
  border-radius: 8px;
  background:
    linear-gradient(180deg, rgba(28, 34, 48, .96), rgba(11, 15, 23, .96));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, .04),
    0 6px 18px rgba(0, 0, 0, .22);
  color: #dce6f8;
  cursor: pointer;
  transition:
    border-color .18s ease,
    transform .18s ease,
    box-shadow .18s ease;
}

.hub-launcher:hover {
  transform: translateY(-1px);
  border-color: rgba(142, 113, 255, .6);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, .06),
    0 9px 24px rgba(0, 0, 0, .34),
    0 0 0 1px rgba(124, 92, 255, .08);
}

.hub-launcher.online {
  border-color: rgba(83, 224, 191, .34);
}

.launcher-mark {
  position: relative;
  width: 20px;
  height: 20px;
}

.launcher-mark span {
  position: absolute;
  border: 1px solid rgba(126, 105, 255, .75);
  transform: rotate(45deg);
}

.launcher-mark span:nth-child(1) {
  inset: 1px;
}

.launcher-mark span:nth-child(2) {
  inset: 5px;
  border-color: rgba(80, 216, 224, .85);
}

.launcher-mark span:nth-child(3) {
  inset: 9px;
  background: #7d6cff;
  border: 0;
}

.launcher-copy {
  text-align: left;
}

.launcher-copy strong,
.launcher-copy small {
  display: block;
}

.launcher-copy strong {
  font:
    700 9px/1.1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: .12em;
}

.launcher-copy small {
  margin-top: 3px;
  color: #6f7e98;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .07em;
}

.launcher-pulse {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #4fe0b2;
  box-shadow: 0 0 10px rgba(79, 224, 178, .8);
}

.hub-backdrop {
  position: fixed;
  z-index: 10000;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 26px;
  background:
    radial-gradient(circle at 50% 0%, rgba(78, 55, 132, .18), transparent 38%),
    rgba(3, 5, 9, .78);
  backdrop-filter: blur(14px) saturate(.85);
}

.hub-shell {
  position: relative;
  width: min(1540px, calc(100vw - 52px));
  height: min(900px, calc(100vh - 52px));
  overflow: hidden;
  border: 1px solid rgba(128, 145, 181, .2);
  border-radius: 14px;
  background:
    linear-gradient(135deg, rgba(20, 25, 36, .98), rgba(7, 10, 16, .995) 55%);
  box-shadow:
    0 38px 100px rgba(0, 0, 0, .72),
    0 0 0 1px rgba(255, 255, 255, .02) inset,
    0 1px 0 rgba(255, 255, 255, .05) inset;
  color: #dfe7f5;
}

.hub-grid-glow {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(rgba(130, 145, 180, .025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(130, 145, 180, .025) 1px, transparent 1px);
  background-size: 40px 40px;
  mask-image: linear-gradient(to bottom, black, transparent 72%);
}

.hub-noise {
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: .18;
  background:
    radial-gradient(circle at 18% 8%, rgba(128, 92, 255, .18), transparent 24%),
    radial-gradient(circle at 72% 0%, rgba(41, 185, 211, .11), transparent 30%);
}

.hub-command {
  position: relative;
  z-index: 2;
  display: flex;
  justify-content: space-between;
  align-items: center;
  height: 94px;
  padding: 0 24px;
  border-bottom: 1px solid rgba(111, 128, 160, .14);
  background: rgba(8, 12, 18, .58);
}

.brand {
  display: flex;
  align-items: center;
  gap: 16px;
}

.brand-sigil {
  position: relative;
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
}

.sigil-core {
  position: relative;
  z-index: 2;
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border: 1px solid rgba(136, 112, 255, .7);
  transform: rotate(45deg);
  background:
    linear-gradient(135deg, rgba(130, 92, 255, .28), rgba(27, 34, 53, .5));
  color: #f0edff;
  font:
    800 13px/1 Inter,
    sans-serif;
  box-shadow: 0 0 24px rgba(117, 85, 255, .18);
}

.sigil-core::first-letter {
  transform: rotate(-45deg);
}

.sigil-ring {
  position: absolute;
  inset: 0;
  border: 1px solid rgba(73, 199, 220, .28);
  border-radius: 50%;
}

.eyebrow {
  color: #6f7d98;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .19em;
}

.brand h1 {
  margin: 4px 0 0;
  font:
    650 24px/1.05 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.025em;
}

.brand p {
  margin: 5px 0 0;
  color: #7f8ca3;
  font: 10px/1.3 Inter, "Segoe UI", sans-serif;
}

.command-status {
  display: flex;
  align-items: center;
  gap: 10px;
}

.status-block {
  min-width: 108px;
  padding: 7px 10px;
  border-left: 1px solid rgba(120, 137, 170, .16);
}

.status-block span,
.status-block strong {
  display: block;
}

.status-block span {
  color: #59667d;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .14em;
}

.status-block strong {
  margin-top: 5px;
  color: #a7b3c7;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
}

.status-block strong.green {
  color: #55dfb4;
}

.icon-button,
.close-button {
  display: grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1px solid rgba(117, 133, 165, .18);
  border-radius: 7px;
  background: rgba(19, 25, 36, .72);
  color: #8c9ab1;
  cursor: pointer;
}

.close-button {
  font-size: 20px;
}

.icon-button:hover,
.close-button:hover {
  border-color: rgba(136, 112, 255, .42);
  color: #eef2fb;
}

.hub-body {
  position: relative;
  z-index: 2;
  display: grid;
  grid-template-columns: 178px minmax(0, 1fr) 250px;
  height: calc(100% - 94px);
}

.hub-rail,
.hub-inspector {
  background: rgba(8, 12, 18, .5);
}

.hub-rail {
  display: flex;
  flex-direction: column;
  padding: 22px 14px 18px;
  border-right: 1px solid rgba(111, 128, 160, .12);
}

.rail-section {
  display: grid;
  gap: 6px;
}

.rail-bottom {
  margin-top: auto;
  gap: 12px;
}

.rail-label {
  margin: 0 8px 5px;
  color: #4e5b70;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .16em;
}

.rail-button {
  display: grid;
  grid-template-columns: 8px 1fr auto;
  align-items: center;
  gap: 8px;
  height: 34px;
  padding: 0 9px;
  border: 1px solid transparent;
  border-radius: 7px;
  background: transparent;
  color: #7f8da3;
  text-align: left;
  font:
    650 9px/1 Inter,
    "Segoe UI",
    sans-serif;
  cursor: pointer;
}

.rail-button:hover {
  background: rgba(255, 255, 255, .025);
  color: #cbd5e5;
}

.rail-button.active {
  border-color: rgba(130, 104, 255, .22);
  background:
    linear-gradient(90deg, rgba(113, 81, 238, .12), rgba(76, 95, 129, .025));
  color: #e5e9f3;
}

.rail-dot {
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: #455168;
}

.rail-button.active .rail-dot {
  background: #816dff;
  box-shadow: 0 0 9px rgba(129, 109, 255, .9);
}

.rail-button em {
  color: #556177;
  font:
    normal 700 8px/1 ui-monospace,
    monospace;
}

.rail-meter {
  padding: 0 8px;
}

.rail-meter span,
.rail-meter strong {
  display: block;
}

.rail-meter span {
  color: #4d596d;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.rail-meter strong {
  margin-top: 5px;
  color: #8896ac;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
}

.rail-meter strong.denied {
  color: #d57f8d;
}

.hub-main {
  min-width: 0;
  overflow: auto;
  padding: 26px 28px 36px;
}

.hub-main::-webkit-scrollbar,
.activity-list::-webkit-scrollbar {
  width: 7px;
}

.hub-main::-webkit-scrollbar-thumb,
.activity-list::-webkit-scrollbar-thumb {
  border-radius: 6px;
  background: #293246;
}

.hub-hero {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 28px;
  padding: 7px 2px 24px;
}

.hub-hero h2 {
  margin: 7px 0 8px;
  color: #f0f3fa;
  font:
    600 30px/1.05 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.035em;
}

.hub-hero p {
  max-width: 660px;
  margin: 0;
  color: #7f8da4;
  font: 11px/1.6 Inter, "Segoe UI", sans-serif;
}

.hero-stats {
  display: flex;
  gap: 8px;
}

.hero-stats article {
  min-width: 92px;
  padding: 10px 12px;
  border: 1px solid rgba(112, 129, 160, .13);
  border-radius: 8px;
  background: rgba(17, 23, 34, .64);
}

.hero-stats span,
.hero-stats strong {
  display: block;
}

.hero-stats span {
  color: #58657b;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.hero-stats strong {
  margin-top: 7px;
  color: #dce5f4;
  font:
    600 19px/1 Inter,
    sans-serif;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 18px;
  margin-bottom: 18px;
}

.search-box {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  width: min(560px, 100%);
  height: 39px;
  padding: 0 11px;
  border: 1px solid rgba(112, 129, 160, .18);
  border-radius: 8px;
  background: rgba(10, 15, 23, .72);
}

.search-box > span {
  color: #69778d;
  font-size: 18px;
}

.search-box input {
  min-width: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: #dce5f3;
  font: 10px/1 Inter, "Segoe UI", sans-serif;
}

.search-box input::placeholder {
  color: #4d5a6f;
}

.search-box kbd {
  padding: 3px 5px;
  border: 1px solid rgba(108, 123, 151, .18);
  border-radius: 4px;
  background: rgba(255, 255, 255, .02);
  color: #5c697e;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.toolbar-copy {
  display: flex;
  gap: 7px;
  color: #526075;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .09em;
}

.separator {
  color: #313b4d;
}

.package-stage {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(390px, 1fr));
  gap: 14px;
}

.package-card {
  position: relative;
  overflow: hidden;
  min-height: 330px;
  padding: 18px;
  border: 1px solid rgba(110, 128, 160, .14);
  border-radius: 11px;
  background:
    linear-gradient(145deg, rgba(20, 27, 39, .84), rgba(9, 13, 20, .92));
  box-shadow:
    0 9px 24px rgba(0, 0, 0, .14),
    inset 0 1px 0 rgba(255, 255, 255, .025);
  transition:
    transform .18s ease,
    border-color .18s ease,
    box-shadow .18s ease;
}

.package-card::before {
  content: "";
  position: absolute;
  inset: 0 auto auto 0;
  width: 100%;
  height: 1px;
  background:
    linear-gradient(90deg, transparent, rgba(117, 92, 255, .5), transparent);
  opacity: .55;
}

.package-card:hover {
  transform: translateY(-2px);
  border-color: rgba(126, 107, 222, .28);
  box-shadow:
    0 16px 34px rgba(0, 0, 0, .22),
    0 0 30px rgba(95, 69, 182, .045);
}

.package-card.active {
  border-color: rgba(68, 212, 177, .28);
}

.package-card.active::before {
  background:
    linear-gradient(90deg, transparent, rgba(76, 226, 184, .65), transparent);
}

.package-card.incompatible {
  border-color: rgba(214, 161, 88, .2);
}

.card-topline {
  display: grid;
  grid-template-columns: 52px minmax(0, 1fr) auto;
  gap: 13px;
  align-items: start;
}

.package-icon {
  position: relative;
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
  border: 1px solid rgba(115, 94, 224, .3);
  border-radius: 10px;
  background:
    radial-gradient(circle at 50% 50%, rgba(113, 86, 238, .2), transparent 62%),
    rgba(10, 14, 22, .8);
  color: #dcd6ff;
  font:
    700 15px/1 Inter,
    sans-serif;
}

.icon-orbit {
  position: absolute;
  inset: 7px;
  border: 1px solid rgba(73, 194, 213, .18);
  transform: rotate(45deg);
}

.package-state {
  display: flex;
  gap: 8px;
  align-items: center;
  min-height: 13px;
}

.package-state span {
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .06em;
}

.verified {
  color: #5fe0b6;
}

.verified.bad {
  color: #e37686;
}

.live-state {
  color: #54ddb0;
}

.installed-state {
  color: #8e9bb2;
}

.available-state {
  color: #728096;
}

.package-title h3 {
  margin: 6px 0 4px;
  color: #edf1f8;
  font:
    600 17px/1.1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.018em;
}

.package-id {
  margin: 0;
  color: #657289;
  font:
    700 8px/1.2 ui-monospace,
    Consolas,
    monospace;
}

.package-id span {
  color: #8877e3;
}

.package-channel {
  padding: 4px 6px;
  border: 1px solid rgba(97, 112, 140, .17);
  border-radius: 4px;
  color: #69768b;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.summary {
  min-height: 44px;
  margin: 17px 0 14px;
  color: #8d99ad;
  font: 10px/1.55 Inter, "Segoe UI", sans-serif;
}

.capability-row {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
  min-height: 25px;
}

.capability-row span {
  padding: 4px 6px;
  border: 1px solid rgba(103, 119, 150, .15);
  border-radius: 4px;
  background: rgba(255, 255, 255, .018);
  color: #76849a;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.runtime-row {
  display: grid;
  grid-template-columns: .8fr 1.2fr 1fr;
  gap: 8px;
  margin-top: 14px;
  padding: 12px 0;
  border-top: 1px solid rgba(109, 126, 156, .1);
  border-bottom: 1px solid rgba(109, 126, 156, .1);
}

.runtime-row span,
.runtime-row strong {
  display: block;
}

.runtime-row span {
  color: #4e5a6e;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.runtime-row strong {
  margin-top: 5px;
  color: #8491a6;
  font:
    700 7px/1.25 ui-monospace,
    Consolas,
    monospace;
}

.trust-row {
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 8px;
  align-items: center;
  margin-top: 11px;
  color: #4f5c70;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-row code {
  overflow: hidden;
  color: #6e7b90;
  text-overflow: ellipsis;
}

.trust-copy {
  color: #5d6a80;
}

.package-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-top: 15px;
}

.compatibility {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #68758a;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.compat-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #b27b50;
}

.compat-dot.online {
  background: #4eddb0;
  box-shadow: 0 0 8px rgba(78, 221, 176, .52);
}

.actions {
  display: flex;
  gap: 6px;
}

.actions button {
  height: 29px;
  padding: 0 11px;
  border-radius: 6px;
  font:
    700 8px/1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: .06em;
  cursor: pointer;
}

.actions button:disabled {
  opacity: .38;
  cursor: default;
}

.primary-action {
  border: 1px solid rgba(122, 102, 255, .62);
  background:
    linear-gradient(180deg, rgba(116, 91, 245, .92), rgba(84, 60, 195, .92));
  color: white;
  box-shadow:
    0 5px 14px rgba(93, 65, 214, .2),
    inset 0 1px 0 rgba(255, 255, 255, .16);
}

.secondary-action {
  border: 1px solid rgba(74, 207, 172, .32);
  background: rgba(31, 83, 70, .22);
  color: #72dfbc;
}

.ghost-action {
  border: 1px solid rgba(110, 126, 154, .18);
  background: rgba(255, 255, 255, .015);
  color: #758196;
}

.empty-state {
  grid-column: 1 / -1;
  display: grid;
  justify-items: center;
  padding: 90px 20px;
  color: #748197;
  text-align: center;
}

.empty-orbit {
  display: grid;
  place-items: center;
  width: 54px;
  height: 54px;
  margin-bottom: 14px;
  border: 1px solid rgba(118, 94, 226, .3);
  transform: rotate(45deg);
}

.empty-orbit span {
  transform: rotate(-45deg);
  color: #8b79e6;
}

.empty-state strong {
  color: #a8b3c5;
  font: 12px/1 Inter, sans-serif;
}

.empty-state p {
  color: #5c687b;
  font: 9px/1.4 Inter, sans-serif;
}

.hub-inspector {
  display: flex;
  flex-direction: column;
  min-width: 0;
  padding: 20px 16px 16px;
  border-left: 1px solid rgba(111, 128, 160, .12);
}

.inspector-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.inspector-head .rail-label {
  margin: 0;
}

.inspector-head strong {
  color: #54dcb0;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-stack {
  display: grid;
  gap: 7px;
  margin-top: 14px;
}

.trust-stack article {
  padding: 10px;
  border: 1px solid rgba(107, 124, 153, .1);
  border-radius: 7px;
  background: rgba(255, 255, 255, .015);
}

.trust-stack span,
.trust-stack strong,
.trust-stack em {
  display: block;
}

.trust-stack span {
  color: #58657a;
  font: 8px/1 Inter, sans-serif;
}

.trust-stack strong {
  margin-top: 6px;
  color: #a8b4c7;
  font:
    700 9px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-stack em {
  margin-top: 4px;
  color: #536077;
  font:
    normal 700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.activity-panel {
  min-height: 0;
  margin-top: 18px;
}

.activity-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.activity-head span,
.activity-head small {
  color: #536076;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.activity-list {
  display: grid;
  gap: 5px;
  max-height: 180px;
  margin-top: 9px;
  overflow: auto;
}

.activity-list p,
.activity-list code {
  margin: 0;
  color: #667389;
  font:
    7px/1.45 ui-monospace,
    Consolas,
    monospace;
}

.activity-list code {
  color: #75839a;
}

.error-panel {
  margin-top: 16px;
  padding: 9px;
  border: 1px solid rgba(221, 93, 111, .2);
  border-radius: 7px;
  background: rgba(97, 28, 39, .13);
}

.error-panel span {
  color: #e77c8b;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.error-panel pre {
  max-height: 100px;
  margin: 7px 0 0;
  overflow: auto;
  color: #c78790;
  white-space: pre-wrap;
  font:
    7px/1.45 ui-monospace,
    Consolas,
    monospace;
}

.inspector-footer {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-top: auto;
  padding-top: 14px;
  border-top: 1px solid rgba(105, 122, 151, .1);
}

.signal {
  width: 8px;
  height: 8px;
  border: 1px solid rgba(81, 218, 179, .55);
  border-radius: 50%;
  box-shadow:
    0 0 0 3px rgba(81, 218, 179, .05),
    0 0 12px rgba(81, 218, 179, .2);
}

.inspector-footer strong,
.inspector-footer small {
  display: block;
}

.inspector-footer strong {
  color: #76849a;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.inspector-footer small {
  margin-top: 4px;
  color: #465267;
  font:
    700 6px/1 ui-monospace,
    Consolas,
    monospace;
}

.hub-fade-enter-active,
.hub-fade-leave-active {
  transition:
    opacity .16s ease,
    transform .16s ease;
}

.hub-fade-enter-from,
.hub-fade-leave-to {
  opacity: 0;
}

.hub-fade-enter-from .hub-shell,
.hub-fade-leave-to .hub-shell {
  transform: translateY(8px) scale(.992);
}

@media (max-width: 1120px) {
  .hub-body {
    grid-template-columns: 150px minmax(0, 1fr);
  }

  .hub-inspector {
    display: none;
  }

  .hero-stats {
    display: none;
  }
}

@media (max-width: 760px) {
  .hub-backdrop {
    padding: 8px;
  }

  .hub-shell {
    width: calc(100vw - 16px);
    height: calc(100vh - 16px);
  }

  .hub-body {
    grid-template-columns: 1fr;
  }

  .hub-rail {
    display: none;
  }

  .hub-command {
    padding: 0 14px;
  }

  .status-block {
    display: none;
  }

  .hub-main {
    padding: 18px 14px 28px;
  }

  .package-stage {
    grid-template-columns: 1fr;
  }

  .toolbar-copy {
    display: none;
  }
}
</style>
'@
  WriteUtf8 $hubDockVue $browser

  Write-Host 'Premium Equipment Dock UI: INSTALLED' -ForegroundColor Green

  Write-Host "`n[7/13] MIGRATE FIRST PACKAGE INTO RUNTIME EQUIPMENT STATE" -ForegroundColor Yellow

  if(-not(Test-Path -LiteralPath $runtimePackage)){
    New-Item -ItemType Directory -Path $runtimePackage -Force|Out-Null

    foreach($file in $manifestJson.files){
      $rel=[string]$file.path
      AssertSafeRelative $rel

      $src=Join-Path $sourcePackage ($rel.Replace('/','\'))
      $dst=Join-Path $runtimePackage ($rel.Replace('/','\'))

      if((Sha256 $src) -ne ([string]$file.sha256).ToLowerInvariant()){
        throw "Migration source hash mismatch: $rel"
      }

      $parent=Split-Path -Parent $dst
      New-Item -ItemType Directory -Path $parent -Force|Out-Null
      Copy-Item -LiteralPath $src -Destination $dst -Force

      if((Sha256 $dst) -ne ([string]$file.sha256).ToLowerInvariant()){
        throw "Migration destination hash mismatch: $rel"
      }
    }

    Copy-Item -LiteralPath $sourceManifest -Destination (Join-Path $runtimePackage 'manifest.json') -Force
  }

  New-Item -ItemType Directory -Path $runtimeRoot -Force|Out-Null

  $state=[ordered]@{
    schema='vertex.hub.runtime-state.v1'
    packages=@(
      [ordered]@{
        package_id=$packageId
        version=$packageVersion
        enabled=$true
        installed_at_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      }
    )
  }
  WriteUtf8 $runtimeState ($state|ConvertTo-Json -Depth 8)

  $auditRecord=[ordered]@{
    schema='vertex.hub.audit.v1'
    timestamp_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    action='MIGRATE_ENABLE'
    package_id=$packageId
    version=$packageVersion
  }|ConvertTo-Json -Compress
  WriteUtf8 $runtimeAudit ($auditRecord+"`n")

  Write-Host 'Live Flight runtime install: VERIFIED' -ForegroundColor Green
  Write-Host 'Live Flight runtime state  : ENABLED' -ForegroundColor Green

  Write-Host "`n[8/13] FRONTEND TYPECHECK / PREMIUM BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[browser] vue-tsc' {& $pnpm.Source exec vue-tsc --noEmit}
    RunChecked '[browser] vite build' {& $pnpm.Source exec vite build}
  }finally{Pop-Location}

  Write-Host "`n[9/13] STATIC UI / SAFETY AUDIT" -ForegroundColor Yellow

  $browserNow=[IO.File]::ReadAllText($hubDockVue)
  $runtimeNow=[IO.File]::ReadAllText($runtimeTs)
  $tauriNow=[IO.File]::ReadAllText($tauriLib)
  $hubNow=[IO.File]::ReadAllText($hubLib)

  $audits=@(
    [pscustomobject]@{Name='Package Browser shell';Pass=$browserNow.Contains('MOTHERSHIP EQUIPMENT DOCK')},
    [pscustomobject]@{Name='Install action';Pass=$browserNow.Contains("perform(pkg, 'INSTALL')")},
    [pscustomobject]@{Name='Enable action';Pass=$browserNow.Contains("perform(pkg, 'ENABLE')")},
    [pscustomobject]@{Name='Disable action';Pass=$browserNow.Contains("perform(pkg, 'DISABLE')")},
    [pscustomobject]@{Name='Uninstall action';Pass=$browserNow.Contains("perform(pkg, 'UNINSTALL')")},
    [pscustomobject]@{Name='Unknown execution gated';Pass=$browserNow.Contains('EXECUTION GATED')},
    [pscustomobject]@{Name='No remote loader';Pass=(-not $browserNow.Contains('http://') -and -not $browserNow.Contains('https://'))},
    [pscustomobject]@{Name='Runtime IPC install';Pass=$runtimeNow.Contains("invoke<string>('vertex_hub_install'")},
    [pscustomobject]@{Name='Runtime IPC enable';Pass=$runtimeNow.Contains("invoke<string>('vertex_hub_set_enabled'")},
    [pscustomobject]@{Name='Runtime IPC uninstall';Pass=$runtimeNow.Contains("invoke<string>('vertex_hub_uninstall'")},
    [pscustomobject]@{Name='Tauri runtime state';Pass=$tauriNow.Contains('fn vertex_hub_runtime_state')},
    [pscustomobject]@{Name='Rust identity guard';Pass=$hubNow.Contains('fn hub_identity')},
    [pscustomobject]@{Name='Rust install contract';Pass=$hubNow.Contains('pub fn hub_runtime_install')},
    [pscustomobject]@{Name='Rust uninstall contract';Pass=$hubNow.Contains('pub fn hub_runtime_uninstall')}
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "Hot Install / Browser audit RED: $($audit.Name)"}
    Write-Host ("  {0,-30} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[10/13] RUNTIME PACKAGE HASH CROSS-CHECK" -ForegroundColor Yellow

  foreach($file in $manifestJson.files){
    $rel=[string]$file.path
    $installed=Join-Path $runtimePackage ($rel.Replace('/','\'))

    if(-not(Test-Path -LiteralPath $installed)){throw "Runtime installed file missing: $rel"}

    if((Sha256 $installed) -ne ([string]$file.sha256).ToLowerInvariant()){
      throw "Runtime installed hash RED: $rel"
    }
  }

  if((Sha256 (Join-Path $runtimePackage 'manifest.json')) -ne (Sha256 $sourceManifest)){
    throw 'Runtime manifest hash RED.'
  }

  Write-Host 'Runtime package SHA-256: VERIFIED' -ForegroundColor Green

  Write-Host "`n[11/13] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  RunChecked '[release] Tauri cargo check' {
    & $cargo.Source check --manifest-path $tauriCargo --all-targets
  }

  Push-Location $ui
  try{
    RunChecked '[release] final frontend build' {& $pnpm.Source build}
  }finally{Pop-Location}

  Write-Host "`n[12/13] FINAL RUNTIME CONTRACT CHECK" -ForegroundColor Yellow

  $stateCheck=Get-Content -LiteralPath $runtimeState -Raw | ConvertFrom-Json
  $installedState=@(
    $stateCheck.packages |
    Where-Object {
      [string]$_.package_id -eq $packageId -and
      [string]$_.version -eq $packageVersion
    }
  )

  if($installedState.Count -ne 1){throw 'Runtime state package entry missing.'}
  if(-not [bool]$installedState[0].enabled){throw 'Runtime state package is not enabled.'}

  Write-Host 'Runtime state source of truth : GREEN' -ForegroundColor Green
  Write-Host 'First package                : INSTALLED + ENABLED' -ForegroundColor Green

  Write-Host "`n[13/13] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.vertex-hub-hot-install-package-browser.v1'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VERTEXHUB HOT INSTALL / PACKAGE BROWSER'
    ui=[ordered]@{
      shell='FULLSCREEN_EQUIPMENT_DOCK'
      visual_language='GRAPHITE_VIOLET_CYAN_MOTHERSHIP'
      search='ONLINE'
      filters=@('ALL','INSTALLED','ENABLED','AVAILABLE')
      trust_inspector='ONLINE'
      activity_mirror='ONLINE'
      responsive='ACTIVE'
    }
    runtime=[ordered]@{
      root=$runtimeRoot
      state=$runtimeState
      audit=$runtimeAudit
      install='ONLINE'
      enable='ONLINE'
      disable='ONLINE'
      uninstall='ONLINE'
      bundled_hot_activation='ONLINE'
      unknown_code_execution='GATED'
    }
    security=[ordered]@{
      registry_validation='ENFORCED'
      manifest_sha256='ENFORCED'
      file_sha256='ENFORCED'
      identity_guard='ENFORCED'
      path_traversal='DENIED'
      remote_import='DENIED'
      arbitrary_shell='DENIED'
      controller_state_mutation='DENIED'
    }
    package=[ordered]@{
      package_id=$packageId
      version=$packageVersion
      runtime_installed=$true
      runtime_enabled=$true
      execution_mode='BUNDLED'
    }
    validation=[ordered]@{
      hub_runtime_lifecycle_test='GREEN'
      frontend_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
      runtime_hashes='VERIFIED'
    }
    next_target='VERTEXHUB MULTI-PACKAGE EQUIPMENT EXPANSION'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX — HOT INSTALL / PACKAGE BROWSER V1 GREEN
============================================================
 VertexHub Package Browser              ONLINE
 Premium Equipment Dock UI              ONLINE
 Search / Filters                       ONLINE
 Trust Inspector                        ONLINE
 Rust Runtime Equipment State           ONLINE
 Tauri Hot Install IPC                  ONLINE
 INSTALL                                ONLINE
 ENABLE                                 ONLINE
 DISABLE                                ONLINE
 UNINSTALL                              ONLINE
 Runtime Audit                          ONLINE
 Bundled Hot Activation                 ONLINE
 Unknown Code Execution                 GATED
 Registry Validation                    ENFORCED
 Package SHA-256                        VERIFIED
 Path Traversal                         DENIED
 Remote Runtime Import                  DENIED
 Arbitrary Shell                        DENIED
 Controller State Mutation              DENIED
 Tauri Check                            GREEN
 Frontend Typecheck                     GREEN
 Frontend Build                         GREEN
 Workspace Release Gate                 GREEN
------------------------------------------------------------
 PACKAGE: $packageId@$packageVersion
 STATE:   INSTALLED + ENABLED
 HUB UI:  MOTHERSHIP EQUIPMENT DOCK
 REPORT:  $report
------------------------------------------------------------
 NEXT TARGET: VERTEXHUB MULTI-PACKAGE EQUIPMENT EXPANSION
============================================================
 VERTEXHUB IS NOW A REAL EQUIPMENT DOCK
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VERTEXHUB HOT INSTALL / PACKAGE BROWSER RED — DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  foreach($p in @(
    $hubLib,$hubRuntimeTest,$tauriLib,$catalogTs,$runtimeTs,$hubDockVue,
    $runtimeState,$runtimeAudit
  )){
    if(Test-Path -LiteralPath $p){
      Copy-Item -LiteralPath $p -Destination (Join-Path $failed ([IO.Path]::GetFileName($p))) -Force -ErrorAction SilentlyContinue
    }
  }

  $restore=@(
    @('vsa-vertex-hub.lib.rs',$hubLib),
    @('vsa-shell-desktop.lib.rs',$tauriLib),
    @('catalog.ts',$catalogTs),
    @('runtime.ts',$runtimeTs),
    @('VertexHubDock.vue',$hubDockVue)
  )

  foreach($pair in $restore){
    $src=Join-Path $backup $pair[0]
    if(Test-Path -LiteralPath $src){
      Copy-Item -LiteralPath $src -Destination $pair[1] -Force
    }
  }

  if(Test-Path -LiteralPath $hubRuntimeTest){
    Remove-Item -LiteralPath $hubRuntimeTest -Force -ErrorAction SilentlyContinue
  }

  $stateBackup=Join-Path $backup 'runtime-state.json'
  $auditBackup=Join-Path $backup 'runtime-audit.ndjson'

  if(Test-Path -LiteralPath $stateBackup){
    Copy-Item -LiteralPath $stateBackup -Destination $runtimeState -Force
  }elseif(Test-Path -LiteralPath $runtimeState){
    Remove-Item -LiteralPath $runtimeState -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $auditBackup){
    Copy-Item -LiteralPath $auditBackup -Destination $runtimeAudit -Force
  }elseif(Test-Path -LiteralPath $runtimeAudit){
    Remove-Item -LiteralPath $runtimeAudit -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $runtimePackage){
    Remove-Item -LiteralPath $runtimePackage -Recurse -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $runtimeRoot){
    $children=@(Get-ChildItem -LiteralPath $runtimeRoot -Force -ErrorAction SilentlyContinue)
    if($children.Count -eq 0){
      Remove-Item -LiteralPath $runtimeRoot -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Host 'Hub core rollback              : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Tauri rollback                 : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Package Browser rollback       : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Runtime state rollback         : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Original Hub registry/package  : UNTOUCHED' -ForegroundColor Yellow
  Write-Host 'V3 loader baseline             : RESTORED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}