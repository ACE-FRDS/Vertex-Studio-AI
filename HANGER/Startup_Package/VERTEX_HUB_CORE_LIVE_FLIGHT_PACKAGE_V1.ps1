& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC — VERTEX HUB CORE + LIVE FLIGHT PACKAGE V1
# Windows PowerShell 5.1 compatible
#
# Creates the first formal VertexHub package:
#   vertex.live-flight-panel@1.0.0
#
# Doctrine:
#   Runtime Bus = live nervous system (unchanged)
#   VertexHub   = package/component/schema distribution + integrity
#
# Safety:
#   - CURRENT v0.2 ONLY
#   - LEGACY untouched
#   - V11 GREEN baseline required
#   - package paths are relative + traversal denied
#   - SHA-256 manifest verification
#   - Rust validator
#   - workspace release gate
#   - atomic rollback on RED
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$coreCargo=Join-Path $core 'Cargo.toml'
$reports=Join-Path $core '_vertex_reports'

$livePanel=Join-Path $ui 'src\vertex-editor\VertexLiveFlightPanel.vue'
$liveTransport=Join-Path $ui 'src\vertex-editor\transport.ts'
$mothershipLib=Join-Path $core 'crates\vsa-mothership\src\lib.rs'
$liveLatest=Join-Path $core '_vertex_runtime\live_session_latest.json'

$hubRoot=Join-Path $core 'vertex-hub'
$hubPackages=Join-Path $hubRoot 'packages'
$packageId='vertex.live-flight-panel'
$packageVersion='1.0.0'
$packageRoot=Join-Path (Join-Path $hubPackages $packageId) $packageVersion
$packageSrc=Join-Path $packageRoot 'src'
$packageContracts=Join-Path $packageRoot 'contracts'
$manifestPath=Join-Path $packageRoot 'manifest.json'
$registryPath=Join-Path $hubRoot 'registry.json'

$hubCrate=Join-Path $core 'crates\vsa-vertex-hub'
$hubCrateCargo=Join-Path $hubCrate 'Cargo.toml'
$hubCrateLib=Join-Path $hubCrate 'src\lib.rs'
$hubCrateTest=Join-Path $hubCrate 'tests\live_flight_package.rs'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VERTEX_HUB_LIVE_FLIGHT_V1_BACKUP.$stamp"
$failed=Join-Path $reports "VERTEX_HUB_LIVE_FLIGHT_V1_FAILED.$stamp"
$report=Join-Path $reports "VERTEX_HUB_LIVE_FLIGHT_V1.$stamp.json"

$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}

function RequireCommand([string]$Name){
  $c=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $c){throw "Missing command: $Name"}
  return $c
}

function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}

function CopyBackup([string]$Path,[string]$Name){
  if(Test-Path -LiteralPath $Path){
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $Name) -Force
  }
}

function AssertSafeRelative([string]$Rel){
  if([string]::IsNullOrWhiteSpace($Rel)){throw 'Empty relative path denied.'}
  if([IO.Path]::IsPathRooted($Rel)){throw "Absolute package path denied: $Rel"}
  $segments=$Rel -split '[\\/]'
  if($segments -contains '..'){throw "Package traversal denied: $Rel"}
}

function Sha256([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Hash target missing: $Path"}
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

Write-Host @'
============================================================
 VERTEX — VERTEX HUB CORE + LIVE FLIGHT PACKAGE V1
 FIRST FORMAL VERTEXHUB COMPONENT / SCHEMA PACKAGE
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$coreCargo,$reports,
  $livePanel,$liveTransport,$mothershipLib,$liveLatest
)){
  if(-not(Test-Path -LiteralPath $required)){throw "Required V11 artifact missing: $required"}
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/10] V11 GREEN BASELINE LOCK" -ForegroundColor Yellow

$panelText=[IO.File]::ReadAllText($livePanel)
$transportText=[IO.File]::ReadAllText($liveTransport)
$mshipText=[IO.File]::ReadAllText($mothershipLib)
$latestText=[IO.File]::ReadAllText($liveLatest)

