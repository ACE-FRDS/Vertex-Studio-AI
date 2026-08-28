& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC - GUI DEV BUILD ISOLATION V1
#
# Fix:
#   Vite was watching src-tauri\target and Windows returned EBUSY
#   while Rust/Tauri was compiling executable build artifacts.
#
# Strategy:
#   1. Move existing src-tauri\target outside the Vite UI root.
#   2. Preserve/reuse that Cargo cache when possible.
#   3. Set CARGO_TARGET_DIR permanently in the GUI dev launcher.
#   4. Keep Vite HMR watching frontend source only.
#   5. Rewrite launcher with ASCII-only banner for PS 5.1.
#
# No application source contract changes.
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$tauriRoot=Join-Path $ui 'src-tauri'
$oldTarget=Join-Path $tauriRoot 'target'
$buildRoot=Join-Path $startup '_build'
$newTarget=Join-Path $buildRoot 'VSA_TAURI_DEV'
$launcher=Join-Path $startup 'START_VERTEX_GUI_DEV.ps1'
$reports=Join-Path $core '_vertex_reports'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$launcherBackup=Join-Path $reports "START_VERTEX_GUI_DEV.before-build-isolation.$stamp.ps1"
$report=Join-Path $reports "GUI_DEV_BUILD_ISOLATION_V1.$stamp.json"

$utf8Bom=New-Object System.Text.UTF8Encoding($true)

function WriteUtf8Bom([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8Bom)
}

Write-Host @'
============================================================
 VERTEX - GUI DEV BUILD ISOLATION V1
 REMOVE RUST BUILD OUTPUT FROM VITE WATCH ROOT
============================================================
'@ -ForegroundColor Cyan

foreach($required in @($startup,$base,$ui,$core,$tauriRoot,$launcher,$reports)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required artifact missing: $required"
  }
}

$launcherText=[IO.File]::ReadAllText($launcher)
if(-not $launcherText.Contains('tauri dev')){
  throw 'GUI dev launcher does not contain tauri dev; refusing blind patch.'
}

Write-Host "`n[1/5] BACKUP LAUNCHER" -ForegroundColor Yellow
Copy-Item -LiteralPath $launcher -Destination $launcherBackup -Force
Write-Host "Backup: $launcherBackup" -ForegroundColor Green

Write-Host "`n[2/5] ISOLATE CARGO BUILD OUTPUT" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $buildRoot -Force|Out-Null

if(Test-Path -LiteralPath $oldTarget){
  if(Test-Path -LiteralPath $newTarget){
    $existingFiles=@(Get-ChildItem -LiteralPath $newTarget -Force -ErrorAction SilentlyContinue)
    if($existingFiles.Count -gt 0){
      $legacy=Join-Path $buildRoot "VSA_TAURI_DEV_PREVIOUS.$stamp"
      Move-Item -LiteralPath $newTarget -Destination $legacy
      Write-Host "Existing isolated cache moved: $legacy" -ForegroundColor DarkGray
    }else{
      Remove-Item -LiteralPath $newTarget -Force
    }
  }

  try{
    Move-Item -LiteralPath $oldTarget -Destination $newTarget -ErrorAction Stop
    Write-Host 'Existing src-tauri target cache : MOVED + PRESERVED' -ForegroundColor Green
  }catch{
    Write-Host 'Cache move failed; attempting generated-target cleanup...' -ForegroundColor Yellow
    try{
      Remove-Item -LiteralPath $oldTarget -Recurse -Force -ErrorAction Stop
      New-Item -ItemType Directory -Path $newTarget -Force|Out-Null
      Write-Host 'Old generated target           : REMOVED' -ForegroundColor Green
    }catch{
      throw @"
Cannot relocate or remove:
$oldTarget

A stale cargo/rustc/tauri process may still hold a build artifact.
Close any remaining VSA/Tauri development process and rerun this strike.

Underlying error:
$($_.Exception.Message)
"@
    }
  }
}else{
  New-Item -ItemType Directory -Path $newTarget -Force|Out-Null
  Write-Host 'src-tauri target cache          : NOT_PRESENT' -ForegroundColor DarkGray
}

if(Test-Path -LiteralPath $oldTarget){
  throw 'src-tauri\target still exists inside the Vite watch root.'
}

Write-Host "Cargo target: $newTarget" -ForegroundColor Green

Write-Host "`n[3/5] REWRITE GUI DEV LAUNCHER" -ForegroundColor Yellow

