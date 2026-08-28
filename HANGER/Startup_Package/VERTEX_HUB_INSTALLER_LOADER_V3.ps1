& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC — VERTEXHUB INSTALLER / LOADER V3
# Windows PowerShell 5.1 compatible
#
# Goal:
#   Convert the first registered Hub package from "stored" to
#   "validated -> installed -> loaded -> runtime-toggleable".
#
# Safety / architecture:
#   - CURRENT v0.2 only
#   - V11 Live Runtime unchanged
#   - VertexHub registry remains source of package truth
#   - Rust validator gates install
#   - package files copied into Vite source tree only after hash verification
#   - generated static catalog (no arbitrary runtime code import)
#   - runtime enable/disable only; controller state is read-only
#   - no arbitrary URL / shell / path loading
#   - RED => rollback
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
$hubCrateCargo=Join-Path $hubCrate 'Cargo.toml'
$hubCrateLib=Join-Path $hubCrate 'src\lib.rs'

$packageId='vertex.live-flight-panel'
$packageVersion='1.0.0'
$sourcePackage=Join-Path (Join-Path (Join-Path $hubRoot 'packages') $packageId) $packageVersion
$sourceManifest=Join-Path $sourcePackage 'manifest.json'

$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriLib=Join-Path $ui 'src-tauri\src\lib.rs'

$loaderRoot=Join-Path $ui 'src\vertex-hub'
$installedRoot=Join-Path $loaderRoot 'packages'
$installedPackage=Join-Path (Join-Path $installedRoot $packageId) $packageVersion
$catalogTs=Join-Path $loaderRoot 'catalog.ts'
$runtimeTs=Join-Path $loaderRoot 'runtime.ts'
$hubDockVue=Join-Path $loaderRoot 'VertexHubDock.vue'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VERTEX_HUB_INSTALLER_LOADER_V3_BACKUP.$stamp"
$failed=Join-Path $reports "VERTEX_HUB_INSTALLER_LOADER_V3_FAILED.$stamp"
$report=Join-Path $reports "VERTEX_HUB_INSTALLER_LOADER_V3.$stamp.json"

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

function BackupFile([string]$Path,[string]$Name){
  if(Test-Path -LiteralPath $Path){
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $Name) -Force
  }
}

function Sha256([string]$Path){
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function AssertSafeRelative([string]$Rel){
  if([string]::IsNullOrWhiteSpace($Rel)){throw 'Empty relative path denied.'}
  if([IO.Path]::IsPathRooted($Rel)){throw "Absolute package path denied: $Rel"}
  foreach($segment in ($Rel -split '[\\/]')){
    if($segment -eq '..'){throw "Package traversal denied: $Rel"}
  }
}

Write-Host @'
============================================================
 VERTEX — VERTEXHUB INSTALLER / LOADER V3
 VALIDATE -> INSTALL -> CATALOG -> LOAD -> TOGGLE
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$coreCargo,
  $hubRoot,$hubRegistry,$hubCrate,$hubCrateCargo,$hubCrateLib,
  $sourcePackage,$sourceManifest,$editor,$tauriCargo,$tauriLib
)){
  if(-not(Test-Path -LiteralPath $required)){throw "Required Hub/V11 artifact missing: $required"}
}

