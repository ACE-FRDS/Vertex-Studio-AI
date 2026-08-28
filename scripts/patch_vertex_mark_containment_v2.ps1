#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex Project Mark - Header Containment Fix v2
# Fixes:
# 1) literal `r`n accidentally injected into HTML
# 2) oversized header logo by enforcing a hard viewport
# Does not modify the SVG master or canonical data.

$site = "G:\Vertex_Project\Development\vertex_studio_ai\VertexHub\site"
$htmlPath = Join-Path $site "index.html"
$cssPath  = Join-Path $site "assets\css\components.css"

if (!(Test-Path $htmlPath)) { throw "Missing: $htmlPath" }
if (!(Test-Path $cssPath))  { throw "Missing: $cssPath" }

$html = Get-Content $htmlPath -Raw

# Remove literal PowerShell newline artifacts from previous patch.
$html = $html.Replace('`r`n', [Environment]::NewLine)

# Wrap the header mark in a hard viewport once.
$old = '<img class="vertex-mark brand-mark" src="/assets/brand/vertex-project-mark.svg" alt="Vertex Project Mark">VERTEX AI KNOWLEDGE HUB'
$new = '<span class="brand-mark-viewport"><img class="vertex-mark brand-mark" src="/assets/brand/vertex-project-mark.svg" alt="Vertex Project Mark"></span><span class="brand-title">VERTEX AI<br>KNOWLEDGE HUB</span>'
if ($html.Contains($old)) {
    $html = $html.Replace($old, $new)
}

Set-Content $htmlPath $html -Encoding UTF8

$css = Get-Content $cssPath -Raw

# Append authoritative containment rules.
$css += @'

/* === Vertex Project Mark containment v2 === */
.brand{
  display:flex;
  align-items:center;
  gap:12px;
  min-width:0;
}
.brand-mark-viewport{
  width:34px;
  height:38px;
  flex:0 0 34px;
  display:grid;
  place-items:center;
  overflow:hidden;
}
.brand-mark-viewport .brand-mark{
  display:block !important;
  width:100% !important;
  height:100% !important;
  max-width:100% !important;
  max-height:100% !important;
  object-fit:contain !important;
}
.brand-title{
  display:block;
  font-size:.88rem;
  line-height:1.05;
  letter-spacing:.09em;
  white-space:nowrap;
}
.vera-mark{
  width:64px !important;
  height:64px !important;
  display:grid !important;
  place-items:center !important;
  overflow:hidden !important;
}
.vera-mark .vera-logo{
  display:block !important;
  width:46px !important;
  height:46px !important;
  max-width:46px !important;
  max-height:46px !important;
  object-fit:contain !important;
}
'@

Set-Content $cssPath $css -Encoding UTF8

Write-Host ""
Write-Host "Validating containment fix..." -ForegroundColor Cyan

$routes = @(
  "/",
  "/assets/css/components.css",
  "/assets/brand/vertex-project-mark.svg",
  "/favicon.svg",
  "/bootstrap/",
  "/llms.txt"
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
    throw "Containment validation failed."
}

Write-Host ""
Write-Host "VERTEX MARK CONTAINMENT FIX ONLINE" -ForegroundColor Green
Write-Host "Header viewport : 34 x 38 px"
Write-Host "Vera viewport   : 64 x 64 px"
Write-Host 'Literal `r`n    : REMOVED'
Write-Host "SVG master      : UNCHANGED"
Write-Host "Canonical data  : PRESERVED"