foreach($check in @(
  @('Live Flight Panel source',$panelText.Contains('LIVE FLIGHT')),
  @('Live transport latest',$transportText.Contains('liveSessionLatest')),
  @('Live transport tail',$transportText.Contains('liveSessionTail')),
  @('Mothership live bus marker',$mshipText.Contains('VERTEX LIVE SESSION BUS V1')),
  @('Live schema',$latestText.Contains('"schema":"vertex.mothership.live-session.v1"'))
)){
  if(-not $check[1]){throw "V11 baseline invariant missing: $($check[0])"}
  Write-Host ("  {0,-32} GREEN" -f $check[0]) -ForegroundColor Green
}

Push-Location $ui
try{
  RunChecked '[baseline] frontend build' {& $pnpm.Source build}
}finally{Pop-Location}

RunChecked '[baseline] workspace cargo check' {
  & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
}

if(Test-Path -LiteralPath $packageRoot){
  throw "VertexHub package already exists: $packageRoot"
}
if(Test-Path -LiteralPath $hubCrate){
  throw "VertexHub crate already exists: $hubCrate"
}

Write-Host "`n[1/10] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
CopyBackup $coreCargo 'ProgramSource.Cargo.toml'
CopyBackup $registryPath 'registry.json'
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/10] CREATE VERTEXHUB PACKAGE ROOT" -ForegroundColor Yellow

  New-Item -ItemType Directory -Path $packageSrc -Force|Out-Null
  New-Item -ItemType Directory -Path $packageContracts -Force|Out-Null

  $componentDest=Join-Path $packageSrc 'VertexLiveFlightPanel.vue'
  $adapterDest=Join-Path $packageSrc 'hub-transport.ts'
  $schemaDest=Join-Path $packageContracts 'live-session.v1.schema.json'
  $readmeDest=Join-Path $packageRoot 'README.md'

  $packagedPanel=$panelText.Replace("from './transport'","from './hub-transport'")
  if($packagedPanel -eq $panelText){
    throw 'Live Flight Panel transport import anchor not found.'
  }
  WriteUtf8 $componentDest $packagedPanel

  $adapter=@'
import { invoke } from '@tauri-apps/api/core'

export interface LiveSessionSnapshot {
  schema: string
  kind: 'wave_scheduled' | 'wave_completed' | string
  timestamp_ms: number
  session?: {
    session_id?: string
    status?: string
    completed_waves?: number
  }
  wave?: {
    sequence?: number
    wave_id?: string
    ready?: string[]
    blocked?: string[]
    waiting?: string[]
    missions?: string[]
    resulting_status?: string
  }
  dispatch?: {
    dispatch_id?: string
    mission_set?: string[]
    executions?: Array<{
      execution_id?: string
    }>
    confirmed_missions?: string[]
    process_result_count?: number
  }
  genesis?: {
    event_count?: number
  }
  vsp?: {
    checkpoint_debug?: string
  } | null
}