if(Test-Path -LiteralPath $loaderRoot){
  throw "VertexHub loader source already exists: $loaderRoot"
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'
$rustfmt=RequireCommand 'rustfmt'

Write-Host "`n[0/12] GREEN BASELINE / REGISTERED PACKAGE LOCK" -ForegroundColor Yellow

$registryText=[IO.File]::ReadAllText($hubRegistry)
$manifestText=[IO.File]::ReadAllText($sourceManifest)

try{
  $registryJson=$registryText | ConvertFrom-Json
}catch{
  throw "VertexHub registry JSON parse failed: $($_.Exception.Message)"
}

try{
  $manifestJson=$manifestText | ConvertFrom-Json
}catch{
  throw "VertexHub package manifest JSON parse failed: $($_.Exception.Message)"
}

if([string]$registryJson.schema -ne 'vertex.hub.registry.v1'){
  throw "VertexHub registry schema mismatch: $($registryJson.schema)"
}

$registeredEntries=@(
  $registryJson.packages |
  Where-Object {
    [string]$_.package_id -eq $packageId -and
    [string]$_.version -eq $packageVersion
  }
)

if($registeredEntries.Count -ne 1){
  throw "Expected exactly one registered package entry for $packageId@$packageVersion; found $($registeredEntries.Count)"
}

$registeredEntry=$registeredEntries[0]

if([string]$registeredEntry.status -ne 'registered'){
  throw "Hub package status is not registered: $($registeredEntry.status)"
}

if([string]$manifestJson.schema -ne 'vertex.hub.package.v1'){
  throw "Hub package manifest schema mismatch: $($manifestJson.schema)"
}

if([string]$manifestJson.package_id -ne $packageId){
  throw "Hub package manifest package_id mismatch: $($manifestJson.package_id)"
}

if([string]$manifestJson.version -ne $packageVersion){
  throw "Hub package manifest version mismatch: $($manifestJson.version)"
}

$actualManifestHash=Sha256 $sourceManifest
$registryManifestHash=([string]$registeredEntry.manifest_sha256).ToLowerInvariant()

if($registryManifestHash -ne $actualManifestHash){
  throw "Hub registry manifest SHA-256 mismatch: registry=$registryManifestHash actual=$actualManifestHash"
}

Write-Host ("  Registry schema                    " + [string]$registryJson.schema) -ForegroundColor Green
Write-Host ("  Registered package                 " + $packageId + '@' + $packageVersion) -ForegroundColor Green
Write-Host ("  Package status                     " + [string]$registeredEntry.status) -ForegroundColor Green
Write-Host ("  Manifest schema                    " + [string]$manifestJson.schema) -ForegroundColor Green
Write-Host ("  Manifest SHA-256                   VERIFIED") -ForegroundColor Green

RunChecked '[baseline] Hub integrity test' {
  & $cargo.Source test --manifest-path $hubCrateCargo live_flight_package_is_registered_and_integrity_verified -- --exact
}

RunChecked '[baseline] workspace check' {
  & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
}

Push-Location $ui
try{
  RunChecked '[baseline] frontend build' {& $pnpm.Source build}
}finally{Pop-Location}

Write-Host "`n[1/12] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
BackupFile $hubCrateCargo 'vsa-vertex-hub.Cargo.toml'
BackupFile $hubCrateLib 'vsa-vertex-hub.lib.rs'
BackupFile $tauriCargo 'vsa-shell-desktop.Cargo.toml'
BackupFile $tauriLib 'vsa-shell-desktop.lib.rs'
BackupFile $editor 'VertexEditorDock.vue'
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/12] EXTEND RUST HUB CORE WITH INSTALLER CONTRACT" -ForegroundColor Yellow

  $hubLib=[IO.File]::ReadAllText($hubCrateLib)
  if($hubLib.Contains('pub fn install_registered_package')){throw 'Hub installer contract already exists.'}

  $installerRust=@'

