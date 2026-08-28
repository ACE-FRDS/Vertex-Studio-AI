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