export function desktop(): boolean {
  return Boolean((window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__)
}

export async function liveSessionLatest(): Promise<LiveSessionSnapshot | null> {
  const raw = await invoke<string>('vertex_live_session_latest')
  if (!raw.trim()) return null
  return JSON.parse(raw) as LiveSessionSnapshot
}

export async function liveSessionTail(limit = 40): Promise<LiveSessionSnapshot[]> {
  const lines = await invoke<string[]>('vertex_live_session_tail', { limit })
  const snapshots: LiveSessionSnapshot[] = []

  for (const line of lines) {
    try {
      snapshots.push(JSON.parse(line) as LiveSessionSnapshot)
    } catch {
      // Malformed telemetry never becomes controller state.
    }
  }

  return snapshots
}
'@
  WriteUtf8 $adapterDest $adapter

  $schema=@'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "vertex://schemas/mothership/live-session/v1",
  "title": "Vertex Mothership Live Session V1",
  "type": "object",
  "required": ["schema", "kind", "timestamp_ms"],
  "properties": {
    "schema": {
      "const": "vertex.mothership.live-session.v1"
    },
    "kind": {
      "type": "string",
      "enum": ["wave_scheduled", "wave_completed"]
    },
    "timestamp_ms": {
      "type": "integer",
      "minimum": 0
    },
    "session": {
      "type": "object",
      "properties": {
        "session_id": { "type": "string" },
        "status": { "type": "string" },
        "completed_waves": { "type": "integer", "minimum": 0 }
      },
      "additionalProperties": true
    },
    "wave": {
      "type": "object",
      "properties": {
        "sequence": { "type": "integer", "minimum": 0 },
        "wave_id": { "type": "string" },
        "ready": { "type": "array", "items": { "type": "string" } },
        "blocked": { "type": "array", "items": { "type": "string" } },
        "waiting": { "type": "array", "items": { "type": "string" } },
        "missions": { "type": "array", "items": { "type": "string" } },
        "resulting_status": { "type": "string" }
      },
      "additionalProperties": true
    },
    "dispatch": {
      "type": "object",
      "properties": {
        "dispatch_id": { "type": "string" },
        "mission_set": { "type": "array", "items": { "type": "string" } },
        "executions": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "execution_id": { "type": "string" }
            },
            "additionalProperties": true
          }
        },
        "confirmed_missions": { "type": "array", "items": { "type": "string" } },
        "process_result_count": { "type": "integer", "minimum": 0 }
      },
      "additionalProperties": true
    },
    "genesis": {
      "type": "object",
      "properties": {
        "event_count": { "type": "integer", "minimum": 0 }
      },
      "additionalProperties": true
    },
    "vsp": {
      "type": ["object", "null"],
      "properties": {
        "checkpoint_debug": { "type": "string" }
      },
      "additionalProperties": true
    }
  },
  "additionalProperties": true
}
'@
  WriteUtf8 $schemaDest $schema

  $readme=@'
# Vertex Live Flight Panel

Formal VertexHub package for the VSA Editor Live Flight telemetry surface.

## Package

- ID: `vertex.live-flight-panel`
- Version: `1.0.0`
- Kind: `ui.component`
- Scope: `vsa.editor`
- Runtime: Vue 3 + Tauri 2
- Telemetry: `vertex.mothership.live-session.v1`

## Runtime boundary

VertexHub does **not** sit in the live control path.

`Mothership -> Runtime Bus -> Tauri IPC -> Live Flight Panel`

VertexHub stores and verifies the reusable component, contract, and distribution metadata.

## Safety

The package is read-only with respect to Mothership control state. It consumes only:

- `vertex_live_session_latest`
- `vertex_live_session_tail`

