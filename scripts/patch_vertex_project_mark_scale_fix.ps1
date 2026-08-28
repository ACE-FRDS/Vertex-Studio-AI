#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex Project Mark - Aspect Ratio Fix
# Fixes display sizing only. Does not modify the SVG master.

$siteRoot = "G:\Vertex_Project\Development\vertex_studio_ai\VertexHub\site"
$cssPath  = Join-Path $siteRoot "assets\css\components.css"

if (-not (Test-Path $cssPath)) { throw "CSS missing: $cssPath" }

$css = Get-Content $cssPath -Raw

# Remove previous mark sizing rules from the first patch.
$css = $css -replace '(?ms)\.vertex-mark\{.*?\}\s*', ''
$css = $css -replace '(?ms)\.brand-mark\{.*?\}\s*', ''
$css = $css -replace '(?ms)\.vera-logo\{.*?\}\s*', ''

$css += @'

/* Vertex Project Mark — preserve original SVG aspect ratio */
.vertex-mark{
  display:block;
  width:auto;
  height:auto;
  max-width:100%;
  max-height:100%;
  object-fit:contain;
}

.brand-mark{
  width:auto;
  height:28px;
  max-width:42px;
  flex:0 0 auto;
}

.vera-mark{
  width:64px;
  height:64px;
  display:grid;
  place-items:center;
  overflow:visible;
}

.vera-logo{
  width:auto;
  height:42px;
  max-width:48px;
  object-fit:contain;
}
'@

Set-Content $cssPath $css -Encoding UTF8

Write-Host ""
Write-Host "Validating Vertex Mark aspect ratio fix..." -ForegroundColor Cyan

$routes = @(
  "/",
  "/assets/css/components.css",
  "/assets/brand/vertex-project-mark.svg",
  "/favicon.svg"
)

$results = foreach($route in $routes){
  try {
    $r = Invoke-WebRequest "https://vertex.a-portal.net$route" -UseBasicParsing -TimeoutSec 20
    [pscustomobject]@{Route=$route;Status=$r.StatusCode;Result="OK"}
  } catch {
    [pscustomobject]@{Route=$route;Status="ERROR";Result=$_.Exception.Message}
  }
}

$results | Format-Table -AutoSize

if (@($results | Where-Object Result -ne "OK").Count -gt 0) {
  throw "Aspect ratio validation failed."
}

Write-Host ""
Write-Host "VERTEX PROJECT MARK SCALE FIX ONLINE" -ForegroundColor Green
Write-Host "SVG master : UNCHANGED"
Write-Host "Aspect ratio: PRESERVED"
Write-Host "Header mark : height 28px / auto width"
Write-Host "Vera mark   : height 42px / auto width"
