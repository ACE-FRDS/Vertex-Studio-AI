$Global:VERTEX_ROOT = (Resolve-Path -LiteralPath $PSScriptRoot).Path

$Global:VERTEX_ARD_ROOT = Join-Path `
    $Global:VERTEX_ROOT `
    '_incoming\Vertex_Chappy_Mothership_Rust_Genesis_Pack\Vertex_Chappy_Mothership_Rust_Genesis_Pack'

$Global:VERTEX_ARDCTL = Join-Path `
    $Global:VERTEX_ARD_ROOT `
    'target\release\vertex-ardctl.exe'

$Global:VERTEX_HARNESSD = Join-Path `
    $Global:VERTEX_ARD_ROOT `
    'target\release\vertex-harnessd.exe'

$Global:VERTEX_CTL = Join-Path `
    $Global:VERTEX_ARD_ROOT `
    'target\release\vertexctl.exe'

$Global:VERTEX_ARD_STATE = Join-Path `
    $Global:VERTEX_ROOT `
    'STATE\ard-v2.json'

$Global:VERTEX_VVE_ROOT = Join-Path `
    $Global:VERTEX_ROOT `
    'VVE'

if (-not $env:VERTEX_LM_STUDIO_BASE_URL) {
    $env:VERTEX_LM_STUDIO_BASE_URL = 'http://127.0.0.1:1234/v1'
}

$required = @(
    $Global:VERTEX_ARDCTL,
    $Global:VERTEX_HARNESSD,
    $Global:VERTEX_CTL,
    $Global:VERTEX_ARD_STATE,
    $Global:VERTEX_VVE_ROOT
)

foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        throw "Vertex environment path missing: $path"
    }
}

Write-Host ''
Write-Host 'VERTEX ENVIRONMENT READY' -ForegroundColor Green
Write-Host "ROOT      : $Global:VERTEX_ROOT"
Write-Host "ARD ROOT  : $Global:VERTEX_ARD_ROOT"
Write-Host "ARD STATE : $Global:VERTEX_ARD_STATE"
Write-Host "ARDCTL    : $Global:VERTEX_ARDCTL"
Write-Host "HARNESSD  : $Global:VERTEX_HARNESSD"
Write-Host "VERTEXCTL : $Global:VERTEX_CTL"
Write-Host "VVE       : $Global:VERTEX_VVE_ROOT"
Write-Host "LM STUDIO : $env:VERTEX_LM_STUDIO_BASE_URL"