It does not create or mutate a `FleetControllerSession`.
'@
  WriteUtf8 $readmeDest $readme

  Write-Host "Hub package root: $packageRoot" -ForegroundColor Green

  Write-Host "`n[3/10] BUILD PACKAGE MANIFEST + SHA-256" -ForegroundColor Yellow

  $packageFiles=@(
    [pscustomobject]@{Rel='README.md';Path=$readmeDest;Role='documentation'},
    [pscustomobject]@{Rel='src/VertexLiveFlightPanel.vue';Path=$componentDest;Role='component'},
    [pscustomobject]@{Rel='src/hub-transport.ts';Path=$adapterDest;Role='transport'},
    [pscustomobject]@{Rel='contracts/live-session.v1.schema.json';Path=$schemaDest;Role='schema'}
  )

  $fileRecords=@()
  foreach($f in $packageFiles){
    AssertSafeRelative $f.Rel
    $info=Get-Item -LiteralPath $f.Path
    $fileRecords+=@(
      [ordered]@{
        path=$f.Rel
        role=$f.Role
        sha256=Sha256 $f.Path
        bytes=[int64]$info.Length
      }
    )
  }

  $manifest=[ordered]@{
    schema='vertex.hub.package.v1'
    package_id=$packageId
    display_name='Vertex Live Flight Panel'
    version=$packageVersion
    kind='ui.component'
    scope='vsa.editor'
    publisher='Vertex'
    runtime=[ordered]@{
      framework='vue3'
      desktop='tauri2'
    }
    entrypoints=[ordered]@{
      component='src/VertexLiveFlightPanel.vue'
      transport='src/hub-transport.ts'
    }
    contracts=@(
      [ordered]@{
        schema='vertex.mothership.live-session.v1'
        file='contracts/live-session.v1.schema.json'
      }
    )
    permissions=@(
      'vertex_live_session_latest',
      'vertex_live_session_tail'
    )
    safety=[ordered]@{
      controller_state_mutation=$false
      arbitrary_shell=$false
      workspace_write=$false
      secret_access=$false
      telemetry_read_only=$true
    }
    files=$fileRecords
  }

  WriteUtf8 $manifestPath ($manifest|ConvertTo-Json -Depth 12)
  $manifestHash=Sha256 $manifestPath
  Write-Host "Manifest SHA-256: $manifestHash" -ForegroundColor Green

  Write-Host "`n[4/10] CREATE VERTEXHUB REGISTRY" -ForegroundColor Yellow

  New-Item -ItemType Directory -Path $hubRoot -Force|Out-Null

  $registry=[ordered]@{
    schema='vertex.hub.registry.v1'
    generated_at=(Get-Date).ToString('o')
    packages=@(
      [ordered]@{
        package_id=$packageId
        version=$packageVersion
        kind='ui.component'
        status='registered'
        manifest="packages/$packageId/$packageVersion/manifest.json"
        manifest_sha256=$manifestHash
      }
    )
  }
  WriteUtf8 $registryPath ($registry|ConvertTo-Json -Depth 10)

  Write-Host "Registry: $registryPath" -ForegroundColor Green

  Write-Host "`n[5/10] CREATE RUST VERTEXHUB VALIDATOR" -ForegroundColor Yellow

  New-Item -ItemType Directory -Path (Join-Path $hubCrate 'src') -Force|Out-Null
  New-Item -ItemType Directory -Path (Join-Path $hubCrate 'tests') -Force|Out-Null

  $crateCargo=@'
[package]
name = "vsa-vertex-hub"
version = "0.1.0"
edition = "2024"
rust-version = "1.97.1"

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha2 = "0.10"
'@
  WriteUtf8 $hubCrateCargo $crateCargo

  $crateLib=@'
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Component, Path, PathBuf};

pub const HUB_PACKAGE_SCHEMA: &str = "vertex.hub.package.v1";
pub const HUB_REGISTRY_SCHEMA: &str = "vertex.hub.registry.v1";

#[derive(Debug, Deserialize)]
pub struct HubPackageFile {
    pub path: String,
    pub sha256: String,
    pub bytes: u64,
}

#[derive(Debug, Deserialize)]
pub struct HubPackageManifest {
    pub schema: String,
    pub package_id: String,
    pub version: String,
    pub files: Vec<HubPackageFile>,
}

#[derive(Debug, Deserialize)]
pub struct HubRegistryEntry {
    pub package_id: String,
    pub version: String,
    pub status: String,
    pub manifest: String,
    pub manifest_sha256: String,
}

#[derive(Debug, Deserialize)]
pub struct HubRegistry {
    pub schema: String,
    pub packages: Vec<HubRegistryEntry>,
}

#[derive(Debug)]
pub struct PackageValidation {
    pub package_id: String,
    pub version: String,
    pub file_count: usize,
}

fn safe_relative(value: &str) -> Result<PathBuf, String> {
    let path = Path::new(value);

    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(format!("unsafe Hub path: {value}"));
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            _ => return Err(format!("unsafe Hub path component: {value}")),
        }
    }

    Ok(path.to_path_buf())
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let bytes = fs::read(path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;

    let digest = Sha256::digest(bytes);
    Ok(digest.iter().map(|byte| format!("{byte:02x}")).collect())
}