$launcherNew=@'
& {
$ErrorActionPreference='Stop'

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ui=Join-Path $startup 'VSA_Startup_Package_v0.2\apps\vsa-shell'
$cargoTarget=Join-Path $startup '_build\VSA_TAURI_DEV'

if(-not(Test-Path -LiteralPath $ui)){
  throw "VSA UI root missing: $ui"
}

$pnpm=Get-Command pnpm -ErrorAction SilentlyContinue
if(-not $pnpm){
  throw 'pnpm is not available.'
}

New-Item -ItemType Directory -Path $cargoTarget -Force|Out-Null

# CRITICAL:
# Keep Rust/Tauri generated binaries outside apps\vsa-shell.
# Vite watches the UI tree; Windows can return EBUSY when it tries
# to watch executable build artifacts inside src-tauri\target.
$env:CARGO_TARGET_DIR=$cargoTarget

Write-Host @"
============================================================
 VERTEX - GUI LIVE DEVELOPMENT
============================================================
 Editor + GUI Preview                  ONLINE TARGET
 F10                                   TOGGLE PREVIEW
 Save                                  VITE HMR
 Preview Registry                      STATIC / TRUSTED
 VertexHub Components                  PREVIEWABLE
 Cargo Build Output                    ISOLATED
 Cargo Target                          $cargoTarget
 Arbitrary Runtime Code                DENIED
------------------------------------------------------------
 Close this process to stop Dev Mode.
============================================================
"@ -ForegroundColor Cyan

Push-Location $ui
try{
  & $pnpm.Source exec tauri dev
  if($LASTEXITCODE -ne 0){
    throw "Tauri dev exited RED ($LASTEXITCODE)"
  }
}finally{
  Pop-Location
}
}
'@

WriteUtf8Bom $launcher $launcherNew

$verify=[IO.File]::ReadAllText($launcher)
foreach($needle in @(
  '$env:CARGO_TARGET_DIR=$cargoTarget',
  '_build\VSA_TAURI_DEV',
  'pnpm.Source exec tauri dev'
)){
  if(-not $verify.Contains($needle)){
    Copy-Item -LiteralPath $launcherBackup -Destination $launcher -Force
    throw "Launcher verification RED: missing $needle"
  }
}

Write-Host 'GUI dev launcher              : UPDATED' -ForegroundColor Green
Write-Host 'CARGO_TARGET_DIR              : ISOLATED' -ForegroundColor Green
Write-Host 'PowerShell 5.1 banner         : ASCII SAFE' -ForegroundColor Green

Write-Host "`n[4/5] WATCH-ROOT SAFETY CHECK" -ForegroundColor Yellow

$uiCanonical=[IO.Path]::GetFullPath($ui).TrimEnd('\')+'\'
$newCanonical=[IO.Path]::GetFullPath($newTarget).TrimEnd('\')+'\'

if($newCanonical.StartsWith($uiCanonical,[StringComparison]::OrdinalIgnoreCase)){
  Copy-Item -LiteralPath $launcherBackup -Destination $launcher -Force
  throw 'New Cargo target is still inside Vite UI root.'
}

if(Test-Path -LiteralPath $oldTarget){
  Copy-Item -LiteralPath $launcherBackup -Destination $launcher -Force
  throw 'Old src-tauri target remains inside Vite UI root.'
}

Write-Host 'Vite UI watch root            : CLEAN' -ForegroundColor Green
Write-Host 'Rust generated EXE path       : OUTSIDE UI ROOT' -ForegroundColor Green
Write-Host 'EBUSY watch collision class   : REMOVED' -ForegroundColor Green

Write-Host "`n[5/5] REPORT" -ForegroundColor Yellow

[ordered]@{
  schema='vertex.cic.gui-dev-build-isolation.v1'
  timestamp=(Get-Date).ToString('o')
  status='GREEN'
  vite_ui_root=$ui
  old_cargo_target=$oldTarget
  cargo_target=$newTarget
  old_target_inside_vite_root=$false
  cargo_target_inside_vite_root=$false
  launcher=$launcher
  launcher_backup=$launcherBackup
  fix=[ordered]@{
    cargo_target_dir='ISOLATED'
    previous_cache='PRESERVED_WHEN_POSSIBLE'
    vite_rust_exe_watch='REMOVED'
    powershell_51_banner='ASCII_SAFE'
  }
}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $report -Encoding UTF8

Write-Host @"
============================================================
 VERTEX - GUI DEV BUILD ISOLATION GREEN
============================================================
 Vite                              READY
 Tauri devUrl                      localhost:5173
 Rust Build Output                 OUTSIDE VITE ROOT
 CARGO_TARGET_DIR                  ISOLATED
 Previous Cargo Cache              PRESERVED WHEN POSSIBLE
 EBUSY Watch Collision             REMOVED
 GUI Dev Launcher                  UPDATED
------------------------------------------------------------
 NEXT:
 & "$launcher"
------------------------------------------------------------
 THE BLINDFOLD STAYS OFF.
============================================================
"@ -ForegroundColor Green
}