// VERTEX HUB INSTALLER V1
pub fn install_registered_package(
    hub_root: &Path,
    install_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<PackageValidation, String> {
    let registry_path = hub_root.join("registry.json");
    let registry: HubRegistry = serde_json::from_slice(
        &fs::read(&registry_path)
            .map_err(|error| format!("cannot read {}: {error}", registry_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub registry JSON: {error}"))?;

    if registry.schema != HUB_REGISTRY_SCHEMA {
        return Err(format!("unsupported Hub registry schema: {}", registry.schema));
    }

    let entry = registry
        .packages
        .iter()
        .find(|entry| entry.package_id == package_id && entry.version == version)
        .ok_or_else(|| format!("Hub package is not registered: {package_id}@{version}"))?;

    if entry.status != "registered" {
        return Err(format!("Hub package is not installable: {package_id}@{version}"));
    }

    let manifest_rel = safe_relative(&entry.manifest)?;
    let source_manifest = hub_root.join(&manifest_rel);

    let actual_manifest_hash = sha256_file(&source_manifest)?;
    if actual_manifest_hash != entry.manifest_sha256.to_ascii_lowercase() {
        return Err(format!("Hub manifest hash mismatch: {package_id}@{version}"));
    }

    let source_root = source_manifest
        .parent()
        .ok_or_else(|| format!("invalid source package root: {}", source_manifest.display()))?;

    let validated = validate_package_dir(source_root)?;

    if validated.package_id != package_id || validated.version != version {
        return Err(format!(
            "Hub package identity mismatch: requested={package_id}@{version} actual={}@{}",
            validated.package_id, validated.version
        ));
    }

    let manifest: HubPackageManifest = serde_json::from_slice(
        &fs::read(&source_manifest)
            .map_err(|error| format!("cannot read {}: {error}", source_manifest.display()))?,
    )
    .map_err(|error| format!("invalid Hub manifest JSON: {error}"))?;

    if install_root.exists() {
        return Err(format!(
            "Hub install destination already exists: {}",
            install_root.display()
        ));
    }

    fs::create_dir_all(install_root)
        .map_err(|error| format!("cannot create {}: {error}", install_root.display()))?;

    let rollback = || {
        let _ = fs::remove_dir_all(install_root);
    };

    for file in &manifest.files {
        let relative = match safe_relative(&file.path) {
            Ok(path) => path,
            Err(error) => {
                rollback();
                return Err(error);
            }
        };

        let source = source_root.join(&relative);
        let destination = install_root.join(&relative);

        if let Some(parent) = destination.parent() {
            if let Err(error) = fs::create_dir_all(parent) {
                rollback();
                return Err(format!("cannot create {}: {error}", parent.display()));
            }
        }

        if let Err(error) = fs::copy(&source, &destination) {
            rollback();
            return Err(format!(
                "cannot install {} -> {}: {error}",
                source.display(),
                destination.display()
            ));
        }
    }

    if let Err(error) = fs::copy(&source_manifest, install_root.join("manifest.json")) {
        rollback();
        return Err(format!("cannot install manifest: {error}"));
    }

    match validate_package_dir(install_root) {
        Ok(report) => Ok(report),
        Err(error) => {
            rollback();
            Err(format!("installed Hub package failed integrity check: {error}"))
        }
    }
}
// END VERTEX HUB INSTALLER V1
'@

  $hubLib += $installerRust
  WriteUtf8 $hubCrateLib $hubLib

  $installerTest=Join-Path $hubCrate 'tests\installer.rs'
  $installerTestText=@'
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use vsa_vertex_hub::install_registered_package;

#[test]
fn registered_live_flight_package_installs_with_integrity() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..");

    let hub = workspace.join("vertex-hub");

    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();

    let destination = std::env::temp_dir()
        .join(format!("vertex-hub-install-{stamp}"))
        .join("vertex.live-flight-panel")
        .join("1.0.0");

    let result = install_registered_package(
        &hub,
        &destination,
        "vertex.live-flight-panel",
        "1.0.0",
    )
    .expect("registered package must install");

    assert_eq!(result.package_id, "vertex.live-flight-panel");
    assert_eq!(result.version, "1.0.0");
    assert_eq!(result.file_count, 4);

    let _ = std::fs::remove_dir_all(
        destination
            .ancestors()
            .nth(2)
            .expect("temporary install root"),
    );
}
'@
  WriteUtf8 $installerTest $installerTestText

  RunChecked '[hub installer] rustfmt' {
    & $rustfmt.Source --edition 2024 $hubCrateLib $installerTest
  }

  RunChecked '[hub installer] cargo check' {
    & $cargo.Source check --manifest-path $hubCrateCargo --all-targets
  }

  RunChecked '[hub installer] real temp install test' {
    & $cargo.Source test --manifest-path $hubCrateCargo registered_live_flight_package_installs_with_integrity -- --exact
  }

  Write-Host 'Rust Hub Installer: GREEN' -ForegroundColor Green

  Write-Host "`n[3/12] MATERIALIZE REGISTERED PACKAGE INTO VSA SOURCE TREE" -ForegroundColor Yellow

  $manifest=$manifestJson
  if([string]$manifest.package_id -ne $packageId -or [string]$manifest.version -ne $packageVersion){
    throw "Manifest identity mismatch after baseline lock: $($manifest.package_id)@$($manifest.version)"
  }

  New-Item -ItemType Directory -Path $installedPackage -Force|Out-Null

  foreach($file in $manifest.files){
    $rel=[string]$file.path
    AssertSafeRelative $rel

    $source=Join-Path $sourcePackage ($rel.Replace('/','\'))
    $dest=Join-Path $installedPackage ($rel.Replace('/','\'))

    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){
      throw "Registered package file missing: $source"
    }

    $actual=Sha256 $source
    if($actual -ne ([string]$file.sha256).ToLowerInvariant()){
      throw "Source package SHA-256 mismatch before install: $rel"
    }

    $parent=Split-Path -Parent $dest
    New-Item -ItemType Directory -Path $parent -Force|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force

    $installedHash=Sha256 $dest
    if($installedHash -ne $actual){
      throw "Installed package SHA-256 mismatch: $rel"
    }
  }

  Copy-Item -LiteralPath $sourceManifest -Destination (Join-Path $installedPackage 'manifest.json') -Force
  Write-Host "Installed package: $installedPackage" -ForegroundColor Green

  Write-Host "`n[4/12] DOCK HUB VALIDATOR INTO TAURI IPC" -ForegroundColor Yellow

  $tauriCargoText=[IO.File]::ReadAllText($tauriCargo)
  if($tauriCargoText -notmatch '(?m)^\s*vsa-vertex-hub\s*='){
    $dependencies=[regex]::Match($tauriCargoText,'(?m)^\[dependencies\]\s*$')
    if(-not $dependencies.Success){throw 'Tauri [dependencies] anchor missing.'}

    $insert=$dependencies.Index+$dependencies.Length
    $dep="`r`nvsa-vertex-hub = { path = `"../../../ProgramSource/crates/vsa-vertex-hub`" }"
    $tauriCargoText=$tauriCargoText.Insert($insert,$dep)
    WriteUtf8 $tauriCargo $tauriCargoText
  }

  $tauri=[IO.File]::ReadAllText($tauriLib)
  if($tauri.Contains('vertex_hub_registry')){throw 'Tauri Hub IPC already exists.'}

  $hubIpc=@'

// VERTEX HUB IPC V1
#[tauri::command]
fn vertex_hub_registry() -> Result<String, String> {
    let hub = root()?.join("vertex-hub");

    vsa_vertex_hub::validate_registry(&hub)?;

    std::fs::read_to_string(hub.join("registry.json"))
        .map_err(|error| format!("cannot read validated Hub registry: {error}"))
}
// END VERTEX HUB IPC V1

'@

  $runAnchor=$tauri.IndexOf('pub fn run()')
  if($runAnchor -lt 0){throw 'Tauri run() anchor missing.'}
  $tauri=$tauri.Insert($runAnchor,$hubIpc)

  $handler='tauri::generate_handler!['
  $handlerPos=$tauri.IndexOf($handler)
  if($handlerPos -lt 0){throw 'Tauri generate_handler anchor missing.'}
  $listStart=$handlerPos+$handler.Length
  $tauri=$tauri.Insert($listStart,"`n            vertex_hub_registry,")

  WriteUtf8 $tauriLib $tauri

  RunChecked '[hub ipc] rustfmt' {
    & $rustfmt.Source --edition 2024 $tauriLib
  }

  RunChecked '[hub ipc] Tauri cargo check' {
    & $cargo.Source check --manifest-path $tauriCargo --all-targets
  }

  Write-Host 'Validated Hub Registry IPC: ONLINE' -ForegroundColor Green

  Write-Host "`n[5/12] GENERATE VSA HUB CATALOG" -ForegroundColor Yellow

  $componentImport="./packages/$packageId/$packageVersion/src/VertexLiveFlightPanel.vue"

  $catalog=@"
import { markRaw, type Component } from 'vue'
import LiveFlightPanel from '$componentImport'

export interface VertexHubUiPackage {
  packageId: string
  version: string
  displayName: string
  kind: 'ui.component'
  manifestSha256: string
  component: Component
  defaultEnabled: boolean
}

export const vertexHubUiPackages: VertexHubUiPackage[] = [
  {
    packageId: '$packageId',
    version: '$packageVersion',
    displayName: 'Vertex Live Flight Panel',
    kind: 'ui.component',
    manifestSha256: '$(Sha256 $sourceManifest)',
    component: markRaw(LiveFlightPanel),
    defaultEnabled: true,
  },
]
"@
  WriteUtf8 $catalogTs $catalog

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

export async function validatedHubRegistry(): Promise<HubRegistry> {
  const raw = await invoke<string>('vertex_hub_registry')
  return JSON.parse(raw) as HubRegistry
}

export function hubActivationKey(packageId: string, version: string) {
  return `vertex.hub.enabled:${packageId}@${version}`
}

export function isHubPackageEnabled(
  packageId: string,
  version: string,
  defaultEnabled: boolean,
): boolean {
  const value = window.localStorage.getItem(hubActivationKey(packageId, version))
  if (value === null) return defaultEnabled
  return value === '1'
}

export function setHubPackageEnabled(
  packageId: string,
  version: string,
  enabled: boolean,
) {
  window.localStorage.setItem(
    hubActivationKey(packageId, version),
    enabled ? '1' : '0',
  )
}
'@
  WriteUtf8 $runtimeTs $runtime

  Write-Host 'Generated static Hub catalog: GREEN' -ForegroundColor Green

  Write-Host "`n[6/12] BUILD VERTEXHUB DOCK / RUNTIME TOGGLE" -ForegroundColor Yellow

  $hubDock=@'
<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { vertexHubUiPackages } from './catalog'
import {
  isHubPackageEnabled,
  setHubPackageEnabled,
  validatedHubRegistry,
  type HubRegistry,
} from './runtime'

const registry = ref<HubRegistry | null>(null)
const error = ref('')
const managerOpen = ref(false)
const activation = ref<Record<string, boolean>>({})

function key(packageId: string, version: string) {
  return `${packageId}@${version}`
}

for (const pkg of vertexHubUiPackages) {
  activation.value[key(pkg.packageId, pkg.version)] = isHubPackageEnabled(
    pkg.packageId,
    pkg.version,
    pkg.defaultEnabled,
  )
}

const enabledPackages = computed(
  () => vertexHubUiPackages.filter(
    (pkg) => activation.value[key(pkg.packageId, pkg.version)],
  ),
)

const registryOnline = computed(
  () => registry.value?.schema === 'vertex.hub.registry.v1',
)

function registered(pkg: (typeof vertexHubUiPackages)[number]) {
  return Boolean(
    registry.value?.packages.some(
      (entry) =>
        entry.package_id === pkg.packageId
        && entry.version === pkg.version
        && entry.status === 'registered'
        && entry.manifest_sha256 === pkg.manifestSha256,
    ),
  )
}

function toggle(pkg: (typeof vertexHubUiPackages)[number]) {
  if (!registered(pkg)) return

  const packageKey = key(pkg.packageId, pkg.version)
  const next = !activation.value[packageKey]
  activation.value[packageKey] = next
  setHubPackageEnabled(pkg.packageId, pkg.version, next)
}

onMounted(async () => {
  try {
    registry.value = await validatedHubRegistry()
  } catch (reason) {
    error.value = String(reason)
  }
})
</script>

<template>
  <section class="hub-dock">
    <div class="hub-strip">
      <button
        class="hub-button"
        :class="{ online: registryOnline }"
        @click="managerOpen = !managerOpen"
      >
        HUB {{ enabledPackages.length }}/{{ vertexHubUiPackages.length }}
      </button>

      <span v-if="error" class="hub-error">
        HUB VALIDATION RED
      </span>
    </div>

    <div v-if="managerOpen" class="hub-manager">
      <header>
        <strong>VertexHub Equipment</strong>
        <small>
          Registry {{ registryOnline ? 'VALIDATED' : 'OFFLINE' }}
        </small>
      </header>

      <article
        v-for="pkg in vertexHubUiPackages"
        :key="key(pkg.packageId, pkg.version)"
      >
        <div>
          <strong>{{ pkg.displayName }}</strong>
          <small>{{ pkg.packageId }}@{{ pkg.version }}</small>
        </div>

        <span :class="{ ok: registered(pkg) }">
          {{ registered(pkg) ? 'VERIFIED' : 'UNVERIFIED' }}
        </span>

        <button
          :disabled="!registered(pkg)"
          @click="toggle(pkg)"
        >
          {{
            activation[key(pkg.packageId, pkg.version)]
              ? 'DISABLE'
              : 'ENABLE'
          }}
        </button>
      </article>

      <pre v-if="error">{{ error }}</pre>
    </div>

    <component
      :is="pkg.component"
      v-for="pkg in enabledPackages"
      :key="key(pkg.packageId, pkg.version)"
      v-show="registered(pkg)"
    />
  </section>
</template>

<style scoped>
.hub-dock {
  position: relative;
  min-width: 0;
}
.hub-strip {
  position: absolute;
  z-index: 8;
  top: 4px;
  right: 6px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.hub-button {
  border: 1px solid #334057;
  border-radius: 4px;
  background: #111925;
  color: #8290a5;
  padding: 3px 6px;
  font: 8px ui-monospace, Consolas, monospace;
  cursor: pointer;
}
.hub-button.online {
  border-color: #316e5a;
  color: #65e0b1;
}
.hub-error {
  color: #ff8292;
  font: 8px ui-monospace, Consolas, monospace;
}
.hub-manager {
  position: absolute;
  z-index: 20;
  top: 28px;
  right: 6px;
  width: min(520px, calc(100vw - 24px));
  border: 1px solid #334057;
  border-radius: 7px;
  background: #0c121c;
  box-shadow: 0 14px 34px rgba(0, 0, 0, .42);
  color: #dce5f3;
  overflow: hidden;
}
.hub-manager header,
.hub-manager article {
  display: grid;
  grid-template-columns: 1fr auto auto;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-bottom: 1px solid #202a3a;
}
.hub-manager header {
  grid-template-columns: 1fr auto;
  background: #111a27;
}
.hub-manager strong,
.hub-manager small {
  display: block;
}
.hub-manager small {
  margin-top: 2px;
  color: #7e8ca2;
  font: 9px ui-monospace, Consolas, monospace;
}
.hub-manager span {
  color: #8a96a8;
  font: 9px ui-monospace, Consolas, monospace;
}
.hub-manager span.ok {
  color: #64dcae;
}
.hub-manager button {
  border: 1px solid #38465e;
  border-radius: 4px;
  background: #141e2c;
  color: #d5deec;
  padding: 4px 7px;
  font-size: 9px;
  cursor: pointer;
}
.hub-manager button:disabled {
  opacity: .4;
  cursor: not-allowed;
}
.hub-manager pre {
  max-height: 140px;
  margin: 0;
  padding: 8px 10px;
  overflow: auto;
  color: #ff8a98;
  white-space: pre-wrap;
  font: 9px Consolas, monospace;
}
</style>
'@
  WriteUtf8 $hubDockVue $hubDock

  Write-Host 'VertexHubDock: CREATED' -ForegroundColor Green

  Write-Host "`n[7/12] MIGRATE EDITOR FROM DIRECT COMPONENT TO HUB LOADER" -ForegroundColor Yellow

  $editorText=[IO.File]::ReadAllText($editor)

  $oldImport="import VertexLiveFlightPanel from './VertexLiveFlightPanel.vue'"
  if(-not $editorText.Contains($oldImport)){
    throw 'Direct Live Flight import not found; refusing ambiguous migration.'
  }

  if(-not $editorText.Contains('<VertexLiveFlightPanel />')){
    throw 'Direct Live Flight render anchor not found.'
  }

  $editorText=$editorText.Replace(
    $oldImport,
    "import VertexHubDock from '../vertex-hub/VertexHubDock.vue'"
  )
  $editorText=$editorText.Replace(
    '<VertexLiveFlightPanel />',
    '<VertexHubDock />'
  )

  WriteUtf8 $editor $editorText

  Write-Host 'Direct panel import          : REMOVED' -ForegroundColor Green
  Write-Host 'VertexHubDock import         : INSTALLED' -ForegroundColor Green
  Write-Host 'Live Flight source provider  : VERTEXHUB' -ForegroundColor Green

  Write-Host "`n[8/12] FRONTEND TYPECHECK / BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[loader] vue-tsc' {& $pnpm.Source exec vue-tsc --noEmit}
    RunChecked '[loader] vite build' {& $pnpm.Source exec vite build}
  }finally{Pop-Location}

  Write-Host "`n[9/12] HUB INSTALLATION INTEGRITY CROSS-CHECK" -ForegroundColor Yellow

  $installedManifest=Join-Path $installedPackage 'manifest.json'
  if(-not(Test-Path -LiteralPath $installedManifest)){throw 'Installed manifest missing.'}

  foreach($file in $manifest.files){
    $rel=[string]$file.path
    $dest=Join-Path $installedPackage ($rel.Replace('/','\'))
    if(-not(Test-Path -LiteralPath $dest)){throw "Installed file missing: $rel"}
    if((Sha256 $dest) -ne ([string]$file.sha256).ToLowerInvariant()){
      throw "Installed file integrity RED: $rel"
    }
  }

  $editorNow=[IO.File]::ReadAllText($editor)
  if($editorNow.Contains($oldImport)){throw 'Direct Live Flight import still present.'}
  if(-not $editorNow.Contains("import VertexHubDock from '../vertex-hub/VertexHubDock.vue'")){
    throw 'VertexHubDock import missing.'
  }

  Write-Host 'Installed package hashes     : VERIFIED' -ForegroundColor Green
  Write-Host 'Direct/hub migration         : VERIFIED' -ForegroundColor Green

  Write-Host "`n[10/12] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

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

  Write-Host "`n[11/12] STATIC LOADER SAFETY AUDIT" -ForegroundColor Yellow

  $catalogNow=[IO.File]::ReadAllText($catalogTs)
  $runtimeNow=[IO.File]::ReadAllText($runtimeTs)
  $dockNow=[IO.File]::ReadAllText($hubDockVue)

  $audits=@(
    [pscustomobject]@{
      Name='static component import'
      Pass=[bool]$catalogNow.Contains("import LiveFlightPanel from './packages/")
    },
    [pscustomobject]@{
      Name='no arbitrary URL loader'
      Pass=[bool](
        -not $catalogNow.Contains('http://') -and
        -not $catalogNow.Contains('https://')
      )
    },
    [pscustomobject]@{
      Name='validated registry IPC'
      Pass=[bool]$runtimeNow.Contains("invoke<string>('vertex_hub_registry')")
    },
    [pscustomobject]@{
      Name='runtime enable/disable'
      Pass=[bool]$dockNow.Contains('setHubPackageEnabled')
    },
    [pscustomobject]@{
      Name='verified gate'
      Pass=[bool]$dockNow.Contains("registered(pkg) ? 'VERIFIED' : 'UNVERIFIED'")
    },
    [pscustomobject]@{
      Name='controller mutation absent'
      Pass=[bool](-not $dockNow.Contains('FleetControllerSession'))
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){
      throw "Loader safety audit RED: $($audit.Name)"
    }
    Write-Host ("  {0,-30} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[12/12] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.vertex-hub-installer-loader.v3'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    package=[ordered]@{
      package_id=$packageId
      version=$packageVersion
      source=$sourcePackage
      installed=$installedPackage
      registry=$hubRegistry
    }
    installer=[ordered]@{
      rust_contract='install_registered_package'
      registry_gate='ENFORCED'
      manifest_hash_gate='ENFORCED'
      file_hash_gate='ENFORCED'
      traversal='DENIED'
      rollback_on_install_failure='ACTIVE'
    }
    loader=[ordered]@{
      catalog=$catalogTs
      runtime=$runtimeTs
      dock=$hubDockVue
      loading='STATIC_BUILD_TIME'
      runtime_toggle='ENABLE_DISABLE'
      arbitrary_remote_import='DENIED'
      registry_validation='TAURI_RUST'
    }
    migration=[ordered]@{
      previous='DIRECT_VERTEX_LIVE_FLIGHT_PANEL'
      current='VERTEX_HUB_DOCK'
      live_runtime_path='UNCHANGED'
      controller_state_mutation=$false
    }
    validation=[ordered]@{
      hub_installer_test='GREEN'
      tauri_check='GREEN'
      frontend_typecheck='GREEN'
      frontend_build='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
      installed_hashes='VERIFIED'
      static_loader_safety_audit='GREEN'
    }
    next_target='VERTEXHUB HOT INSTALL / PACKAGE BROWSER'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX — VERTEXHUB INSTALLER / LOADER V3 GREEN
============================================================
 VertexHub Registry                     VALIDATED
 Rust Hub Installer                     ONLINE
 Registered Package Install             VERIFIED
 Installed Package SHA-256              VERIFIED
 Tauri Hub Registry IPC                 ONLINE
 Generated Static Catalog               ONLINE
 VertexHubDock                          ONLINE
 Runtime Enable / Disable               ONLINE
 Direct Live Flight Import              REMOVED
 Live Flight Provider                   VERTEXHUB
 Arbitrary Remote Import                DENIED
 Path Traversal                         DENIED
 Controller State Mutation              DENIED
 Tauri Check                            GREEN
 Frontend Typecheck                     GREEN
 Frontend Build                         GREEN
 Workspace Release Gate                 GREEN
------------------------------------------------------------
 PACKAGE: $packageId@$packageVersion
 SOURCE:  $sourcePackage
 INSTALL: $installedPackage
 REPORT:  $report
------------------------------------------------------------
 NEXT TARGET: VERTEXHUB HOT INSTALL / PACKAGE BROWSER
============================================================
 VSA IS NOW LOADING EQUIPMENT THROUGH VERTEXHUB
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VERTEXHUB INSTALLER / LOADER V3 RED — DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  foreach($p in @($hubCrateLib,$tauriCargo,$tauriLib,$editor,$catalogTs,$runtimeTs,$hubDockVue)){
    if(Test-Path -LiteralPath $p){
      Copy-Item -LiteralPath $p -Destination (Join-Path $failed ([IO.Path]::GetFileName($p))) -Force -ErrorAction SilentlyContinue
    }
  }

  $restore=@(
    @('vsa-vertex-hub.Cargo.toml',$hubCrateCargo),
    @('vsa-vertex-hub.lib.rs',$hubCrateLib),
    @('vsa-shell-desktop.Cargo.toml',$tauriCargo),
    @('vsa-shell-desktop.lib.rs',$tauriLib),
    @('VertexEditorDock.vue',$editor)
  )

  foreach($pair in $restore){
    $src=Join-Path $backup $pair[0]
    if(Test-Path -LiteralPath $src){
      Copy-Item -LiteralPath $src -Destination $pair[1] -Force
    }
  }

  $installerTest=Join-Path $hubCrate 'tests\installer.rs'
  if(Test-Path -LiteralPath $installerTest){
    Remove-Item -LiteralPath $installerTest -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $loaderRoot){
    Remove-Item -LiteralPath $loaderRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Host 'Hub crate rollback            : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Tauri rollback                : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Editor rollback               : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Installed loader source       : REMOVED' -ForegroundColor Yellow
  Write-Host 'Original Hub registry/package : UNTOUCHED' -ForegroundColor Yellow
  Write-Host 'V11 Live Runtime              : UNTOUCHED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}