pub fn validate_package_dir(package_root: &Path) -> Result<PackageValidation, String> {
    let manifest_path = package_root.join("manifest.json");
    let manifest: HubPackageManifest = serde_json::from_slice(
        &fs::read(&manifest_path)
            .map_err(|error| format!("cannot read {}: {error}", manifest_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub manifest JSON: {error}"))?;

    if manifest.schema != HUB_PACKAGE_SCHEMA {
        return Err(format!("unsupported Hub package schema: {}", manifest.schema));
    }

    for file in &manifest.files {
        let relative = safe_relative(&file.path)?;
        let full = package_root.join(relative);

        let metadata = fs::metadata(&full)
            .map_err(|error| format!("package file missing {}: {error}", full.display()))?;

        if metadata.len() != file.bytes {
            return Err(format!(
                "package file size mismatch {}: manifest={} actual={}",
                full.display(),
                file.bytes,
                metadata.len()
            ));
        }

        let actual = sha256_file(&full)?;
        if actual != file.sha256.to_ascii_lowercase() {
            return Err(format!("package SHA-256 mismatch: {}", full.display()));
        }
    }

    Ok(PackageValidation {
        package_id: manifest.package_id,
        version: manifest.version,
        file_count: manifest.files.len(),
    })
}

pub fn validate_registry(hub_root: &Path) -> Result<Vec<PackageValidation>, String> {
    let registry_path = hub_root.join("registry.json");
    let registry: HubRegistry = serde_json::from_slice(
        &fs::read(&registry_path)
            .map_err(|error| format!("cannot read {}: {error}", registry_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub registry JSON: {error}"))?;

    if registry.schema != HUB_REGISTRY_SCHEMA {
        return Err(format!("unsupported Hub registry schema: {}", registry.schema));
    }

    let mut reports = Vec::new();

    for entry in registry.packages {
        if entry.status != "registered" {
            return Err(format!(
                "Hub package is not registered: {}@{}",
                entry.package_id, entry.version
            ));
        }

        let manifest_rel = safe_relative(&entry.manifest)?;
        let manifest_path = hub_root.join(&manifest_rel);

        let actual_manifest_hash = sha256_file(&manifest_path)?;
        if actual_manifest_hash != entry.manifest_sha256.to_ascii_lowercase() {
            return Err(format!(
                "Hub manifest SHA-256 mismatch: {}@{}",
                entry.package_id, entry.version
            ));
        }

        let package_root = manifest_path
            .parent()
            .ok_or_else(|| format!("manifest has no package root: {}", manifest_path.display()))?;

        let report = validate_package_dir(package_root)?;

        if report.package_id != entry.package_id || report.version != entry.version {
            return Err(format!(
                "Hub registry identity mismatch: {}@{}",
                entry.package_id, entry.version
            ));
        }

        reports.push(report);
    }

    Ok(reports)
}

#[cfg(test)]
mod tests {
    use super::safe_relative;

    #[test]
    fn hub_path_traversal_is_denied() {
        assert!(safe_relative("../secret").is_err());
        assert!(safe_relative("/absolute").is_err());
        assert!(safe_relative("contracts/live-session.json").is_ok());
    }
}
'@
  WriteUtf8 $hubCrateLib $crateLib

  $crateTest=@'
use std::path::Path;
use vsa_vertex_hub::validate_registry;

#[test]
fn live_flight_package_is_registered_and_integrity_verified() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..");

    let hub = workspace.join("vertex-hub");
    let reports = validate_registry(&hub).expect("VertexHub registry must validate");

    let package = reports
        .iter()
        .find(|report| {
            report.package_id == "vertex.live-flight-panel"
                && report.version == "1.0.0"
        })
        .expect("Live Flight package must be registered");

    assert_eq!(package.file_count, 4);
}
'@
  WriteUtf8 $hubCrateTest $crateTest

  Write-Host "Validator crate: $hubCrate" -ForegroundColor Green

  Write-Host "`n[6/10] DOCK HUB CRATE INTO WORKSPACE" -ForegroundColor Yellow

  $cargoText=[IO.File]::ReadAllText($coreCargo)
  $workspaceMemberChanged=$false

  $memberCoverage=(
    $cargoText -match '["'']crates/\*["'']' -or
    $cargoText -match '["'']crates/vsa-vertex-hub["'']'
  )

  if($memberCoverage){
    Write-Host 'Workspace member coverage: ALREADY PRESENT' -ForegroundColor Green
  }else{
    $membersMatch=[regex]::Match(
      $cargoText,
      '(?ms)(?<prefix>^\s*members\s*=\s*\[)(?<body>.*?)(?<suffix>\])'
    )

    if(-not $membersMatch.Success){
      throw 'Workspace members array not found; refusing unsafe Cargo.toml mutation.'
    }

    $body=$membersMatch.Groups['body'].Value.TrimEnd()
    $separator=''
    if($body.Trim().Length -gt 0){
      if(-not $body.TrimEnd().EndsWith(',')){$separator=','}
      $separator+="`r`n"
    }

    $replacement=
      $membersMatch.Groups['prefix'].Value +
      $body +
      $separator +
      '  "crates/vsa-vertex-hub",' +
      "`r`n" +
      $membersMatch.Groups['suffix'].Value

    $cargoText=
      $cargoText.Substring(0,$membersMatch.Index) +
      $replacement +
      $cargoText.Substring($membersMatch.Index+$membersMatch.Length)

    WriteUtf8 $coreCargo $cargoText
    $workspaceMemberChanged=$true
    Write-Host 'Workspace member: vsa-vertex-hub ADDED' -ForegroundColor Green
  }

  Write-Host "`n[7/10] HUB VALIDATOR TARGETED TEST" -ForegroundColor Yellow

  RunChecked '[hub] cargo check' {
    & $cargo.Source check --manifest-path $hubCrateCargo --all-targets
  }

  RunChecked '[hub] package registry integrity test' {
    & $cargo.Source test --manifest-path $hubCrateCargo live_flight_package_is_registered_and_integrity_verified -- --exact
  }

  RunChecked '[hub] path safety test' {
    & $cargo.Source test --manifest-path $hubCrateCargo hub_path_traversal_is_denied -- --exact
  }

  Write-Host "`n[8/10] PACKAGE SOURCE STATIC VERIFICATION" -ForegroundColor Yellow

  $packagePanel=[IO.File]::ReadAllText($componentDest)
  $packageAdapter=[IO.File]::ReadAllText($adapterDest)
  $packageSchema=[IO.File]::ReadAllText($schemaDest)

  foreach($verification in @(
    @('component uses Hub transport',$packagePanel.Contains("from './hub-transport'")),
    @('component remains Live Flight',$packagePanel.Contains('LIVE FLIGHT')),
    @('adapter latest command',$packageAdapter.Contains('vertex_live_session_latest')),
    @('adapter tail command',$packageAdapter.Contains('vertex_live_session_tail')),
    @('schema locked',$packageSchema.Contains('vertex.mothership.live-session.v1'))
  )){
    if(-not $verification[1]){throw "Hub package static verification RED: $($verification[0])"}
    Write-Host ("  {0,-32} GREEN" -f $verification[0]) -ForegroundColor Green
  }

  Write-Host "`n[9/10] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  Push-Location $ui
  try{
    RunChecked '[release] frontend build unchanged' {& $pnpm.Source build}
  }finally{Pop-Location}

  Write-Host "`n[10/10] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.vertex-hub-live-flight-package.v1'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    hub=[ordered]@{
      root=$hubRoot
      registry=$registryPath
      registry_schema='vertex.hub.registry.v1'
      validator_crate=$hubCrate
    }
    package=[ordered]@{
      package_id=$packageId
      version=$packageVersion
      kind='ui.component'
      root=$packageRoot
      manifest=$manifestPath
      manifest_sha256=$manifestHash
      contract='vertex.mothership.live-session.v1'
      component='src/VertexLiveFlightPanel.vue'
      transport='src/hub-transport.ts'
      file_count=4
    }
    runtime_boundary=[ordered]@{
      live_path='Mothership -> Runtime Bus -> Tauri IPC -> Editor'
      hub_in_live_path=$false
      controller_state_mutation=$false
    }
    validation=[ordered]@{
      package_hashes='GREEN'
      registry_hash='GREEN'
      rust_validator='GREEN'
      traversal_guard='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
      frontend_build='GREEN'
    }
    legacy='UNTOUCHED'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX — VERTEXHUB LIVE FLIGHT PACKAGE GREEN
============================================================
 VertexHub Core                         ONLINE
 Hub Registry v1                       ONLINE
 Rust Hub Validator                    ONLINE
 Package                               $packageId@$packageVersion
 Kind                                  ui.component
 Component Source                      PACKAGED
 Tauri Transport Adapter               PACKAGED
 live-session.v1 Schema                PACKAGED
 Package SHA-256                       VERIFIED
 Manifest SHA-256                      VERIFIED
 Path Traversal                        DENIED
 Controller State Mutation             DENIED
 Runtime Bus Path                      UNCHANGED
 Workspace Release Gate                GREEN
 Frontend Build                        GREEN
 LEGACY                                UNTOUCHED
------------------------------------------------------------
 HUB:      $hubRoot
 PACKAGE:  $packageRoot
 REGISTRY: $registryPath
 REPORT:   $report
------------------------------------------------------------
 NEXT TARGET: VERTEXHUB INSTALLER / LOADER
============================================================
 FIRST VERTEXHUB PACKAGE: REGISTERED
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VERTEXHUB PACKAGE V1 RED — DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  foreach($p in @($manifestPath,$registryPath,$hubCrateCargo,$hubCrateLib,$hubCrateTest)){
    if(Test-Path -LiteralPath $p){
      Copy-Item -LiteralPath $p -Destination (Join-Path $failed ([IO.Path]::GetFileName($p))) -Force -ErrorAction SilentlyContinue
    }
  }

  $cargoBackup=Join-Path $backup 'ProgramSource.Cargo.toml'
  if(Test-Path -LiteralPath $cargoBackup){
    Copy-Item -LiteralPath $cargoBackup -Destination $coreCargo -Force
  }

  if(Test-Path -LiteralPath $hubCrate){
    Remove-Item -LiteralPath $hubCrate -Recurse -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $packageRoot){
    Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $hubRoot){
    $remaining=@(Get-ChildItem -LiteralPath $hubRoot -Force -ErrorAction SilentlyContinue)
    if($remaining.Count -eq 0){
      Remove-Item -LiteralPath $hubRoot -Force -ErrorAction SilentlyContinue
    }elseif(
      $remaining.Count -eq 2 -and
      (Test-Path -LiteralPath $registryPath) -and
      (Test-Path -LiteralPath $hubPackages)
    ){
      Remove-Item -LiteralPath $registryPath -Force -ErrorAction SilentlyContinue
      if(Test-Path -LiteralPath $hubPackages){
        $pkgChildren=@(Get-ChildItem -LiteralPath $hubPackages -Force -ErrorAction SilentlyContinue)
        if($pkgChildren.Count -eq 0){
          Remove-Item -LiteralPath $hubPackages -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }

  Write-Host 'ProgramSource Cargo.toml rollback: COMPLETE' -ForegroundColor Yellow
  Write-Host 'VertexHub new crate/package rollback: COMPLETE' -ForegroundColor Yellow
  Write-Host 'V11 Live Runtime: UNTOUCHED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}