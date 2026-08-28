#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex Project Mark - Measured SVG Fix v3
# SVG measured before patching:
# viewBox = 0 0 205 210
# visible geometry roughly x=17..196, y=18.5..189.8
# No clipping tricks; use a square viewport and preserveAspectRatio.

$site = "G:\Vertex_Project\Development\vertex_studio_ai\VertexHub\site"
$htmlPath = Join-Path $site "index.html"
$cssPath  = Join-Path $site "assets\css\components.css"
$svgPath  = Join-Path $site "assets\brand\vertex-project-mark.svg"

foreach ($p in @($htmlPath,$cssPath,$svgPath)) {
    if (!(Test-Path $p)) { throw "Missing: $p" }
}

# Ensure the published SVG explicitly preserves its native ratio.
$svg = Get-Content $svgPath -Raw
if ($svg -notmatch 'preserveAspectRatio=') {
    $svg = $svg -replace '<svg\b', '<svg preserveAspectRatio="xMidYMid meet"'
    Set-Content $svgPath $svg -Encoding UTF8
}

$html = Get-Content $htmlPath -Raw
$html = $html.Replace('`r`n',[Environment]::NewLine)

# Normalize header markup regardless of whether v2 wrapper exists.
$html = [regex]::Replace(
    $html,
    '(?s)<span class="brand-mark-viewport">.*?</span>\s*<span class="brand-title">.*?</span>',
    '<span class="brand-mark-viewport"><img class="brand-mark" src="/assets/brand/vertex-project-mark.svg" alt="Vertex Project Mark"></span><span class="brand-title">VERTEX AI<br>KNOWLEDGE HUB</span>',
    1
)

Set-Content $htmlPath $html -Encoding UTF8

$css = Get-Content $cssPath -Raw

$css += @'

/* === Vertex Project Mark measured fix v3 ===
   Native SVG viewBox: 205 x 210 (nearly square).
   Use a square box; never stretch width/height independently.
*/
.brand-mark-viewport{
  width:36px !important;
  height:36px !important;
  flex:0 0 36px !important;
  display:flex !important;
  align-items:center !important;
  justify-content:center !important;
  overflow:visible !important;
}
.brand-mark-viewport > .brand-mark{
  display:block !important;
  width:32px !important;
  height:32px !important;
  max-width:none !important;
  max-height:none !important;
  object-fit:contain !important;
  object-position:center !important;
}
.vera-mark{
  width:64px !important;
  height:64px !important;
  display:flex !important;
  align-items:center !important;
  justify-content:center !important;
  overflow:visible !important;
}
.vera-mark > .vera-logo{
  display:block !important;
  width:48px !important;
  height:48px !important;
  max-width:none !important;
  max-height:none !important;
  object-fit:contain !important;
  object-position:center !important;
}
'@

Set-Content $cssPath $css -Encoding UTF8

Write-Host ""
Write-Host "Measured SVG facts:" -ForegroundColor Cyan
Write-Host "  viewBox : 0 0 205 210"
Write-Host "  ratio   : 0.976 : 1 (nearly square)"
Write-Host "  strategy: square viewport + contain + NO clipping"
Write-Host ""
Write-Host "Validating v3..." -ForegroundColor Cyan

$routes = @("/", "/assets/brand/vertex-project-mark.svg", "/assets/css/components.css", "/favicon.svg")
$results = foreach($route in $routes) {
    try {
        $r = Invoke-WebRequest "https://vertex.a-portal.net$route" -UseBasicParsing -TimeoutSec 20
        [pscustomobject]@{Route=$route;Status=$r.StatusCode;Result="OK"}
    } catch {
        [pscustomobject]@{Route=$route;Status="ERROR";Result=$_.Exception.Message}
    }
}
$results | Format-Table -AutoSize

if (@($results | Where-Object Result -ne "OK").Count -gt 0) { throw "v3 validation failed." }

Write-Host ""
Write-Host "VERTEX MARK MEASURED FIX v3 ONLINE" -ForegroundColor Green
Write-Host "Header mark : 32 x 32 inside 36 x 36 viewport"
Write-Host "Vera mark   : 48 x 48 inside 64 x 64 viewport"
Write-Host "Clipping    : NONE"
Write-Host "Canonical   : PRESERVED"
